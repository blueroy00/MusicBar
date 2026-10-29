import CoreAudio

enum AudioInputMonitor {
    // shortcut: meetings that never open audio input need another detection signal.
    static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    // Read activity flags only; never open an input device or capture audio.
    static func isActive() -> Bool? {
        guard #available(macOS 14.2, *) else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        let stride = MemoryLayout<AudioObjectID>.stride
        guard Int(size) % stride == 0 else { return nil }
        if size == 0 { return false }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / stride)
        let result = processes.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
        }
        guard result == noErr, Int(size) <= processes.count * stride else { return nil }
        address.mSelector = kAudioProcessPropertyIsRunningInput
        var failed = false
        for process in processes.prefix(Int(size) / stride) {
            var active: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(process, &address, 0, nil, &valueSize, &active) != noErr {
                failed = true
            } else if active != 0 {
                // Output-only process taps can report input activity without an input device.
                var devices = AudioObjectPropertyAddress(
                    mSelector: kAudioProcessPropertyDevices,
                    mScope: kAudioObjectPropertyScopeInput,
                    mElement: kAudioObjectPropertyElementMain
                )
                var deviceSize: UInt32 = 0
                if AudioObjectGetPropertyDataSize(process, &devices, 0, nil, &deviceSize) != noErr {
                    failed = true
                } else if deviceSize > 0 {
                    return true
                }
            }
        }
        return failed ? nil : false
    }
}

struct InputPauseRule {
    private(set) var wasActive = false

    mutating func shouldPause(inputActive: Bool?, enabled: Bool, playing: Bool) -> Bool {
        guard enabled else {
            wasActive = false
            return false
        }
        guard let inputActive else { return false }
        defer { wasActive = inputActive }
        // Only the start of input activity triggers a pause; manual playback stays available.
        return inputActive && !wasActive && playing
    }
}
