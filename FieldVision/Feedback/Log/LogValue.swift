nonisolated enum LogValue: Encodable, ExpressibleByStringLiteral, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    case text(String)
    case number(Double)
    case integer(Int)
    case flag(Bool)

    init(stringLiteral value: String) {
        self = .text(value)
    }

    init(floatLiteral value: Double) {
        self = .number(value)
    }

    init(integerLiteral value: Int) {
        self = .integer(value)
    }

    init(booleanLiteral value: Bool) {
        self = .flag(value)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case .text(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .integer(let value): try container.encode(value)
            case .flag(let value): try container.encode(value)
        }
    }
}
