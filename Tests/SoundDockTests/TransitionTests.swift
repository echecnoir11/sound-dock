import XCTest
import AVFoundation
@testable import SoundDock

final class TransitionTests: XCTestCase {
    private func engine() throws -> (AVAudioEngine, Effects) {
        let e = AVAudioEngine(), fx = Effects(), player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        e.attach(player); fx.attach(to: e); fx.connect(e, source: player, format: format)
        try e.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        fx.apply(EffectSettings(), engine: e)
        try e.start()
        return (e, fx)
    }
    @MainActor func testBassVolumeAndSupportedSpeedReachTargetsGradually() throws {
        let (e, fx) = try engine(); defer { fx.cancelTransitions(); e.stop() }
        var target = EffectSettings(); target.bass = 10; target.volume = 0.2; target.speed = 1.5
        fx.apply(target, engine: e, allowSpeed: true, smooth: true)
        XCTAssertEqual(fx.eq.bands[0].gain, 0)
        XCTAssertEqual(e.mainMixerNode.outputVolume, 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.14))
        XCTAssertGreaterThan(fx.eq.bands[0].gain, 0)
        XCTAssertLessThan(fx.eq.bands[0].gain, 10)
        XCTAssertGreaterThan(e.mainMixerNode.outputVolume, 0.2)
        XCTAssertLessThan(e.mainMixerNode.outputVolume, 1)
        XCTAssertGreaterThan(fx.pitch.rate, 1)
        XCTAssertLessThan(fx.pitch.rate, 1.5)
        RunLoop.main.run(until: Date().addingTimeInterval(0.23))
        XCTAssertEqual(fx.eq.bands[0].gain, 10, accuracy: 0.001)
        XCTAssertEqual(e.mainMixerNode.outputVolume, 0.2, accuracy: 0.001)
        XCTAssertEqual(fx.pitch.rate, 1.5, accuracy: 0.001)
        XCTAssertTrue(e.isRunning)
    }
    @MainActor func testRetargetAndDisableDoNotLeaveOldRampRunning() throws {
        let (e, fx) = try engine(); defer { fx.cancelTransitions(); e.stop() }
        var first = EffectSettings(); first.bass = 12; first.volume = 0.1
        fx.apply(first, engine: e, smooth: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        var second = EffectSettings(); second.bass = 3; second.volume = 0.7; second.speed = 2
        fx.apply(second, engine: e, allowSpeed: false, smooth: false)
        XCTAssertEqual(fx.eq.bands[0].gain, 3)
        XCTAssertEqual(e.mainMixerNode.outputVolume, 0.7)
        XCTAssertEqual(fx.pitch.rate, 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertEqual(fx.eq.bands[0].gain, 3)
        XCTAssertEqual(e.mainMixerNode.outputVolume, 0.7)
    }
    @MainActor func testCancelStopsParameterUpdates() throws {
        let (e, fx) = try engine(); defer { e.stop() }
        var target = EffectSettings(); target.bass = 12
        fx.apply(target, engine: e, smooth: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        fx.cancelTransitions()
        let current = fx.eq.bands[0].gain
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertEqual(fx.eq.bands[0].gain, current)
    }
    func testVisualizerLightsMoreSegmentsAsLevelRises() {
        XCTAssertEqual(VisualizerScale.litSegments(0), 0)
        XCTAssertEqual(VisualizerScale.litSegments(0.1), 1)
        XCTAssertEqual(VisualizerScale.litSegments(0.6), 6)
        XCTAssertEqual(VisualizerScale.litSegments(1), 10)
        let counts = (0...100).map { VisualizerScale.litSegments(Float($0) / 100) }
        XCTAssertEqual(counts, counts.sorted())
    }
    func testVisualizerClampsInvalidAndOutOfRangeLevels() {
        XCTAssertEqual(VisualizerScale.litSegments(.nan), 0)
        XCTAssertEqual(VisualizerScale.litSegments(-1), 0)
        XCTAssertEqual(VisualizerScale.litSegments(10), 10)
        XCTAssertEqual(VisualizerScale.litSegments(1, rows: 0), 0)
    }
}
