import Foundation

/// Diagnostic integers must not pass through the schema layer's Double model.
indirect enum CrashJSON: Codable, Sendable {
	case null, bool(Bool), string(String), integer(Int64), unsigned(UInt64), decimal(Decimal)
	case array([Self]), object([String: Self])
	init(from decoder: Decoder) throws {
		let value = try decoder.singleValueContainer()
		if value.decodeNil() { self = .null }
		else if let v = try? value.decode(Bool.self) { self = .bool(v) }
		else if let v = try? value.decode(String.self) { self = .string(v) }
		else if let v = try? value.decode(Int64.self) { self = .integer(v) }
		else if let v = try? value.decode(UInt64.self) { self = .unsigned(v) }
		else if let v = try? value.decode(Decimal.self) { self = .decimal(v) }
		else if let v = try? value.decode([Self].self) { self = .array(v) }
		else { self = .object(try value.decode([String: Self].self)) }
	}
	func encode(to encoder: Encoder) throws {
		var value = encoder.singleValueContainer()
		switch self {
		case .null: try value.encodeNil()
		case .bool(let v): try value.encode(v)
		case .string(let v): try value.encode(v)
		case .integer(let v): try value.encode(v)
		case .unsigned(let v): try value.encode(v)
		case .decimal(let v): try value.encode(v)
		case .array(let v): try value.encode(v)
		case .object(let v): try value.encode(v)
		}
	}
}
