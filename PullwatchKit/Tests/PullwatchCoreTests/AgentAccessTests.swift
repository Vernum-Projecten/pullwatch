import Foundation
import Testing
import PullwatchCore

/// De keuze of agents Pullwatch mogen gebruiken: standaard nooit, en oude of onbekende configs
/// geven nooit toegang.
@Suite struct AgentAccessTests {
    @Test func `A new config gives agents no access`() {
        #expect(AppConfig().agentAccess == .never)
    }

    @Test func `A config from before the agents gives them no access`() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"accounts":[],"pollInterval":120}"#.utf8))
        #expect(config.agentAccess == .never)
    }

    @Test(arguments: [AgentAccess.never, .whileOpen, .always])
    func `Each mode survives a round trip through config.json`(_ access: AgentAccess) throws {
        var config = AppConfig()
        config.agentAccess = access
        let again = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(again.agentAccess == access)
    }

    @Test(arguments: [("never", AgentAccess.never), ("whileOpen", .whileOpen), ("always", .always)])
    func `The modes have stable names in config.json`(_ name: String, _ access: AgentAccess) throws {
        let json = #"{"accounts":[],"pollInterval":120,"agentAccess":"\#(name)"}"#
        #expect(try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).agentAccess == access)
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppConfig(agentAccess: access))) as? [String: Any]
        #expect(written?["agentAccess"] as? String == name)
    }

    @Test func `An unknown mode gives agents no access`() throws {
        let json = #"{"accounts":[],"pollInterval":120,"agentAccess":"sometimes"}"#
        #expect(try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).agentAccess == .never)
    }

    @Test func `Only never keeps the socket closed`() {
        #expect(!AgentAccess.never.opensSocket)
        #expect(AgentAccess.whileOpen.opensSocket)
        #expect(AgentAccess.always.opensSocket)
    }
}
