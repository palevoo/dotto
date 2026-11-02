import Foundation

/// Universally unique, lexicographically sortable identifier.
/// 48 bits of milliseconds since the epoch, 80 bits of randomness, Crockford base32, 26 characters.
/// Sorting by the string sorts by time. Made on the device, never by a server.
public struct ULID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    private static let decodeTable: [Character: UInt8] = {
        var table: [Character: UInt8] = [:]
        for (index, character) in alphabet.enumerated() {
            table[character] = UInt8(index)
            table[Character(character.lowercased())] = UInt8(index)
        }
        return table
    }()

    public let string: String

    public init(timestamp: Date = Date()) {
        self.init(milliseconds: ULID.milliseconds(from: timestamp), random: ULID.randomBytes())
    }

    public init(milliseconds: UInt64, random: [UInt8]) {
        precondition(random.count == 10, "ULID randomness is 10 bytes")
        precondition(milliseconds < (1 << 48), "ULID time is 48 bits")
        string = ULID.encode(milliseconds: milliseconds, random: random)
    }

    public init?(_ string: String) {
        guard string.count == 26,
              let first = string.first,
              let firstValue = ULID.decodeTable[first],
              firstValue <= 7,
              string.allSatisfy({ ULID.decodeTable[$0] != nil })
        else { return nil }
        self.string = string.uppercased()
    }

    public var milliseconds: UInt64 {
        var value: UInt64 = 0
        for character in string.prefix(10) {
            value = (value << 5) | UInt64(ULID.decodeTable[character]!)
        }
        return value
    }

    public var timestamp: Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    public var randomBytes: [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 10)
        var bitCursor = 0
        for character in string.dropFirst(10) {
            let value = ULID.decodeTable[character]!
            for bit in stride(from: 4, through: 0, by: -1) {
                if (value >> UInt8(bit)) & 1 == 1 {
                    bytes[bitCursor / 8] |= 1 << (7 - UInt8(bitCursor % 8))
                }
                bitCursor += 1
            }
        }
        return bytes
    }

    public var description: String { string }

    public static func < (lhs: ULID, rhs: ULID) -> Bool { lhs.string < rhs.string }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let ulid = ULID(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a ULID: \(raw)"))
        }
        self = ulid
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }

    // MARK: - Internals

    static func milliseconds(from date: Date) -> UInt64 {
        UInt64(max(0, date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    static func randomBytes() -> [UInt8] {
        (0..<10).map { _ in UInt8.random(in: .min ... .max) }
    }

    private static func encode(milliseconds: UInt64, random: [UInt8]) -> String {
        var characters: [Character] = []
        characters.reserveCapacity(26)
        for index in 0..<10 {
            let shift = UInt64(5 * (9 - index))
            characters.append(alphabet[Int((milliseconds >> shift) & 0x1F)])
        }
        for index in 0..<16 {
            characters.append(alphabet[Int(fiveBits(of: random, at: 5 * index))])
        }
        return String(characters)
    }

    private static func fiveBits(of bytes: [UInt8], at offset: Int) -> UInt8 {
        var value: UInt8 = 0
        for bitIndex in offset..<(offset + 5) {
            let byte = bytes[bitIndex / 8]
            let bit = (byte >> (7 - UInt8(bitIndex % 8))) & 1
            value = (value << 1) | bit
        }
        return value
    }
}

/// Hands out ULIDs that strictly increase even within one millisecond,
/// so events made in a burst on one device keep their order.
public final class ULIDGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var lastMilliseconds: UInt64 = 0
    private var lastRandom: [UInt8] = []

    public init() {}

    public func next(at date: Date = Date()) -> ULID {
        lock.lock()
        defer { lock.unlock() }

        var milliseconds = ULID.milliseconds(from: date)
        if milliseconds <= lastMilliseconds, !lastRandom.isEmpty {
            milliseconds = lastMilliseconds
            if !increment(&lastRandom) {
                milliseconds += 1
                lastRandom = ULID.randomBytes()
            }
        } else {
            lastRandom = ULID.randomBytes()
        }
        lastMilliseconds = milliseconds
        return ULID(milliseconds: milliseconds, random: lastRandom)
    }

    /// Adds one to the 80-bit big-endian number. Returns false on overflow.
    private func increment(_ bytes: inout [UInt8]) -> Bool {
        var index = bytes.count - 1
        while index >= 0 {
            if bytes[index] == .max {
                bytes[index] = 0
                index -= 1
            } else {
                bytes[index] += 1
                return true
            }
        }
        return false
    }
}
