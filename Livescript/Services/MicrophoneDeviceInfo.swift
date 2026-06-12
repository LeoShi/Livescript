import CoreAudio
import Foundation

enum MicrophoneDeviceInfo {
    static func currentInputKind() -> AudioInputKind {
        guard let deviceID = defaultInputDeviceID() else { return .unknown }
        return isBuiltInDevice(deviceID) ? .builtIn : .external
    }

    static func defaultInputDeviceName() -> String? {
        guard let deviceID = defaultInputDeviceID() else { return nil }
        return copyDeviceString(deviceID, selector: kAudioObjectPropertyName)
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private static func isBuiltInDevice(_ deviceID: AudioDeviceID) -> Bool {
        let uid = copyDeviceString(deviceID, selector: kAudioDevicePropertyDeviceUID)?.lowercased() ?? ""
        if uid.contains("builtin") || uid.contains("built-in") {
            return true
        }

        let name = copyDeviceString(deviceID, selector: kAudioObjectPropertyName)?.lowercased() ?? ""
        return name.contains("built-in")
            || name.contains("internal")
            || name.contains("macbook")
            || name.contains("imac")
            || name.contains("studio display")
    }

    private static func copyDeviceString(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ref)
        guard status == noErr, let ref else { return nil }
        return ref.takeUnretainedValue() as String
    }
}
