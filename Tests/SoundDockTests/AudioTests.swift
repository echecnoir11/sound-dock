import XCTest
import AVFoundation
import CoreAudio
@testable import SoundDock

final class AudioTests: XCTestCase {
    func render(_ settings: EffectSettings, frequency: Double = 440, impulse: Bool = false, allowSpeed: Bool = false) throws -> [Float] {
        let engine = AVAudioEngine(), fx = Effects(), player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        engine.attach(player); fx.attach(to: engine)
        fx.connect(engine, source: player, format: format)
        fx.apply(settings, engine: engine, allowSpeed: allowSpeed)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96000)!
        input.frameLength = 96000
        for channel in 0..<2 {
            for frame in 0..<96000 {
                input.floatChannelData![channel][frame] = impulse ? (frame == 8000 ? 0.5 : 0) : Float(sin(2 * .pi * frequency * Double(frame) / 48000) * 0.15)
            }
        }
        player.scheduleBuffer(input)
        try engine.start(); player.play()
        defer { engine.stop() }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        var samples: [Float] = [], attempts = 0
        while samples.count < 96000 && attempts < 1000 {
            attempts += 1
            let count = AVAudioFrameCount(min(1024, 96000 - samples.count))
            let result = try engine.renderOffline(count, to: buffer)
            if result == .success {
                samples.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            }
        }
        XCTAssertEqual(samples.count, 96000)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite })
        return samples
    }
    func rms(_ s: ArraySlice<Float>) -> Double { sqrt(s.reduce(0.0) { $0 + Double($1 * $1) } / Double(s.count)) }
    func frequency(_ samples: [Float], start: Int = 24000, end: Int = 72000) -> Double {
        var crossings = 0
        for i in (start + 1)..<end { if samples[i-1] <= 0 && samples[i] > 0 { crossings += 1 } }
        return Double(crossings) * 48000 / Double(end - start)
    }
    func testFileSpeedChangesDurationWithoutChangingPitch() throws {
        var s = EffectSettings(); s.speed = 2
        let fast = try render(s, allowSpeed: true)
        XCTAssertEqual(frequency(fast, start: 12000, end: 36000), 440, accuracy: 5)
        XCTAssertLessThan(rms(fast[72000..<96000]), 0.00001)
        s.speed = 0.5
        let slow = try render(s, allowSpeed: true)
        XCTAssertEqual(frequency(slow), 440, accuracy: 5)
        XCTAssertGreaterThan(rms(slow[72000..<96000]), 0.02)
    }
    func testSystemSpeedAlwaysStaysOneAndBypassResetsFileSpeed() throws {
        var s = EffectSettings(); s.speed = 2
        let system = try render(s)
        XCTAssertGreaterThan(rms(system[72000..<90000]), 0.02)
        let engine = AVAudioEngine(), fx = Effects()
        fx.apply(s, engine: engine, allowSpeed: false)
        XCTAssertEqual(fx.pitch.rate, 1)
        s.bypass = true
        fx.apply(s, engine: engine, allowSpeed: true)
        XCTAssertEqual(fx.pitch.rate, 1)
    }
    func testVirtualAndAggregateDevicesCannotBePlaybackDestinations() {
        let blackhole = Device(id: 1, uid: "bh", name: "BlackHole 2ch", inputs: 2, outputs: 2, transport: kAudioDeviceTransportTypeVirtual)
        let aggregate = Device(id: 2, uid: "agg", name: "Aggregate", inputs: 2, outputs: 4, transport: kAudioDeviceTransportTypeAggregate)
        let speakers = Device(id: 3, uid: "hw", name: "Speakers", inputs: 0, outputs: 2, transport: kAudioDeviceTransportTypeBuiltIn)
        XCTAssertFalse(blackhole.isPhysical)
        XCTAssertFalse(aggregate.isPhysical)
        XCTAssertTrue(speakers.isPhysical)
    }
    func testBypassRetainsVolumeAndClearsEffects() throws {
        var s = EffectSettings(); s.bass = 12; s.pitch = 7; s.reverb = 45; s.bypass = true
        let rendered = try render(s)
        XCTAssertEqual(frequency(rendered), 440, accuracy: 2)
        XCTAssertEqual(rms(rendered[24000..<72000]), 0.15 * Double(s.volume) / sqrt(2), accuracy: 0.003)
    }
    func testPitchOctavesAndNoRateChange() throws {
        var s = EffectSettings(); s.pitch = 12
        XCTAssertEqual(frequency(try render(s)), 880, accuracy: 8)
        s.pitch = -12
        XCTAssertEqual(frequency(try render(s)), 220, accuracy: 5)
        let fx = Effects(); let engine = AVAudioEngine(); fx.apply(s, engine: engine)
        XCTAssertEqual(fx.pitch.rate, 1)
    }
    func testBassBoostChangesFrequencyBalance() throws {
        let neutral = EffectSettings()
        var boosted = neutral; boosted.bass = 12
        let bassNeutral = rms(try render(neutral, frequency: 60)[24000..<72000])
        let bassBoosted = rms(try render(boosted, frequency: 60)[24000..<72000])
        let highNeutral = rms(try render(neutral, frequency: 6000)[24000..<72000])
        let highBoosted = rms(try render(boosted, frequency: 6000)[24000..<72000])
        XCTAssertGreaterThan((bassBoosted / bassNeutral) / (highBoosted / highNeutral), 2.5)
        XCTAssertGreaterThan(bassBoosted, bassNeutral * 2.5)
    }
    func testReverbProducesTail() throws {
        var s = EffectSettings(); s.reverb = 45
        let dry = try render(EffectSettings(), impulse: true), wet = try render(s, impulse: true)
        XCTAssertGreaterThan(rms(wet[24000..<48000]), rms(dry[24000..<48000]) + 0.000001)
    }
    func testNeutralAtFullVolumePreservesInputLevel() throws {
        let rendered = try render(EffectSettings())
        XCTAssertEqual(rms(rendered[24000..<72000]), 0.15 / sqrt(2), accuracy: 0.002)
    }
    func testLimiterControlsPeaksWithStrongEQBoost() throws {
        var s = EffectSettings(); s.bass = 12; s.low = 12; s.mid = 12; s.high = 12
        let rendered = try render(s, frequency: 250)
        XCTAssertLessThanOrEqual(rendered[24000..<72000].map { abs($0) }.max()!, 1.01)
    }
    func testMuteWithBoostedEQ() throws {
        var s = EffectSettings(); s.bass = 12; s.low = 12; s.mid = 12; s.high = 12
        s.volume = 0
        XCTAssertLessThan(rms(try render(s)[24000..<72000]), 0.000001)
    }
}
