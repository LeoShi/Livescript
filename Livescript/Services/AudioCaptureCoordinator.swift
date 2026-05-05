import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit
import CoreMedia

enum CapturedAudioSource: String {
    case mic
    case system
}

struct CapturedAudioChunk {
    let source: CapturedAudioSource
    let samples: [Float]
}

enum SystemCaptureStatus: Equatable {
    case notStarted
    case starting
    case running
    case denied(String)
    case error(String)
}

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
    private var sourceMode: TranscriptSourceMode = .mic

    var onChunk: ((CapturedAudioChunk) -> Void)?
    var onSystemStatus: ((SystemCaptureStatus) -> Void)?

    func start(sourceMode: TranscriptSourceMode) throws {
        self.sourceMode = sourceMode
        if sourceMode == .mic || sourceMode == .mixed {
            try startMicrophone()
        }
        if sourceMode == .system || sourceMode == .mixed {
            startSystemAudio()
        } else {
            onSystemStatus?(.notStarted)
        }
    }

    func stop() {
        micEngine.inputNode.removeTap(onBus: 0)
        micEngine.stop()
        systemCapture?.stop()
        systemCapture = nil
        onSystemStatus?(.notStarted)
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
            self.onChunk?(CapturedAudioChunk(source: .mic, samples: mono))
        }

        micEngine.prepare()
        try micEngine.start()
    }

    private func startSystemAudio() {
        onSystemStatus?(.starting)
        let capture = SystemAudioCapture(
            onChunk: { [weak self] chunk in
                self?.onChunk?(CapturedAudioChunk(source: .system, samples: chunk))
            },
            onStatus: { [weak self] status in
                self?.onSystemStatus?(status)
            }
        )
        self.systemCapture = capture
        capture.start()
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
}

private final class SystemAudioCapture: NSObject {
    private var stream: SCStream?
    private let output = SystemAudioOutput()
    private let queue = DispatchQueue(label: "SystemAudioCapture.stream")
    private let onStatus: (SystemCaptureStatus) -> Void

    init(onChunk: @escaping ([Float]) -> Void, onStatus: @escaping (SystemCaptureStatus) -> Void) {
        self.onStatus = onStatus
        super.init()
        output.onChunk = onChunk
    }

    func start() {
        // Force-trigger the OS Screen Recording prompt if needed. After a Debug rebuild
        // the binary's code signature changes and the cached TCC entry can become stale —
        // CGRequestScreenCaptureAccess re-syncs it. The call is a no-op when already granted.
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    self.onStatus(.error("No displays available for capture"))
                    return
                }

                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.captureMicrophone = false
                config.sampleRate = 16_000
                config.channelCount = 1
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.width = 2
                config.height = 2

                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                self.stream = stream

                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)
                try await stream.startCapture()
                self.onStatus(.running)
            } catch {
                let nsError = error as NSError
                let isDenied = (nsError.code == -3801) ||
                    nsError.domain.contains("SCStreamError") && nsError.code == -3801 ||
                    nsError.domain == "com.apple.coremedia.tcc"
                let detail = "[\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)"
                if isDenied {
                    self.onStatus(.denied("Permission stale. Open System Settings > Privacy & Security > Screen & System Audio Recording, toggle Livescript OFF then ON, fully quit and relaunch the app. \(detail)"))
                } else {
                    self.onStatus(.error(detail))
                }
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
