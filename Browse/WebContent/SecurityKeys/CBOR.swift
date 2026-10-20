import Foundation

/// The subset of CBOR (RFC 8949) that CTAP2 uses.
///
/// Maps keep their pairs in an array so a decoded value re-encodes the way it
/// came in. `encoded()` writes maps in CTAP2 canonical order (shorter encoded
/// key first, then bytewise), which is what authenticators require.
indirect enum CBOR: Equatable, Sendable {
    case unsigned(UInt64)
    /// Stores the encoded argument `n`; the value is `-1 - n`.
    case negative(UInt64)
    case bytes(Data)
    case text(String)
    case array([CBOR])
    case map([(CBOR, CBOR)])
    case tagged(UInt64, CBOR)
    case bool(Bool)
    case null
    case undefined
    case double(Double)

    static func int(_ value: Int) -> CBOR {
        value >= 0 ? .unsigned(UInt64(value)) : .negative(UInt64(-1 - value))
    }

    static func == (lhs: CBOR, rhs: CBOR) -> Bool {
        lhs.encoded() == rhs.encoded()
    }

    // MARK: Accessors

    var intValue: Int? {
        switch self {
        case .unsigned(let v): return v <= UInt64(Int.max) ? Int(v) : nil
        case .negative(let n): return n < UInt64(Int.max) ? -1 - Int(n) : nil
        default: return nil
        }
    }
    var bytesValue: Data? { if case .bytes(let d) = self { return d }; return nil }
    var textValue: String? { if case .text(let s) = self { return s }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var arrayValue: [CBOR]? { if case .array(let a) = self { return a }; return nil }
    var mapValue: [(CBOR, CBOR)]? { if case .map(let m) = self { return m }; return nil }

    subscript(key: Int) -> CBOR? { lookup(.int(key)) }
    subscript(key: String) -> CBOR? { lookup(.text(key)) }

    private func lookup(_ key: CBOR) -> CBOR? {
        guard case .map(let pairs) = self else { return nil }
        let k = key.encoded()
        return pairs.first(where: { $0.0.encoded() == k })?.1
    }

    // MARK: Encoding

    func encoded() -> Data {
        var out = Data()
        encode(into: &out)
        return out
    }

    private static func head(_ major: UInt8, _ value: UInt64, into out: inout Data) {
        let m = major << 5
        switch value {
        case 0..<24:
            out.append(m | UInt8(value))
        case 24...0xFF:
            out.append(m | 24); out.append(UInt8(value))
        case 0x100...0xFFFF:
            out.append(m | 25)
            out.append(UInt8(value >> 8)); out.append(UInt8(value & 0xFF))
        case 0x10000...0xFFFF_FFFF:
            out.append(m | 26)
            for shift in stride(from: 24, through: 0, by: -8) { out.append(UInt8((value >> UInt64(shift)) & 0xFF)) }
        default:
            out.append(m | 27)
            for shift in stride(from: 56, through: 0, by: -8) { out.append(UInt8((value >> UInt64(shift)) & 0xFF)) }
        }
    }

    private func encode(into out: inout Data) {
        switch self {
        case .unsigned(let v): Self.head(0, v, into: &out)
        case .negative(let n): Self.head(1, n, into: &out)
        case .bytes(let d): Self.head(2, UInt64(d.count), into: &out); out.append(d)
        case .text(let s):
            let d = Data(s.utf8)
            Self.head(3, UInt64(d.count), into: &out); out.append(d)
        case .array(let items):
            Self.head(4, UInt64(items.count), into: &out)
            for item in items { item.encode(into: &out) }
        case .map(let pairs):
            Self.head(5, UInt64(pairs.count), into: &out)
            let sorted = pairs
                .map { ($0.0.encoded(), $0.1) }
                .sorted { a, b in
                    a.0.count != b.0.count ? a.0.count < b.0.count : a.0.lexicographicallyPrecedes(b.0)
                }
            for (key, value) in sorted {
                out.append(key)
                value.encode(into: &out)
            }
        case .tagged(let tag, let value):
            Self.head(6, tag, into: &out); value.encode(into: &out)
        case .bool(let b): out.append(b ? 0xF5 : 0xF4)
        case .null: out.append(0xF6)
        case .undefined: out.append(0xF7)
        case .double(let d):
            out.append(0xFB)
            let bits = d.bitPattern
            for shift in stride(from: 56, through: 0, by: -8) { out.append(UInt8((bits >> UInt64(shift)) & 0xFF)) }
        }
    }

    // MARK: Decoding

    struct DecodingError: Error {}

    /// Decodes one item from the start of `data`. Returns it and how many
    /// bytes it used, so callers can find what follows (authData does this).
    static func decode(_ data: Data) throws -> (CBOR, Int) {
        var reader = Reader(bytes: [UInt8](data))
        let value = try reader.item(depth: 0)
        return (value, reader.offset)
    }

    static func decodeAll(_ data: Data) throws -> CBOR {
        let (value, used) = try decode(data)
        guard used == data.count else { throw DecodingError() }
        return value
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else { throw DecodingError() }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, offset + count <= bytes.count else { throw DecodingError() }
            defer { offset += count }
            return Array(bytes[offset..<offset + count])
        }

        mutating func argument(_ info: UInt8) throws -> UInt64 {
            switch info {
            case 0..<24: return UInt64(info)
            case 24: return UInt64(try byte())
            case 25, 26, 27:
                let n = info == 25 ? 2 : info == 26 ? 4 : 8
                return try take(n).reduce(0) { $0 << 8 | UInt64($1) }
            default: throw DecodingError() // Indefinite lengths aren't used by CTAP2.
            }
        }

        mutating func length(_ info: UInt8) throws -> Int {
            let n = try argument(info)
            guard n <= UInt64(bytes.count - offset) * 2 + 16 else { throw DecodingError() }
            return Int(n)
        }

        mutating func item(depth: Int) throws -> CBOR {
            guard depth < 32 else { throw DecodingError() }
            let initial = try byte()
            let major = initial >> 5
            let info = initial & 0x1F
            switch major {
            case 0: return .unsigned(try argument(info))
            case 1: return .negative(try argument(info))
            case 2: return .bytes(Data(try take(try length(info))))
            case 3:
                guard let s = String(bytes: try take(try length(info)), encoding: .utf8) else { throw DecodingError() }
                return .text(s)
            case 4:
                let n = try length(info)
                var items: [CBOR] = []
                for _ in 0..<n { items.append(try item(depth: depth + 1)) }
                return .array(items)
            case 5:
                let n = try length(info)
                var pairs: [(CBOR, CBOR)] = []
                for _ in 0..<n {
                    let k = try item(depth: depth + 1)
                    pairs.append((k, try item(depth: depth + 1)))
                }
                return .map(pairs)
            case 6: return .tagged(try argument(info), try item(depth: depth + 1))
            default:
                switch info {
                case 20: return .bool(false)
                case 21: return .bool(true)
                case 22: return .null
                case 23: return .undefined
                case 25:
                    // Half precision by hand: Float16 doesn't exist on Intel Macs.
                    let bits = Int(try argument(25))
                    let exponent = (bits >> 10) & 0x1F, mantissa = Double(bits & 0x3FF)
                    let magnitude: Double = exponent == 0 ? mantissa * pow(2, -24)
                        : exponent == 31 ? (mantissa == 0 ? .infinity : .nan)
                        : (1 + mantissa / 1024) * pow(2, Double(exponent - 15))
                    return .double(bits & 0x8000 != 0 ? -magnitude : magnitude)
                case 26: return .double(Double(Float(bitPattern: UInt32(try argument(26)))))
                case 27: return .double(Double(bitPattern: try argument(27)))
                default: throw DecodingError()
                }
            }
        }
    }
}
