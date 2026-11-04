/// Of een agent de tools al mag gebruiken. De eerste keer dat een client zich meldt, vraagt de
/// app het aan de persoon (een melding met Toestaan en Niet toestaan). Tot die toestaat krijgt elke
/// `tools/call` een toolfout die zegt waar het kan; de verbinding blijft open, zodat de agent
/// kan wachten en het daarna opnieuw proberen. `tools/list` geeft de tools wel: hun beschrijving
/// bevat geen gegevens, en een client die de lijst bij de handshake niet krijgt, vraagt hem
/// meestal niet opnieuw.
public struct MCPApproval: Sendable {
    /// Of de client met deze naam (`clientInfo.name` uit `initialize`) is toegestaan. Per aanroep
    /// gevraagd, zodat toestaan meteen telt.
    public let isApproved: @Sendable (_ clientName: String) async -> Bool

    public init(isApproved: @escaping @Sendable (_ clientName: String) async -> Bool) {
        self.isApproved = isApproved
    }

    /// De fout op `tools/call` zolang de client niet is toegestaan. Engels, voor het model.
    public static func waitingMessage(for displayName: String) -> String {
        "Waiting for approval in Pullwatch: allow \(displayName) in the notification or under Settings, Agents."
    }
}
