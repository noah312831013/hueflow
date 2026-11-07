import AudioToolbox
import CoreAudio
import Foundation

/// The beat level of whatever the Mac is playing, for music-reactive gradients: a Core Audio process tap on the system
/// output (macOS 14.2+; asks once for "System Audio Recording", nothing on screen is captured). It starts on the first
/// read and stops a few seconds after the last, so it only runs while a reactive gradient is drawing.
final class AudioTap {
    static let shared = AudioTap()
    private var envelope = BeatEnvelope()
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "app.hueflow.audio", qos: .userInteractive)
    private var tap = AudioObjectID(kAudioObjectUnknown), device = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var lastRead = 0.0, failed = false

    private init() {
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.proc != nil, ProcessInfo.processInfo.systemUptime - self.lastRead > 3 else { return }
            self.stop()
        }
    }

    /// 0–1; call from the main thread.
    func level() -> Float {
        lastRead = ProcessInfo.processInfo.systemUptime
        if proc == nil && !failed { failed = !start() } // a failure (old macOS, no device) isn't retried every frame
        lock.lock(); defer { lock.unlock() }
        return envelope.level
    }

    private func start() -> Bool {
        guard #available(macOS 14.2, *) else { return false }
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr else { return false }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Hueflow Music", kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device) == noErr else { stop(); return false }
        var format = AudioStreamBasicDescription(), size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format)
        let rate = Float(format.mSampleRate > 0 ? format.mSampleRate : 48000)
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { [weak self] _, input, _, _, _ in
            // shortcut: reads only the first buffer, which holds the tap's interleaved float stereo mixdown; a
            // non-interleaved tap format would be analysed from its left channel only.
            guard let self, let b = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)).first,
                  let data = b.mData else { return }
            let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: Int(b.mDataByteSize) / 4)
            self.lock.lock(); self.envelope.feed(samples, channels: Int(b.mNumberChannels), sampleRate: rate); self.lock.unlock()
        }
        guard status == noErr, AudioDeviceStart(device, proc) == noErr else { stop(); return false }
        return true
    }

    private func stop() {
        if let proc { AudioDeviceStop(device, proc); AudioDeviceDestroyIOProcID(device, proc) }
        proc = nil
        if device != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(device) }
        device = AudioObjectID(kAudioObjectUnknown)
        if tap != kAudioObjectUnknown, #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tap) }
        tap = AudioObjectID(kAudioObjectUnknown)
        lock.lock(); envelope = BeatEnvelope(); lock.unlock()
    }
}
