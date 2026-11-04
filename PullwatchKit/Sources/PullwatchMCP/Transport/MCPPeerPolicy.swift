public import Darwin

/// Wat de app weet van het proces aan de andere kant van een verbinding, voordat er één byte van
/// gelezen is: de gebruiker (`getpeereid`) en de codehandtekening (via het audit token).
public struct MCPPeerEvidence: Sendable, Equatable {
    /// De gebruiker van het proces, of nil als de kernel hem niet gaf.
    public var userID: uid_t?
    public var signature: Signature

    public enum Signature: Sendable, Equatable {
        /// Geen proces of handtekening te vinden (het proces is al weg, geen audit token).
        case unreadable
        /// Ongetekend, of een handtekening die niet (meer) klopt.
        case invalid
        /// Een geldige handtekening.
        case valid(SigningFacts)
    }

    /// Wat de geldige handtekening zegt.
    public struct SigningFacts: Sendable, Equatable {
        /// De code-identifier (`nl.torrisi.pullwatch.mcp`).
        public var identifier: String
        /// Het team van het certificaat; nil bij ad-hoc.
        public var teamIdentifier: String?
        /// Ad-hoc getekend (geen certificaat), ook door de linker.
        public var isAdHoc: Bool
        /// Of de code voldoet aan `MCPPeerPolicy.requirement` (alleen gecontroleerd als die er is).
        public var meetsRequirement: Bool

        public init(identifier: String, teamIdentifier: String?, isAdHoc: Bool, meetsRequirement: Bool) {
            self.identifier = identifier
            self.teamIdentifier = teamIdentifier
            self.isAdHoc = isAdHoc
            self.meetsRequirement = meetsRequirement
        }
    }

    public init(userID: uid_t?, signature: Signature) {
        self.userID = userID
        self.signature = signature
    }
}

/// Of een verbinding met de socket mag blijven.
public enum MCPPeerDecision: Sendable, Equatable {
    case accept
    /// Weigeren, met de reden voor het log.
    case refuse(String)
}

/// Wie met de socket mag praten: alleen de helper `pullwatch-mcp` van dezelfde gebruiker, en
/// getekend door hetzelfde team als de app. Het besluit staat los van de echte handtekeningen,
/// zodat de tabel getest wordt zonder certificaten.
///
/// - Een app met een team (Developer ID, of Apple Development): de helper moet voldoen aan
///   `identifier "nl.torrisi.pullwatch.mcp" and anchor apple generic and certificate
///   leaf[subject.OU] = "<team van de app>"`. Een ad-hoc helper of een met een ander team wordt
///   geweigerd.
/// - Een app zonder team (een debug-build, de ongetekende build van CI): een geldig getekende
///   helper met identifier `nl.torrisi.pullwatch.mcp` (zo tekent Xcode hem ad-hoc), of een door de
///   linker ad-hoc getekende met de bestandsnaam `pullwatch-mcp` als identifier (een build met
///   `CODE_SIGNING_ALLOWED=NO`). Elke andere identifier, en ongetekende code, wordt geweigerd.
public struct MCPPeerPolicy: Sendable, Equatable {
    /// De bundle id van de helper, en de identifier in zijn handtekening.
    public static let helperIdentifier = "nl.torrisi.pullwatch.mcp"
    /// De identifier die de linker een ongetekende build geeft: de naam van het bestand.
    public static let linkerSignedHelperIdentifier = "pullwatch-mcp"

    /// De gebruiker van de app.
    public var userID: uid_t
    /// Het team van de app zelf; nil zonder team (ad-hoc of ongetekend).
    public var teamIdentifier: String?

    public init(userID: uid_t, teamIdentifier: String?) {
        self.userID = userID
        // Een team-id is tien hoofdletters en cijfers; iets anders komt niet in een requirement.
        self.teamIdentifier = teamIdentifier.flatMap { team in
            team.utf8.count == 10 && team.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) } ? team : nil
        }
    }

    /// De code requirement die de helper moet halen, of nil zonder team.
    public var requirement: String? {
        teamIdentifier.map { team in
            #"identifier "\#(Self.helperIdentifier)" and anchor apple generic and certificate leaf[subject.OU] = "\#(team)""#
        }
    }

    public func decide(_ evidence: MCPPeerEvidence) -> MCPPeerDecision {
        guard let peer = evidence.userID else { return .refuse("no peer user") }
        guard peer == userID else { return .refuse("peer runs as user \(peer), not \(userID)") }
        let facts: MCPPeerEvidence.SigningFacts
        switch evidence.signature {
        case .unreadable:
            return .refuse("no code signature to check")
        case .invalid:
            return .refuse("unsigned or invalid code signature")
        case .valid(let signing):
            facts = signing
        }

        if let teamIdentifier {
            guard facts.meetsRequirement, facts.identifier == Self.helperIdentifier,
                facts.teamIdentifier == teamIdentifier, !facts.isAdHoc
            else {
                return .refuse("\(facts.identifier) (team \(facts.teamIdentifier ?? "none")) is not the pullwatch-mcp helper of team \(teamIdentifier)")
            }
            return .accept
        }

        if facts.identifier == Self.helperIdentifier { return .accept }
        if facts.isAdHoc, facts.identifier == Self.linkerSignedHelperIdentifier { return .accept }
        return .refuse("\(facts.identifier) is not the pullwatch-mcp helper")
    }
}
