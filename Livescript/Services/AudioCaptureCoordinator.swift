import AVFoundation
import Foundation
import ScreenCaptureKit
import CoreMedia

enum AudioCaptureError: LocalizedError {
    case inputUnavailable
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .inputUnavailable:
            return "Audio input is unavailable."
        case .conversionFailed:
            return "Failed to convert captured audio."
        }
    }
}

final class AudioCaptureCoordinator {
    private let micEngine = AVAudioEngine()
    private var micConverter: AVAudioConverter?
    private var systemCapture: SystemAudioCapture?
    private let queue = DispatchQueue(label: "AudioCaptureCoordinator.queue")

    private var latestMicChunk: [Float] = []
    private var latestSystemChunk: [Float] = []
    private var sourceMode: TranscriptSourceMode = .mic

    var onPCMChunk: (([Float]) -> Void)?

    func start(sourceMode: TranscriptSourceMode) throws {
        self.sourceMode = sourceMode
        if sourceMode == .mic || sourceMode == .mixed {
            try startMicrophone()
        }
        if sourceMode == .system || sourceMode == .mixed {
            startSystemAudio()
        }
    }

    func stop() {
        micEngine.inputNode.removeTap(onBus: 0)
        micEngine.stop()
        systemCapture?.stop()
        systemCapture = nil
    }

    private func startMicrophone() throws {
        let input = micEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let targetFormat = try Self.makeTargetFormat()

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.conversionFailed
        }
        self.micConverter = converter

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let mono = self.convertToMono16K(buffer: buffer, converter: converter, targetFormat: targetFormat) else { return }
            self.handleIncomingChunk(mono, kind: .mic)
        }

        micEngine.prepare()
        try micEngine.start()
    }

    private func startSystemAudio() {
        let capture = SystemAudioCapture { [weak self] chunk in
            self?.handleIncomingChunk(chunk, kind: .system)
        }
        self.systemCapture = capture
        capture.start()
    }

    private func handleIncomingChunk(_ chunk: [Float], kind: InputKind) {
        queue.async { [weak self] in
            guard let self else { return }
            switch kind {
            case .mic:
                self.latestMicChunk = chunk
            case .system:
                self.latestSystemChunk = chunk
            }

            let output: [Float]
            switch self.sourceMode {
            case .mic:
                output = self.latestMicChunk
            case .system:
                output = self.latestSystemChunk
            case .mixed:
                output = Self.mix(self.latestMicChunk, self.latestSystemChunk)
            }
            guard !output.isEmpty else { return }
            self.onPCMChunk?(output)
        }
    }

    private static func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        let count = min(a.count, b.count)
        guard count > 0 else { return a.isEmpty ? b : a }
        var mixed = [Float](repeating: 0, count: count)
        for i in 0..<count {
            mixed[i] = (a[i] + b[i]) * 0.5
        }
        return mixed
    }

    private static func makeTargetFormat() throws -> AVAudioFormat {
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.conversionFailed
        }
        return target
    }

    private func convertToMono16K(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) -> [Float]? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return nil }

        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil, let channelData = output.floatChannelData?[0] else {
            return nil
        }

        let count = Int(output.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: count))
    }

    private enum InputKind {
        case mic
        case system
    }
}

private final class SystemAudioCapture: NSObject {
    private var stream: SCStream?
    private let output = SystemAudioOutput()
    private let queue = DispatchQueue(label: "SystemAudioCapture.stream")

    init(onChunk: @escaping ([Float]) -> Void) {
        super.init()
        output.onChunk = onChunk
    }

    func start() {
        Task {
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first else { return }

                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.captureMicrophone = false
                config.sampleRate = 16_000
                config.channelCount = 1
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)

                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                self.stream = stream

                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)
                try await stream.startCapture()
            } catch {
                // Permission denied or capture unsupported: keep silent, caller handles no-data state.
            }
        }
    }

    func stop() {
        Task {
            try? await stream?.stopCapture()
            stream = nil
        }
    }
}

private final class SystemAudioOutput: NSObject, SCStreamOutput {
    var onChunk: (([Float]) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        guard let pcm = sampleBuffer.floatSamples() else { return }
        onChunk?(pcm)
    }
}

private extension CMSampleBuffer {
    func floatSamples() -> [Float]? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(self),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }
        let asbd = asbdPointer.pointee

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer())
        var sizeNeeded: Int = 0

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let buffer = audioBufferList.mBuffers
        guard let data = buffer.mData else { return nil }
        let byteCount = Int(buffer.mDataByteSize)
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let sampleCount = byteCount / MemoryLayout<Float>.stride
            let ptr = data.bindMemory(to: Float.self, capacity: sampleCount)
            return Array(UnsafeBufferPointer(start: ptr, count: sampleCount))
        }
        if asbd.mBitsPerChannel == 16 {
            let sampleCount = byteCount / MemoryLayout<Int16>.stride
            let ptr = data.bindMemory(to: Int16.self, capacity: sampleCount)
            return (0..<sampleCount).map { Float(ptr[$0]) / Float(Int16.max) }
        }
        return nil
    }
}
