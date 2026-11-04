import Darwin
import Foundation
import Security

/// Leest wat `MCPPeerPolicy` nodig heeft van de andere kant van een socket. Achter een protocol,
/// zodat het besluit getest wordt zonder echte handtekeningen.
public protocol MCPPeerInspecting: Sendable {
    /// De gebruiker en handtekening van het proces aan de andere kant van `socket`.
    /// `requirement` is de code requirement die het moet halen, of nil zonder team.
    func evidence(forSocket socket: Int32, requirement: String?) -> MCPPeerEvidence
}

/// De controle op elke nieuwe verbinding: wat de inspecteur ziet, beoordeeld door het beleid.
public struct MCPPeerCheck: Sendable {
    public let policy: MCPPeerPolicy
    private let inspector: any MCPPeerInspecting

    public init(policy: MCPPeerPolicy, inspector: any MCPPeerInspecting = CodeSignaturePeerInspector()) {
        self.policy = policy
        self.inspector = inspector
    }

    /// De controle voor dit proces: zijn eigen gebruiker en het team uit zijn eigen handtekening.
    public static func forCurrentProcess() -> MCPPeerCheck {
        MCPPeerCheck(policy: MCPPeerPolicy(userID: getuid(), teamIdentifier: CodeSignaturePeerInspector.ownTeamIdentifier()))
    }

    /// Of de verbinding op `socket` mag blijven. Leest niets van de socket zelf.
    public func evaluate(socket: Int32) -> MCPPeerDecision {
        policy.decide(inspector.evidence(forSocket: socket, requirement: policy.requirement))
    }
}

/// De echte inspecteur: `getpeereid` voor de gebruiker, en de handtekening via het audit token van
/// de socket (`LOCAL_PEERTOKEN`, `SecCodeCopyGuestWithAttributes` met `kSecGuestAttributeAudit`).
/// Het audit token wijst precies dat proces aan, ook als zijn pid intussen hergebruikt is.
public struct CodeSignaturePeerInspector: MCPPeerInspecting {
    public init() {}

    public func evidence(forSocket socket: Int32, requirement: String?) -> MCPPeerEvidence {
        var user: uid_t = 0
        var group: gid_t = 0
        let userID: uid_t? = getpeereid(socket, &user, &group) == 0 ? user : nil
        return MCPPeerEvidence(userID: userID, signature: signature(forSocket: socket, requirement: requirement))
    }

    private func signature(forSocket socket: Int32, requirement: String?) -> MCPPeerEvidence.Signature {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(socket, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0 else { return .unreadable }
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }

        var guest: SecCode?
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess, let guest else { return .unreadable }
        guard SecCodeCheckValidity(guest, [], nil) == errSecSuccess else { return .invalid }

        var meetsRequirement = false
        if let requirement {
            var compiled: SecRequirement?
            if SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess, let compiled {
                meetsRequirement = SecCodeCheckValidity(guest, [], compiled) == errSecSuccess
            }
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(guest, [], &staticCode) == errSecSuccess, let staticCode,
            let facts = Self.signingFacts(of: staticCode)
        else { return .invalid }
        return .valid(
            MCPPeerEvidence.SigningFacts(
                identifier: facts.identifier, teamIdentifier: facts.team, isAdHoc: facts.isAdHoc, meetsRequirement: meetsRequirement
            )
        )
    }

    /// Het team uit de eigen handtekening, of nil (ad-hoc of ongetekend).
    public static func ownTeamIdentifier() -> String? {
        var current: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &current) == errSecSuccess, let current,
            SecCodeCopyStaticCode(current, [], &staticCode) == errSecSuccess, let staticCode
        else { return nil }
        return signingFacts(of: staticCode)?.team
    }

    /// Identifier, team en ad-hoc uit de handtekening van `code`.
    private static func signingFacts(of code: SecStaticCode) -> (identifier: String, team: String?, isAdHoc: Bool)? {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
            let information = information as? [String: Any],
            let identifier = information[kSecCodeInfoIdentifier as String] as? String
        else { return nil }
        let flags = (information[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let isAdHoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0
        return (identifier, information[kSecCodeInfoTeamIdentifier as String] as? String, isAdHoc)
    }
}
