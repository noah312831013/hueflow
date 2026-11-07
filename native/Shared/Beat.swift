import Foundation

/// Turns blocks of audio into a 0–1 beat level for music-reactive wallpapers. A one-pole low-pass keeps the bass (the
/// beat), its RMS is divided by a slowly decaying peak so quiet and loud tracks both use the full range, and a
/// fast-attack, slow-release envelope keeps the shape from shaking.
struct BeatEnvelope {
    private(set) var level: Float = 0
    private var low: Float = 0, peak: Float = 0

    /// `samples` interleaved, `channels` per frame.
    mutating func feed(_ samples: UnsafeBufferPointer<Float>, channels: Int, sampleRate: Float) {
        let ch = max(1, channels), frames = samples.count / ch
        guard frames > 0, sampleRate > 0 else { return }
        let a = 1 - exp(-2 * Float.pi * 150 / sampleRate) // 150 Hz low-pass
        var sum: Float = 0
        for i in 0..<frames {
            var x: Float = 0
            for c in 0..<ch { x += samples[i * ch + c] }
            low += a * (x / Float(ch) - low)
            sum += low * low
        }
        let rms = sqrt(sum / Float(frames)), dt = Float(frames) / sampleRate
        peak = max(rms, peak * exp(-dt / 4), 0.01) // the floor keeps silence and hiss near 0 instead of amplifying them
        let target = (rms / peak) * (rms / peak)   // squared: the gaps between beats drop further than the beats
        level += (target - level) * (1 - exp(-dt / (target > level ? 0.03 : 0.12)))
    }
}
