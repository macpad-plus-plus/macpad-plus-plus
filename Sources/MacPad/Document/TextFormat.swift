import Foundation
import Scintilla

/// On-disk character encodings, named as Notepad++ names them.
enum TextEncoding: String, CaseIterable, Sendable {
    case utf8
    case utf8BOM
    case utf16LE
    case utf16BE
    case windows1252
    case latin1

    var displayName: String {
        switch self {
        case .utf8: "UTF-8"
        case .utf8BOM: "UTF-8 BOM"
        case .utf16LE: "UTF-16 LE BOM"
        case .utf16BE: "UTF-16 BE BOM"
        case .windows1252: "Windows-1252"
        case .latin1: "ISO-8859-1"
        }
    }

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8, .utf8BOM: .utf8
        case .utf16LE: .utf16LittleEndian
        case .utf16BE: .utf16BigEndian
        case .windows1252: .windowsCP1252
        case .latin1: .isoLatin1
        }
    }

    var byteOrderMark: [UInt8] {
        switch self {
        case .utf8BOM: [0xEF, 0xBB, 0xBF]
        case .utf16LE: [0xFF, 0xFE]
        case .utf16BE: [0xFE, 0xFF]
        default: []
        }
    }
}

enum LineEnding: String, CaseIterable, Sendable {
    case lf, crlf, cr

    var displayName: String {
        switch self {
        case .lf: String(localized: "Unix (LF)")
        case .crlf: String(localized: "Windows (CR LF)")
        case .cr: String(localized: "Macintosh (CR)")
        }
    }

    var shortName: String {
        switch self {
        case .lf: "LF"
        case .crlf: "CRLF"
        case .cr: "CR"
        }
    }

    var scintillaMode: Int {
        switch self {
        case .lf: Int(SC_EOL_LF)
        case .crlf: Int(SC_EOL_CRLF)
        case .cr: Int(SC_EOL_CR)
        }
    }
}

struct TextFormat: Equatable, Sendable {
    var encoding: TextEncoding = .utf8
    var lineEnding: LineEnding = .lf
}

/// Converts between file bytes and the UTF-8 buffer Scintilla edits.
enum TextCodec {
    struct Decoded {
        var utf8: Data
        var format: TextFormat
    }

    static func decode(_ data: Data) -> Decoded {
        let (encoding, body) = detectEncoding(data)
        let utf8: Data
        if encoding == .utf8 || encoding == .utf8BOM {
            utf8 = body
        } else {
            // Detection only picks encodings that decode successfully.
            let string = String(data: body, encoding: encoding.stringEncoding) ?? ""
            utf8 = Data(string.utf8)
        }
        return Decoded(utf8: utf8, format: TextFormat(encoding: encoding, lineEnding: detectLineEnding(utf8)))
    }

    static func encode(_ utf8: Data, format: TextFormat) throws -> Data {
        var output = Data(format.encoding.byteOrderMark)
        switch format.encoding {
        case .utf8, .utf8BOM:
            output.append(utf8)
        default:
            let string = String(decoding: utf8, as: UTF8.self)
            guard let encoded = string.data(using: format.encoding.stringEncoding, allowLossyConversion: false) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding, userInfo: [
                    NSLocalizedFailureReasonErrorKey:
                        String(localized: "The document contains characters that cannot be saved as \(format.encoding.displayName). Convert it to UTF-8 and save again."),
                ])
            }
            output.append(encoded)
        }
        return output
    }

    private static func detectEncoding(_ data: Data) -> (TextEncoding, Data) {
        for encoding in [TextEncoding.utf8BOM, .utf16LE, .utf16BE] {
            let bom = encoding.byteOrderMark
            if data.starts(with: bom) {
                return (encoding, data.dropFirst(bom.count))
            }
        }
        if String(data: data, encoding: .utf8) != nil {
            return (.utf8, data)
        }
        if String(data: data, encoding: .windowsCP1252) != nil {
            return (.windows1252, data)
        }
        return (.latin1, data)
    }

    /// Picks the most frequent line ending; files without any default to LF.
    private static func detectLineEnding(_ utf8: Data) -> LineEnding {
        var lf = 0, crlf = 0, cr = 0
        utf8.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var i = 0
            let count = bytes.count
            while i < count {
                switch bytes[i] {
                case 0x0D:
                    if i + 1 < count, bytes[i + 1] == 0x0A {
                        crlf += 1
                        i += 1
                    } else {
                        cr += 1
                    }
                case 0x0A:
                    lf += 1
                default:
                    break
                }
                i += 1
            }
        }
        if crlf > lf && crlf >= cr { return .crlf }
        if cr > lf && cr > crlf { return .cr }
        return .lf
    }
}
