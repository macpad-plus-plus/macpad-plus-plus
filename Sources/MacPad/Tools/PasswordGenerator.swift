import Foundation

/// Random passwords with a minimum number of each kind of character.
///
/// Every kind with a minimum above zero is used; the rest of the length is
/// drawn from all of them, then the characters are shuffled. Randomness comes
/// from the system's cryptographically secure generator.
struct PasswordGenerator: Equatable {
    var length = 16
    var minimumUppercase = 5
    var minimumLowercase = 5
    var minimumDigits = 4
    var minimumSymbols = 2
    /// Leaves out characters that are easy to mistake for one another.
    var excludeAmbiguous = false

    static let lengthRange = 4...128
    static let uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    static let lowercase = "abcdefghijklmnopqrstuvwxyz"
    static let digits = "0123456789"
    static let symbols = "!#$%&()*+,-./:;<=>?@[]^_{|}~"
    /// 0, O and o; 1, I, l and |; and the pairs S 5, B 8, Z 2, G 6.
    static let ambiguous = "0Oo1Il|S5B8Z2G6"

    // MARK: Distribution

    /// How the length is shared out by default: 16 characters are 5 uppercase,
    /// 5 lowercase, 4 numbers and 2 symbols.
    static let weights = [5, 5, 4, 2]

    /// Splits `total` among the kinds marked in `enabled`, in proportion to
    /// `weights`, rounding so the counts add up exactly (largest remainder).
    /// Every enabled kind gets at least one character while there are enough.
    static func distribute(_ total: Int, enabled: [Bool]) -> [Int] {
        let weights = zip(Self.weights, enabled).map { $1 ? $0 : 0 }
        let weightSum = weights.reduce(0, +)
        guard weightSum > 0, total > 0 else { return weights.map { _ in 0 } }
        let shares = weights.map { Double(total * $0) / Double(weightSum) }
        var counts = shares.map { Int($0.rounded(.down)) }
        let byRemainder = shares.indices.filter { weights[$0] > 0 }
            .sorted { shares[$0] - Double(counts[$0]) > shares[$1] - Double(counts[$1]) }
        for index in byRemainder.prefix(total - counts.reduce(0, +)) {
            counts[index] += 1
        }
        // A small total can round an enabled kind down to nothing; take one
        // from the largest instead.
        for index in counts.indices where enabled[index] && counts[index] == 0 {
            guard let largest = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[largest] > 1 else { break }
            counts[largest] -= 1
            counts[index] += 1
        }
        return counts
    }

    /// The counts of each kind, in `weights` order.
    var counts: [Int] {
        get { [minimumUppercase, minimumLowercase, minimumDigits, minimumSymbols] }
        set { (minimumUppercase, minimumLowercase, minimumDigits, minimumSymbols) = (newValue[0], newValue[1], newValue[2], newValue[3]) }
    }

    /// A new length, shared out again among the kinds in use.
    mutating func setLength(_ newLength: Int) {
        length = min(max(newLength, Self.lengthRange.lowerBound), Self.lengthRange.upperBound)
        var enabled = counts.map { $0 > 0 }
        if !enabled.contains(true) { enabled = Array(repeating: true, count: 4) }
        counts = Self.distribute(length, enabled: enabled)
    }

    /// One kind set by hand: the length stays, and the other kinds in use
    /// share what is left, keeping at least one each. 0 leaves a kind out.
    mutating func setCount(_ value: Int, at index: Int) {
        var others = counts.map { $0 > 0 }
        others[index] = false
        let otherCount = others.filter { $0 }.count
        // The only kind in use has nowhere to give characters to.
        guard otherCount > 0 else {
            counts = counts.indices.map { $0 == index ? length : 0 }
            return
        }
        let kept = min(max(value, 0), length - otherCount)
        var updated = Self.distribute(length - kept, enabled: others)
        updated[index] = kept
        counts = updated
    }

    enum Problem: Equatable {
        /// No kind of character has a minimum above zero.
        case noKinds
        /// The minimums add up to more than the length.
        case minimumsExceedLength
    }

    var problem: Problem? {
        let minimums = [minimumUppercase, minimumLowercase, minimumDigits, minimumSymbols]
        if minimums.allSatisfy({ $0 <= 0 }) { return .noKinds }
        if minimums.reduce(0, +) > length { return .minimumsExceedLength }
        return nil
    }

    /// The characters of each kind in use, paired with its minimum.
    private var kinds: [(characters: [Character], minimum: Int)] {
        [(Self.uppercase, minimumUppercase), (Self.lowercase, minimumLowercase),
         (Self.digits, minimumDigits), (Self.symbols, minimumSymbols)]
            .filter { $0.1 > 0 }
            .map { set, minimum in
                (Array(excludeAmbiguous ? set.filter { !Self.ambiguous.contains($0) } : set), minimum)
            }
    }

    func generate() -> String? {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    func generate<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String? {
        guard problem == nil else { return nil }
        let kinds = kinds
        var characters: [Character] = []
        for kind in kinds {
            for _ in 0..<kind.minimum {
                characters.append(kind.characters.randomElement(using: &generator)!)
            }
        }
        let pool = kinds.flatMap(\.characters)
        while characters.count < length {
            characters.append(pool.randomElement(using: &generator)!)
        }
        characters.shuffle(using: &generator)
        return String(characters)
    }
}
