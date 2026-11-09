import Foundation

/// Any JSON, kept as it was. An event of a kind this build does not know yet carries its
/// payload this way, so the line reads, counts and writes back byte for byte, and the fold
/// leaves it alone until a build that knows the kind reads the same file.
public indirect enum JSONValue: Hashable, Sendable, Codable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not JSON"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let object): try container.encode(object)
        case .array(let array): try container.encode(array)
        case .string(let string): try container.encode(string)
        case .number(let number):
            // A whole number stays whole, as it was written.
            if number == number.rounded(), abs(number) < 1e15 { try container.encode(Int64(number)) } else { try container.encode(number) }
        case .bool(let bool): try container.encode(bool)
        case .null: try container.encodeNil()
        }
    }
}
