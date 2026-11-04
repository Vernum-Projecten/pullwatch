import Foundation
import MCP

/// Het JSON Schema (2020-12) van de invoer of uitvoer van een tool, als Swift-waarde. Eén
/// beschrijving levert het schema dat de agent in `tools/list` ziet en de controle die de server
/// op de argumenten doet, zodat die twee nooit uit elkaar lopen. Alleen de onderdelen die
/// Pullwatch nodig heeft; elk object weigert onbekende velden, zodat een tikfout van een model
/// een duidelijke fout geeft in plaats van een stil genegeerd filter.
public struct MCPSchema: Sendable, Hashable {
    indirect enum Kind: Sendable, Hashable {
        case string(allowed: [String]?, maxLength: Int?, format: String?)
        case integer(minimum: Int?, maximum: Int?)
        case number
        case boolean
        case array(items: MCPSchema, maxItems: Int?)
        /// `additional` nil: geen andere velden dan `properties`; anders het schema van elke
        /// andere waarde (een woordenboek zoals aantallen per ernst).
        case object(properties: [String: MCPSchema], required: [String], additional: MCPSchema?)
    }

    let kind: Kind
    /// Wat het veld betekent, voor het model.
    public let description: String?

    // MARK: - Bouwen

    /// Een tekst, eventueel alleen een van `oneOf`, hoogstens `maxLength` tekens, of met een
    /// `format` zoals `date-time`.
    public static func string(
        _ description: String? = nil, oneOf allowed: [String]? = nil, maxLength: Int? = nil, format: String? = nil
    ) -> MCPSchema {
        MCPSchema(kind: .string(allowed: allowed, maxLength: maxLength, format: format), description: description)
    }

    /// Een geheel getal, eventueel tussen `minimum` en `maximum` (beide inclusief).
    public static func integer(_ description: String? = nil, minimum: Int? = nil, maximum: Int? = nil) -> MCPSchema {
        MCPSchema(kind: .integer(minimum: minimum, maximum: maximum), description: description)
    }

    /// Een getal, geheel of niet.
    public static func number(_ description: String? = nil) -> MCPSchema {
        MCPSchema(kind: .number, description: description)
    }

    /// Waar of onwaar.
    public static func boolean(_ description: String? = nil) -> MCPSchema {
        MCPSchema(kind: .boolean, description: description)
    }

    /// Een lijst van `items`, eventueel hoogstens `maxItems` lang.
    public static func array(of items: MCPSchema, _ description: String? = nil, maxItems: Int? = nil) -> MCPSchema {
        MCPSchema(kind: .array(items: items, maxItems: maxItems), description: description)
    }

    /// Een object met precies deze velden; `required` moeten er zijn.
    public static func object(
        _ properties: [String: MCPSchema], required: [String] = [], _ description: String? = nil
    ) -> MCPSchema {
        MCPSchema(kind: .object(properties: properties, required: required, additional: nil), description: description)
    }

    /// Een object met vrije sleutels en waarden van één schema.
    public static func dictionary(of values: MCPSchema, _ description: String? = nil) -> MCPSchema {
        MCPSchema(kind: .object(properties: [:], required: [], additional: values), description: description)
    }

    /// Of dit een object is: de invoer en uitvoer van een tool moeten dat zijn.
    var isObject: Bool {
        if case .object = kind { true } else { false }
    }

    // MARK: - JSON Schema

    /// Het schema zoals het in `tools/list` staat (JSON Schema 2020-12, de standaard van MCP).
    public var jsonSchema: Value {
        var schema: [String: Value] = [:]
        switch kind {
        case let .string(allowed, maxLength, format):
            schema["type"] = "string"
            if let allowed { schema["enum"] = .array(allowed.map(Value.string)) }
            if let maxLength { schema["maxLength"] = .int(maxLength) }
            if let format { schema["format"] = .string(format) }
        case let .integer(minimum, maximum):
            schema["type"] = "integer"
            if let minimum { schema["minimum"] = .int(minimum) }
            if let maximum { schema["maximum"] = .int(maximum) }
        case .number:
            schema["type"] = "number"
        case .boolean:
            schema["type"] = "boolean"
        case let .array(items, maxItems):
            schema["type"] = "array"
            schema["items"] = items.jsonSchema
            if let maxItems { schema["maxItems"] = .int(maxItems) }
        case let .object(properties, required, additional):
            schema["type"] = "object"
            schema["properties"] = .object(properties.mapValues(\.jsonSchema))
            if !required.isEmpty { schema["required"] = .array(required.map(Value.string)) }
            schema["additionalProperties"] = additional?.jsonSchema ?? false
        }
        if let description { schema["description"] = .string(description) }
        return .object(schema)
    }

    // MARK: - Controleren

    /// Controleert `value` tegen dit schema. De fout noemt het veld (`state`, `filters.repo`,
    /// `repos[2]`) en wat er mis is, in het Engels, want een model leest hem.
    public func validate(_ value: Value) throws(MCPSchemaViolation) {
        try validate(value, at: "")
    }

    private func validate(_ value: Value, at path: String) throws(MCPSchemaViolation) {
        let name = path.isEmpty ? "arguments" : "`\(path)`"
        switch kind {
        case let .string(allowed, maxLength, _):
            try Self.validateString(value, named: name, allowed: allowed, maxLength: maxLength)
        case let .integer(minimum, maximum):
            try Self.validateInteger(value, named: name, minimum: minimum, maximum: maximum)
        case .number:
            guard value.isNumber else { throw MCPSchemaViolation("\(name) must be a number") }
        case .boolean:
            guard case .bool = value else { throw MCPSchemaViolation("\(name) must be true or false") }
        case let .array(items, maxItems):
            guard case let .array(elements) = value else { throw MCPSchemaViolation("\(name) must be an array") }
            if let maxItems, elements.count > maxItems {
                throw MCPSchemaViolation("\(name) must have at most \(maxItems) items")
            }
            for (index, element) in elements.enumerated() {
                try items.validate(element, at: "\(path)[\(index)]")
            }
        case let .object(properties, required, additional):
            guard case let .object(fields) = value else { throw MCPSchemaViolation("\(name) must be an object") }
            try Self.validateFields(fields, at: path, properties: properties, required: required, additional: additional)
        }
    }

    private static func validateString(
        _ value: Value, named name: String, allowed: [String]?, maxLength: Int?
    ) throws(MCPSchemaViolation) {
        guard let text = value.textValue else { throw MCPSchemaViolation("\(name) must be a string") }
        if let allowed, !allowed.contains(text) {
            throw MCPSchemaViolation("\(name) must be one of \(allowed.joined(separator: ", "))")
        }
        if let maxLength, text.count > maxLength {
            throw MCPSchemaViolation("\(name) must be at most \(maxLength) characters")
        }
    }

    private static func validateInteger(
        _ value: Value, named name: String, minimum: Int?, maximum: Int?
    ) throws(MCPSchemaViolation) {
        guard let number = value.integerValue else { throw MCPSchemaViolation("\(name) must be an integer") }
        if let minimum, number < minimum { throw MCPSchemaViolation("\(name) must be at least \(minimum)") }
        if let maximum, number > maximum { throw MCPSchemaViolation("\(name) must be at most \(maximum)") }
    }

    private static func validateFields(
        _ fields: [String: Value], at path: String, properties: [String: MCPSchema], required: [String], additional: MCPSchema?
    ) throws(MCPSchemaViolation) {
        for key in required where fields[key] == nil {
            throw MCPSchemaViolation("`\(join(path, key))` is required")
        }
        // Op naam gesorteerd, zodat dezelfde invoer altijd dezelfde fout geeft.
        for (key, field) in fields.sorted(by: { $0.key < $1.key }) {
            guard let schema = properties[key] ?? additional else {
                let known = properties.keys.sorted().joined(separator: ", ")
                throw MCPSchemaViolation("`\(join(path, key))` is not a known field" + (known.isEmpty ? "" : " (known: \(known))"))
            }
            try schema.validate(field, at: join(path, key))
        }
    }

    private static func join(_ path: String, _ key: String) -> String {
        path.isEmpty ? key : "\(path).\(key)"
    }
}

/// Waarom een waarde niet bij haar schema past, in een zin voor het model.
public struct MCPSchemaViolation: Error, Sendable, Hashable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

// MARK: - Waarden lezen

extension Value {
    /// De tekst van een tekstwaarde. De SDK leest een tekst die op een data-URL lijkt als `.data`;
    /// die telt hier als de tekst die de client stuurde.
    var textValue: String? {
        switch self {
        case let .string(text):
            text
        case .data:
            (try? JSONEncoder().encode(self)).flatMap { try? JSONDecoder().decode(String.self, from: $0) }
        default:
            nil
        }
    }

    /// Of de waarde een getal is, geheel of niet.
    var isNumber: Bool {
        switch self {
        case .int, .double: true
        default: false
        }
    }

    /// Een geheel getal, ook als JSON het als `3.0` schreef.
    var integerValue: Int? {
        switch self {
        case let .int(number):
            number
        case let .double(number) where number.rounded() == number && abs(number) < 9.0e15:
            Int(number)
        default:
            nil
        }
    }
}
