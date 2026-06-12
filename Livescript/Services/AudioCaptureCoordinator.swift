import AVFoundation
import CoreAudio
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

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
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .inputUnavailable:
            return "Audio input is unavailable."
        case .conversionFailed:
            return "Failed to convert captured audio."
        case .microphonePermissionDenied:
            return "Microphone permission is required."
        }
    }
}

final class AudioCaptureCoordinator {
    private var micEngine = AVAudioEngine()
    private var micConverter: AVAudioConverter?
    private var micTargetFormat: AVAudioFormat?
    private var micConfigObserver: NSObjectProtocol?
    private var defaultInputDeviceListener: AudioObjectPropertyListenerBlock?
    private var systemCapture: SystemAudioCapture?
    private var sourceMode: TranscriptSourceMode = .mic
    private var isMicRunning = false

    private(set) var microphoneInputKind: AudioInputKind = .unknown

    var onChunk: ((CapturedAudioChunk) -> Void)?
    var onSystemStatus: ((SystemCaptureStatus) -> Void)?

    deinit {
        if let micConfigObserver {
            NotificationCenter.default.removeObserver(micConfigObserver)
        }
        removeDefaultInputDeviceListener()
    }

    func start(sourceMode: TranscriptSourceMode) throws {
        self.sourceMode = sourceMode
        if sourceMode == .mic || sourceMode == .mixed {
            try ensureMicrophonePermission()
            try startMicrophone()
        }
        if sourceMode == .system || sourceMode == .mixed {
            startSystemAudio()
        } else {
            onSystemStatus?(.notStarted)
        }
    }

    func stop() {
        if let micConfigObserver {
            NotificationCenter.default.removeObserver(micConfigObserver)
            self.micConfigObserver = nil
        }
        removeDefaultInputDeviceListener()
        tearDownMicrophoneEngine()
        systemCapture?.stop()
        systemCapture = nil
        onSystemStatus?(.notStarted)
    }

    private func ensureMicrophonePermission() throws {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return
            case .denied:
                throw AudioCaptureError.microphonePermissionDenied
            case .undetermined:
                return
            @unknown default:
                return
            }
        }
    }

    private func startMicrophone() throws {
        tearDownMicrophoneEngine()
        micEngine = AVAudioEngine()
        microphoneInputKind = MicrophoneDeviceInfo.currentInputKind()
        installDefaultInputDeviceListenerIfNeeded()

        let input = micEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioCaptureError.inputUnavailable
        }

        let targetFormat = try Self.makeTargetFormat()
        guard let monoInputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.conversionFailed
        }
        guard let converter = AVAudioConverter(from: monoInputFormat, to: targetFormat) else {
            throw AudioCaptureError.conversionFailed
        }

        self.micConverter = converter
        self.micTargetFormat = targetFormat

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self,
                  let converter = self.micConverter,
                  let targetFormat = self.micTargetFormat else { return }

            guard let mono = self.convertToMono16K(
                buffer: buffer,
                converter: converter,
                inputFormat: inputFormat,
                targetFormat: targetFormat
            ) else { return }

            self.onChunk?(CapturedAudioChunk(source: .mic, samples: mono))
        }

        if let micConfigObserver {
            NotificationCenter.default.removeObserver(micConfigObserver)
        }
        micConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: micEngine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            guard self.sourceMode == .mic || self.sourceMode == .mixed else { return }
            try? self.startMicrophone()
        }

        micEngine.prepare()
        try micEngine.start()
        isMicRunning = true
    }

    private func tearDownMicrophoneEngine() {
        if isMicRunning {
            micEngine.inputNode.removeTap(onBus: 0)
            micEngine.stop()
            isMicRunning = false
        }
        micConverter = nil
        micTargetFormat = nil
    }

    private func installDefaultInputDeviceListenerIfNeeded() {
        guard defaultInputDeviceListener == nil else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            guard self.sourceMode == .mic || self.sourceMode == .mixed else { return }
            self.microphoneInputKind = MicrophoneDeviceInfo.currentInputKind()
            try? self.startMicrophone()
        }
        defaultInputDeviceListener = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func removeDefaultInputDeviceListener() {
        guard defaultInputDeviceListener != nil else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        if let defaultInputDeviceListener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                defaultInputDeviceListener
            )
        }
        defaultInputDeviceListener = nil
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

    private func convertToMono16K(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        inputFormat: AVAudioFormat,
        targetFormat: AVAudioFormat
    ) -> [Float]? {
        guard let monoBuffer = downmixToMono(buffer: buffer, format: inputFormat) else { return nil }

        guard monoBuffer.format.sampleRate == targetFormat.sampleRate,
              monoBuffer.format.channelCount == targetFormat.channelCount else {
            return resample(buffer: monoBuffer, converter: converter, targetFormat: targetFormat)
        }

        guard let channelData = monoBuffer.floatChannelData?[0] else { return nil }
        let count = Int(monoBuffer.frameLength)
        guard count > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: channelData, count: count))
    }

    private func resample(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> [Float]? {
        var outputSamples: [Float] = []
        var error: NSError?
        var inputProvided = false

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return buffer
        }

        var status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        while status != .error {
            if error != nil { return nil }
            if outputBuffer.frameLength > 0, let channelData = outputBuffer.floatChannelData?[0] {
                outputSamples.append(
                    contentsOf: UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength))
                )
            }
            if status != .haveData { break }
            outputBuffer.frameLength = 0
            status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        }

        return outputSamples.isEmpty ? nil : outputSamples
    }

    private func downmixToMono(buffer: AVAudioPCMBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameLength = buffer.frameLength
        guard frameLength > 0 else { return nil }

        let channelCount = Int(format.channelCount)
        guard channelCount >= 1 else { return nil }

        if channelCount == 1, format.commonFormat == .pcmFormatFloat32 {
            return buffer
        }

        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameLength) else {
            return nil
        }
        monoBuffer.frameLength = frameLength

        guard let monoData = monoBuffer.floatChannelData?[0] else { return nil }

        if let floatChannels = buffer.floatChannelData {
            for frame in 0..<Int(frameLength) {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += floatChannels[channel][frame]
                }
                monoData[frame] = sum / Float(channelCount)
            }
            return monoBuffer
        }

        if let int16Channels = buffer.int16ChannelData {
            for frame in 0..<Int(frameLength) {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += Float(int16Channels[channel][frame]) / Float(Int16.max)
                }
                monoData[frame] = sum / Float(channelCount)
            }
            return monoBuffer
        }

        return nil
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
                    self.onStatus(.denied("System audio permission is required. Open System Settings > Privacy & Security > Screen & System Audio Recording, toggle Livescript OFF then ON, then relaunch the app. \(detail)"))
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
