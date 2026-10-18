import XCTest
@testable import MacPad

@MainActor
final class PreferencesTests: XCTestCase {
    func testClassicThemeFontIsBundled() {
        Chrome.registerFonts()
        XCTAssertNotNil(NSFont(name: Chrome.classicFontName, size: 12))
        XCTAssertNotNil(NSFont(name: EditorTheme.classic.preferredFont ?? "", size: 12), "Monaco ships with macOS")
    }

    func testEditorSettingsAreClamped() {
        let defaults = UserDefaults.standard
        defaults.set(500.0, forKey: Preferences.Key.fontSize)
        defaults.set(0, forKey: Preferences.Key.tabWidth)
        defer {
            defaults.removeObject(forKey: Preferences.Key.fontSize)
            defaults.removeObject(forKey: Preferences.Key.tabWidth)
        }
        XCTAssertEqual(Preferences.editor.fontSize, 72)
        XCTAssertEqual(Preferences.editor.tabWidth, 1)
    }
}
