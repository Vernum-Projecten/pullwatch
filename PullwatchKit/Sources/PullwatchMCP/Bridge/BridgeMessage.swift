import Foundation
import MCP

/// Wat de helper van een JSON-RPC-bericht wil weten zonder het verder te begrijpen: is het een
/// verzoek (met id), een antwoord, en welke methode. Een bericht dat geen JSON-object is (een
/// batch, iets kapots) is niets van dat alles en gaat ongewijzigd door.
struct BridgeMessage {
    private let fields: [String: Value]

    init(_ data: Data) {
        fields = (try? JSONDecoder().decode(Value.self, from: data))?.objectValue ?? [:]
    }

    /// De methode van een verzoek of notificatie.
    var method: String? { fields["method"]?.stringValue }

    /// Het id van een verzoek; een notificatie heeft er geen.
    var requestID: Value? {
        guard method != nil, let id = fields["id"], id != .null else { return nil }
        return id
    }

    /// Het id van een antwoord.
    var responseID: Value? {
        guard method == nil, fields["result"] != nil || fields["error"] != nil, let id = fields["id"], id != .null else { return nil }
        return id
    }

    /// Het foutantwoord op verzoek `id`.
    static func error(id: Value, message: String) -> Data {
        let response: Value = [
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": .int(MCPBridge.unavailableCode), "message": .string(message)],
        ]
        return (try? JSONEncoder().encode(response)) ?? Data()
    }

    /// `message` met een ander id, of nil als het geen JSON-object is.
    static func replacingID(of message: Data, with id: Value) -> Data? {
        guard var fields = (try? JSONDecoder().decode(Value.self, from: message))?.objectValue else { return nil }
        fields["id"] = id
        return try? JSONEncoder().encode(Value.object(fields))
    }
}
