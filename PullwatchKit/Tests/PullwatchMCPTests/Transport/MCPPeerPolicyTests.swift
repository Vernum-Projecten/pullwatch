import Darwin
import Foundation
import Testing
@testable import PullwatchMCP

/// Wie met de socket mag praten, als beslistabel zonder echte handtekeningen.
@Suite struct MCPPeerPolicyTests {
    static let me: uid_t = 501
    static let team = "ABCDE12345"

    static func signed(
        _ identifier: String = MCPPeerPolicy.helperIdentifier, team: String? = team, adHoc: Bool = false, meets: Bool = true
    ) -> MCPPeerEvidence.Signature {
        .valid(.init(identifier: identifier, teamIdentifier: team, isAdHoc: adHoc, meetsRequirement: meets))
    }

    static func peer(_ signature: MCPPeerEvidence.Signature, user: uid_t? = me) -> MCPPeerEvidence {
        MCPPeerEvidence(userID: user, signature: signature)
    }

    let teamed = MCPPeerPolicy(userID: me, teamIdentifier: team)
    let teamless = MCPPeerPolicy(userID: me, teamIdentifier: nil)

    // MARK: - Een app met een team

    @Test func `A signed app accepts its own helper`() {
        #expect(teamed.decide(Self.peer(Self.signed())) == .accept)
    }

    struct Refused: Sendable, CustomTestStringConvertible {
        let name: String
        let evidence: MCPPeerEvidence
        var testDescription: String { name }
    }

    static let refusedBySignedApp: [Refused] = [
        Refused(name: "another user", evidence: peer(signed(), user: 502)),
        Refused(name: "no user", evidence: peer(signed(), user: nil)),
        Refused(name: "unsigned", evidence: peer(.invalid)),
        Refused(name: "no signature to read", evidence: peer(.unreadable)),
        Refused(name: "ad-hoc helper", evidence: peer(signed(team: nil, adHoc: true, meets: false))),
        Refused(name: "linker-signed helper", evidence: peer(signed("pullwatch-mcp", team: nil, adHoc: true, meets: false))),
        Refused(name: "another team", evidence: peer(signed(team: "ZZZZZ99999", meets: false))),
        Refused(name: "same team, another program", evidence: peer(signed("nl.torrisi.pullwatch", meets: false))),
        Refused(name: "requirement not met", evidence: peer(signed(meets: false))),
        Refused(name: "the requirement says yes but the identifier is wrong", evidence: peer(signed("com.example.tool"))),
    ]

    @Test(arguments: refusedBySignedApp)
    func `A signed app refuses`(_ refused: Refused) {
        #expect(teamed.decide(refused.evidence) != .accept)
    }

    @Test func `The requirement names the helper and the team of the app`() {
        #expect(
            teamed.requirement
                == #"identifier "nl.torrisi.pullwatch.mcp" and anchor apple generic and certificate leaf[subject.OU] = "ABCDE12345""#
        )
        #expect(teamless.requirement == nil)
    }

    @Test(arguments: ["", "abcde12345", "ABCDE1234", "ABCDE\"1234", "ABCDE123456"])
    func `A team identifier that is not ten capitals and digits counts as no team`(_ team: String) {
        #expect(MCPPeerPolicy(userID: Self.me, teamIdentifier: team).teamIdentifier == nil)
    }

    // MARK: - Een app zonder team (debug, CI)

    @Test func `An app without a team accepts the helper Xcode signed ad hoc`() {
        #expect(teamless.decide(Self.peer(Self.signed(team: nil, adHoc: true, meets: false))) == .accept)
    }

    @Test func `An app without a team accepts the helper the linker signed`() {
        #expect(teamless.decide(Self.peer(Self.signed("pullwatch-mcp", team: nil, adHoc: true, meets: false))) == .accept)
    }

    @Test func `An app without a team accepts a helper signed with a certificate`() {
        #expect(teamless.decide(Self.peer(Self.signed(meets: false))) == .accept)
    }

    static let refusedByTeamlessApp: [Refused] = [
        Refused(name: "another user", evidence: peer(signed(team: nil, adHoc: true), user: 0)),
        Refused(name: "unsigned", evidence: peer(.invalid)),
        Refused(name: "no signature to read", evidence: peer(.unreadable)),
        Refused(name: "another ad-hoc program", evidence: peer(signed("python3", team: nil, adHoc: true, meets: false))),
        Refused(name: "the linker name with a certificate", evidence: peer(signed("pullwatch-mcp", adHoc: false, meets: false))),
    ]

    @Test(arguments: refusedByTeamlessApp)
    func `An app without a team refuses`(_ refused: Refused) {
        #expect(teamless.decide(refused.evidence) != .accept)
    }

    // MARK: - De echte inspecteur

    @Test func `The real inspector sees this user on a socket pair`() throws {
        let (near, far) = try socketPair()
        defer {
            near.close()
            far.close()
        }
        let evidence = CodeSignaturePeerInspector().evidence(forSocket: near.rawDescriptorForTesting, requirement: nil)
        #expect(evidence.userID == getuid())
        // Het testproces is niet de helper; wat zijn handtekening ook is, hij komt er niet in.
        #expect(MCPPeerCheck.forCurrentProcess().policy.decide(evidence) != .accept)
    }
}
