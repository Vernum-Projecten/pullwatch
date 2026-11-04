import Foundation
import MCP

/// De argumenten van één `tools/call`, al gecontroleerd tegen het invoerschema van de tool. Een
/// handler leest ze per veld of in één keer als `Decodable`-type.
public struct MCPArguments: Sendable, Hashable {
    /// Alle argumenten zoals de client ze stuurde.
    public let values: [String: Value]

    public init(_ values: [String: Value] = [:]) {
        self.values = values
    }

    // MARK: - Per veld

    public subscript(name: String) -> Value? {
        values[name]
    }

    /// De tekst van `name`, of nil als het veld er niet is.
    public func string(_ name: String) -> String? {
        values[name]?.textValue
    }

    /// Het gehele getal van `name`, of nil als het veld er niet is.
    public func integer(_ name: String) -> Int? {
        values[name]?.integerValue
    }

    /// Waar of onwaar van `name`, of nil als het veld er niet is.
    public func boolean(_ name: String) -> Bool? {
        if case let .bool(value) = values[name] { value } else { nil }
    }

    /// De teksten van de lijst `name`, of nil als het veld er niet is.
    public func strings(_ name: String) -> [String]? {
        guard case let .array(elements) = values[name] else { return nil }
        return elements.compactMap(\.textValue)
    }

    // MARK: - In één keer

    /// Alle argumenten als `T`. Past het niet, dan krijgt het model een resultaat met `isError`,
    /// net als bij een fout tegen het schema, zodat het de aanroep kan verbeteren.
    public func decode<T: Decodable>(as type: T.Type = T.self) throws(MCPToolError) -> T {
        do {
            let data = try JSONEncoder().encode(values)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MCPToolError("The arguments do not fit: \(error.localizedDescription)")
        }
    }
}
