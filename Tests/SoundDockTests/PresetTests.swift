import XCTest
import AVFoundation
@testable import SoundDock

final class PresetTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "SoundDockTests.presets.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite); defaults = nil }

    func testSaveRenameReloadAndDelete() throws {
        let store = PresetStore(defaults: defaults)
        var settings = EffectSettings(); settings.speed = 1.25; settings.bass = 6; settings.volume = 0.4
        let preset = try store.save(name: "  Night  ", settings: settings)
        XCTAssertEqual(preset.name, "Night")
        XCTAssertEqual(PresetStore(defaults: defaults).presets, [preset])
        try store.rename(id: preset.id, name: "Warm")
        let reloaded = PresetStore(defaults: defaults)
        XCTAssertEqual(reloaded.presets.first?.id, preset.id)
        XCTAssertEqual(reloaded.presets.first?.name, "Warm")
        XCTAssertEqual(reloaded.presets.first?.speed, 1.25)
        XCTAssertEqual(reloaded.presets.first?.bass, 6)
        XCTAssertEqual(reloaded.presets.first?.volume, 0.4)
        try reloaded.delete(id: preset.id)
        XCTAssertTrue(PresetStore(defaults: defaults).presets.isEmpty)
    }
    func testInvalidNamesAndDuplicatesDoNotOverwriteSavedPresets() throws {
        let store = PresetStore(defaults: defaults)
        let preset = try store.save(name: "Warm", settings: EffectSettings())
        XCTAssertThrowsError(try store.save(name: "  ", settings: EffectSettings()))
        XCTAssertThrowsError(try store.save(name: "warm", settings: EffectSettings()))
        XCTAssertThrowsError(try store.rename(id: preset.id, name: String(repeating: "a", count: 49)))
        var invalid = EffectSettings(); invalid.speed = .nan
        XCTAssertThrowsError(try store.save(name: "Invalid", settings: invalid))
        XCTAssertEqual(PresetStore(defaults: defaults).presets, [preset])
    }
    func testCorruptStorageIsReportedAndValidDataCanBeSaved() throws {
        defaults.set(Data("broken".utf8), forKey: "audioPresets.v1")
        let store = PresetStore(defaults: defaults)
        XCTAssertTrue(store.presets.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        _ = try store.save(name: "New", settings: EffectSettings())
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(PresetStore(defaults: defaults).presets.count, 1)
    }
    func testApplyOnlyChangesPresetFields() throws {
        var before = EffectSettings(); before.pitch = 4; before.reverb = 20; before.low = -3; before.bypass = true
        var saved = EffectSettings(); saved.speed = 0.75; saved.bass = 8; saved.volume = 0.3
        let applied = AudioPreset(name: "Slow", settings: saved).applying(to: before)
        XCTAssertEqual(applied.speed, 0.75)
        XCTAssertEqual(applied.bass, 8)
        XCTAssertEqual(applied.volume, 0.3)
        XCTAssertEqual(applied.pitch, 4)
        XCTAssertEqual(applied.reverb, 20)
        XCTAssertEqual(applied.low, -3)
        XCTAssertTrue(applied.bypass)
    }
    func testParametersCanChangeWhileAudioEngineRuns() throws {
        let engine = AVAudioEngine(), effects = Effects(), player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        engine.attach(player); effects.attach(to: engine); effects.connect(engine, source: player, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)!
        input.frameLength = 48000
        for channel in 0..<2 { for frame in 0..<48000 { input.floatChannelData![channel][frame] = 0.1 } }
        player.scheduleBuffer(input)
        try engine.start(); player.play()
        defer { engine.stop() }
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        XCTAssertEqual(try engine.renderOffline(1024, to: output), .success)
        var saved = EffectSettings(); saved.speed = 1.25; saved.bass = 6; saved.volume = 0.3
        let settings = AudioPreset(name: "Live", settings: saved).applying(to: EffectSettings())
        let sampleTime = engine.manualRenderingSampleTime
        effects.apply(settings, engine: engine, allowSpeed: true)
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.manualRenderingSampleTime, sampleTime)
        XCTAssertEqual(effects.pitch.rate, 1.25)
        XCTAssertEqual(engine.mainMixerNode.outputVolume, 0.3)
        XCTAssertEqual(try engine.renderOffline(1024, to: output), .success)
        XCTAssertGreaterThan(engine.manualRenderingSampleTime, sampleTime)
    }
}
