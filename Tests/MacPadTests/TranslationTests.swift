import XCTest
@testable import MacPad

/// Guards community translations: every file must parse, use only keys from the
/// English template, and keep the same placeholders (%@, %lld…) as English.
final class TranslationTests: XCTestCase {
    private func table(_ language: String) throws -> [String: String] {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language),
                                 "No Localizable.strings for \(language)")
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String], "\(language) is not a valid .strings file")
    }

    private func placeholders(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDuUxXoOfeEgGcCsSpaA%]"#)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { (text as NSString).substring(with: $0.range) }.sorted()
    }

    func testTranslationsMatchTheTemplate() throws {
        let english = try table("en")
        XCTAssertGreaterThan(english.count, 100)
        let languages = Bundle.main.localizations.filter { $0 != "en" && $0 != "Base" }
        XCTAssertTrue(languages.contains("pt-BR"))

        for language in languages {
            let translations = try table(language)
            for (key, value) in translations {
                XCTAssertNotNil(english[key], "\(language): \"\(key)\" is not in the English template")
                XCTAssertEqual(placeholders(value), placeholders(key), "\(language): placeholders differ in \"\(key)\"")
                XCTAssertFalse(value.isEmpty, "\(language): empty translation for \"\(key)\"")
            }
        }
    }

    func testPortugueseLookups() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "pt-BR", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(bundle.localizedString(forKey: "Find…", value: nil, table: nil), "Buscar…")
        XCTAssertEqual(bundle.localizedString(forKey: "Ln %lld, Col %lld", value: nil, table: nil), "Lin %lld, Col %lld")
        XCTAssertEqual(AppLanguage.name(of: "pt-BR"), "Português (Brasil)")
    }
}
