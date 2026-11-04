import XCTest
import AVFoundation
import AudioGuard
@testable import SoundDock

final class VisualizerTests: XCTestCase {
    func testProcessedStereoEnvelopeHasSixteenBoundedBarsAndResets() throws {
        let meter = try XCTUnwrap(SDVisualizerCreate())
        defer { SDVisualizerDestroy(meter) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160)!
        buffer.frameLength = 160
        for i in 0..<160 {
            buffer.floatChannelData![0][i] = Float(i / 10) / 10
            buffer.floatChannelData![1][i] = -0.25
        }
        SDVisualizerProcess(meter, 160, buffer.audioBufferList)
        var levels = [Float](repeating: -1, count: 20)
        let generation = levels.withUnsafeMutableBufferPointer { SDVisualizerCopy(meter, $0.baseAddress!, 20) }
        XCTAssertEqual(generation, 1)
        for i in 0..<16 { XCTAssertEqual(levels[i], min(1, max(0.25, Float(i) / 10)), accuracy: 0.00001) }
        XCTAssertEqual(Array(levels[16...19]), [0, 0, 0, 0])
        SDVisualizerReset(meter)
        let reset = levels.withUnsafeMutableBufferPointer { SDVisualizerCopy(meter, $0.baseAddress!, 20) }
        XCTAssertEqual(reset, 0)
        XCTAssertTrue(levels.allSatisfy { $0 == 0 })
    }
    func testSilentSignalProducesNoAnimatedLevels() throws {
        let meter = try XCTUnwrap(SDVisualizerCreate())
        defer { SDVisualizerDestroy(meter) }
        let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!, frameCapacity: 160)!
        buffer.frameLength = 160
        for i in 0..<160 { buffer.floatChannelData![0][i] = 0 }
        SDVisualizerProcess(meter, 160, buffer.audioBufferList)
        var levels = [Float](repeating: -1, count: 16)
        _ = levels.withUnsafeMutableBufferPointer { SDVisualizerCopy(meter, $0.baseAddress!, 16) }
        XCTAssertTrue(levels.allSatisfy { $0 == 0 })
    }
    @MainActor func testStoppingVisualizationClearsBars() {
        let model = VisualizerModel()
        model.start(); model.stop()
        XCTAssertEqual(model.bars, [Float](repeating: 0, count: 16))
    }
}
