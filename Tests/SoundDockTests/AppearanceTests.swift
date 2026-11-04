import XCTest
import SwiftUI
import AppKit
@testable import SoundDock

final class AppearanceTests: XCTestCase {
    func testOpacityDefaultsBoundsAndInvalidValues() {
        XCTAssertEqual(WindowOpacity.defaultValue, 0.88)
        XCTAssertEqual(WindowOpacity.clamped(0.6), 0.7)
        XCTAssertEqual(WindowOpacity.clamped(1.2), 1)
        XCTAssertEqual(WindowOpacity.clamped(0.88), 0.88)
        XCTAssertEqual(WindowOpacity.clamped(.nan), 0.88)
    }
    func testOpacityPersistsInExistingPreferencesStorage() {
        let suite = "SoundDockTests.appearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppStorage(wrappedValue: WindowOpacity.defaultValue, WindowOpacity.key, store: defaults)
        XCTAssertEqual(first.wrappedValue, 0.88)
        first.wrappedValue = 0.76
        let second = AppStorage(wrappedValue: WindowOpacity.defaultValue, WindowOpacity.key, store: defaults)
        XCTAssertEqual(second.wrappedValue, 0.76)
    }
    @MainActor func testNativeBackgroundUsesVibrancyAndOnlyItsOwnAlpha() {
        _ = NSApplication.shared
        let view = FrostedBackgroundView(frame: NSRect(x: 0, y: 0, width: 354, height: 520))
        view.configure(opacity: 0.88, reduceTransparency: false)
        XCTAssertEqual(view.alphaValue, 0.88, accuracy: 0.001)
        XCTAssertEqual(view.material, .hudWindow)
        XCTAssertEqual(view.blendingMode, .behindWindow)
        XCTAssertEqual(view.state, .active)
        XCTAssertEqual(view.layer?.cornerRadius, 15)
        XCTAssertNil(view.hitTest(NSPoint(x: 20, y: 20)))
    }
    @MainActor func testAccessibilityAndFullOpacityUseSolidFallback() {
        _ = NSApplication.shared
        let view = FrostedBackgroundView()
        view.configure(opacity: 0.7, reduceTransparency: true)
        XCTAssertEqual(view.alphaValue, 1)
        XCTAssertEqual(view.state, .inactive)
        view.configure(opacity: 1, reduceTransparency: false)
        XCTAssertEqual(view.alphaValue, 1)
        XCTAssertEqual(view.state, .inactive)
        view.configure(opacity: 0.7, reduceTransparency: false)
        XCTAssertEqual(view.alphaValue, 0.7, accuracy: 0.001)
        XCTAssertEqual(view.state, .active)
    }
}
