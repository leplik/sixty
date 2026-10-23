import CoreAudio
import CoreMediaIO
import Foundation
import SixtyCore

/// Which processes use an audio device right now (macOS 14+).
/// Needs no permission: it reads "is running" flags, never audio data.
enum AudioClients {
    static func current() -> [AudioClient] {
        processObjects().compactMap { object in
            let microphone = readUInt32(object, kAudioProcessPropertyIsRunningInput) != 0
            let speaker = readUInt32(object, kAudioProcessPropertyIsRunningOutput) != 0
            guard microphone || speaker,
                  let bundleID = readString(object, kAudioProcessPropertyBundleID),
                  !bundleID.isEmpty
            else { return nil }
            return AudioClient(bundleID: bundleID, usesMicrophone: microphone, usesSpeaker: speaker)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func processObjects() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func readUInt32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : 0
    }

    private static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let value = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
        value.initialize(to: nil)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        // CoreAudio hands over a +1 reference.
        return value.pointee?.takeRetainedValue() as String?
    }
}

/// Whether any app uses any camera. Needs no camera permission.
enum Camera {
    static func count() -> Int {
        devices().count
    }

    static func inUse() -> Bool {
        devices().contains(where: isRunning)
    }

    private static func devices() -> [CMIOObjectID] {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return [] }
        return Array(devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private static func isRunning(_ device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        var running: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running)
        return status == noErr && running != 0
    }
}

/// Reads the devices at most every 2 s and applies the call rules.
@MainActor
final class CallDetector {
    private let policy: CallPolicy
    private var checkedAt = Date.distantPast
    private var last: CallSignal?

    init(policy: CallPolicy = .standard) {
        self.policy = policy
    }

    func signal(at now: Date) -> CallSignal? {
        let age = now.timeIntervalSince(checkedAt)
        guard age >= 2 || age < 0 else { return last }
        checkedAt = now
        last = policy.signal(for: DeviceSnapshot(audioClients: AudioClients.current(), cameraInUse: Camera.inUse()))
        return last
    }
}
