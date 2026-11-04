import XCTest
import AVFoundation
import AudioGuard
@testable import SoundDock

final class CaptureTests: XCTestCase {
    func testStereoBufferAndUnderflow() throws {
        let ring = try XCTUnwrap(SDCaptureBufferCreate())
        defer { SDCaptureDestroy(ring) }
        let left = (0..<256).map { Float($0) / 256 }, right = (0..<256).map { -Float($0) / 256 }
        let pushed = left.withUnsafeBufferPointer { l in right.withUnsafeBufferPointer { r in SDCapturePush(ring, 256, l.baseAddress!, r.baseAddress!) } }
        XCTAssertEqual(pushed, 256)
        let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!, frameCapacity: 512)!
        buffer.frameLength = 512
        SDCaptureRead(ring, 512, buffer.mutableAudioBufferList)
        for i in 0..<256 {
            XCTAssertEqual(buffer.floatChannelData![0][i], left[i])
            XCTAssertEqual(buffer.floatChannelData![1][i], right[i])
        }
        for i in 256..<512 { XCTAssertEqual(buffer.floatChannelData![0][i], 0); XCTAssertEqual(buffer.floatChannelData![1][i], 0) }
        SDCaptureRead(ring, 512, buffer.mutableAudioBufferList)
        XCTAssertEqual(buffer.floatChannelData![0][0], 0)
    }
    func testBufferOverflowAndWraparoundPreserveOrder() throws {
        let ring = try XCTUnwrap(SDCaptureBufferCreate())
        defer { SDCaptureDestroy(ring) }
        let first = [Float](repeating: 0.25, count: 70000)
        XCTAssertEqual(first.withUnsafeBufferPointer { SDCapturePush(ring, 70000, $0.baseAddress!, $0.baseAddress!) }, 65536)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32768)!
        buffer.frameLength = 32768
        SDCaptureRead(ring, 32768, buffer.mutableAudioBufferList)
        let second = [Float](repeating: -0.5, count: 32768)
        XCTAssertEqual(second.withUnsafeBufferPointer { SDCapturePush(ring, 32768, $0.baseAddress!, $0.baseAddress!) }, 32768)
        SDCaptureRead(ring, 32768, buffer.mutableAudioBufferList)
        XCTAssertEqual(buffer.floatChannelData![0][0], 0.25)
        XCTAssertEqual(buffer.floatChannelData![1][32767], 0.25)
        SDCaptureRead(ring, 32768, buffer.mutableAudioBufferList)
        XCTAssertEqual(buffer.floatChannelData![0][0], -0.5)
        XCTAssertEqual(buffer.floatChannelData![1][32767], -0.5)
    }
    func testSignalMetersMeasureStereoAndReset() throws {
        let ring = try XCTUnwrap(SDCaptureBufferCreate())
        defer { SDCaptureDestroy(ring) }
        let left = [Float](repeating: 0.25, count: 32), right = [Float](repeating: -0.5, count: 32)
        _ = left.withUnsafeBufferPointer { l in right.withUnsafeBufferPointer { r in SDCapturePush(ring, 32, l.baseAddress!, r.baseAddress!) } }
        let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!, frameCapacity: 32)!
        buffer.frameLength = 32
        SDCaptureRead(ring, 32, buffer.mutableAudioBufferList)
        SDCaptureMarkOutput(ring, 32, buffer.audioBufferList)
        let levels = SDCaptureGetLevels(ring)
        XCTAssertEqual(levels.source, 0.5, accuracy: 0.00001)
        XCTAssertEqual(levels.output, 0.5, accuracy: 0.00001)
        XCTAssertEqual(levels.rendered, 32)
        let reset = SDCaptureGetLevels(ring)
        XCTAssertEqual(reset.source, 0)
        XCTAssertEqual(reset.output, 0)
    }
    func testFiveSecondPrebufferAndAutomaticRefill() throws {
        let ring = try XCTUnwrap(SDCaptureBufferCreate())
        defer { SDCaptureDestroy(ring) }
        XCTAssertTrue(SDCaptureConfigureBuffer(ring, 100, 5, 30))
        let tone = [Float](repeating: 0.25, count: 500)
        func push(_ count: UInt32) { _ = tone.withUnsafeBufferPointer { SDCapturePush(ring, count, $0.baseAddress!, $0.baseAddress!) } }
        let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 100, channels: 2)!, frameCapacity: 500)!
        buffer.frameLength = 500
        push(400)
        SDCaptureRead(ring, 100, buffer.mutableAudioBufferList)
        XCTAssertTrue(SDCaptureGetLevels(ring).buffering)
        XCTAssertEqual(SDCaptureGetLevels(ring).queuedSeconds, 4, accuracy: 0.001)
        XCTAssertEqual(buffer.floatChannelData![0][50], 0)
        push(100)
        SDCaptureRead(ring, 500, buffer.mutableAudioBufferList)
        XCTAssertFalse(SDCaptureGetLevels(ring).buffering)
        XCTAssertEqual(buffer.floatChannelData![0][400], 0.25)
        SDCaptureRead(ring, 100, buffer.mutableAudioBufferList)
        XCTAssertTrue(SDCaptureGetLevels(ring).buffering)
        XCTAssertEqual(buffer.floatChannelData![0][50], 0)
        push(500)
        SDCaptureRead(ring, 300, buffer.mutableAudioBufferList)
        XCTAssertFalse(SDCaptureGetLevels(ring).buffering)
        XCTAssertEqual(buffer.floatChannelData![1][299], 0.25)
    }
    func testFullReserveRecentersAndStaysBounded() throws {
        let ring = try XCTUnwrap(SDCaptureBufferCreate())
        defer { SDCaptureDestroy(ring) }
        XCTAssertTrue(SDCaptureConfigureBuffer(ring, 100, 5, 30))
        let tone = [Float](repeating: 0.25, count: 4000)
        XCTAssertEqual(tone.withUnsafeBufferPointer { SDCapturePush(ring, 4000, $0.baseAddress!, $0.baseAddress!) }, 3000)
        let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 100, channels: 2)!, frameCapacity: 100)!
        buffer.frameLength = 100
        SDCaptureRead(ring, 100, buffer.mutableAudioBufferList)
        let levels = SDCaptureGetLevels(ring)
        XCTAssertEqual(levels.resyncs, 1)
        XCTAssertEqual(levels.queuedSeconds, 4, accuracy: 0.001)
        XCTAssertFalse(levels.buffering)
    }
    func testInvalidBufferConfigurationIsRejected() throws {
        let ring = try XCTUnwrap(SDCaptureBufferCreate())
        defer { SDCaptureDestroy(ring) }
        XCTAssertFalse(SDCaptureConfigureBuffer(ring, 0, 5, 30))
        XCTAssertFalse(SDCaptureConfigureBuffer(ring, 48000, 30, 5))
        XCTAssertFalse(SDCaptureConfigureBuffer(ring, .nan, 5, 30))
    }
    func testObjectiveCExceptionIsReportedAsError() {
        XCTAssertThrowsError(try safely { NSException(name: .invalidArgumentException, reason: "Audio test failure", userInfo: nil).raise() }) { error in
            XCTAssertEqual(error.localizedDescription, "Audio test failure")
        }
    }
    func testSwiftErrorAndSuccessArePreserved() throws {
        XCTAssertThrowsError(try safely { throw AudioFailure(message: "test") }) { error in XCTAssertEqual(error.localizedDescription, "test") }
        var executed = false
        try safely { executed = true }
        XCTAssertTrue(executed)
    }
}
