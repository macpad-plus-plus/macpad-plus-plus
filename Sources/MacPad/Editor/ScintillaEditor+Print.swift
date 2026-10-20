import AppKit
import Scintilla

extension ScintillaEditor {
    /// The text in `font`, colored as `theme` colors this language, for
    /// printing: paper takes the light theme whatever the window shows.
    func attributedTextForPrinting(theme: EditorTheme, font: NSFont, tabWidth: Int) -> NSAttributedString {
        send(SCI_COLOURISE, 0, -1)
        let length = self.length
        var colors: [Int: EditorTheme.TokenStyle] = [:]
        for (kind, styles) in language.styles {
            guard let token = theme.tokens[kind] else { continue }
            for style in styles { colors[Int(style)] = token }
        }

        // Character and style bytes, interleaved, plus two terminating NULs.
        var cells = [CChar](repeating: 0, count: 2 * length + 2)
        cells.withUnsafeMutableBufferPointer { buffer in
            var range = Sci_TextRangeFull(chrg: Sci_CharacterRangeFull(cpMin: 0, cpMax: length), lpstrText: buffer.baseAddress)
            withUnsafeMutablePointer(to: &range) { send(SCI_GETSTYLEDTEXTFULL, 0, Int(bitPattern: $0)) }
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = []
        paragraph.defaultTabInterval = (" " as NSString).size(withAttributes: [.font: font]).width * CGFloat(tabWidth)
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        let result = NSMutableAttributedString()
        var runStart = 0
        func flush(upTo end: Int) {
            guard end > runStart else { return }
            let bytes = (runStart..<end).map { UInt8(bitPattern: cells[2 * $0]) }
            let token = colors[Int(UInt8(bitPattern: cells[2 * runStart + 1]))]
            let attributes: [NSAttributedString.Key: Any] = [
                .font: token?.bold == true ? bold : token?.italic == true ? italic : font,
                .foregroundColor: NSColor(rgb: token?.color ?? theme.foreground),
                .paragraphStyle: paragraph,
            ]
            result.append(NSAttributedString(string: String(decoding: bytes, as: UTF8.self), attributes: attributes))
            runStart = end
        }
        for position in 0..<length where cells[2 * position + 1] != cells[2 * runStart + 1] {
            // A character's bytes share one style, so runs never split one.
            flush(upTo: position)
        }
        flush(upTo: length)
        return result
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
