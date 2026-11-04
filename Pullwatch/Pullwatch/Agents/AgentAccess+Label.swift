import Foundation
import PullwatchCore

extension AgentAccess {
    /// De keuze zoals Instellingen, Agents hem toont, naar de woorden van Xcode ("While Xcode is
    /// Open").
    var label: LocalizedStringResource {
        switch self {
        case .never: LocalizedStringResource("Nooit", comment: "Instellingen, Agents: agents mogen Pullwatch nooit gebruiken")
        case .whileOpen: LocalizedStringResource("Zolang Pullwatch open is", comment: "Instellingen, Agents: agents mogen Pullwatch gebruiken zolang de app draait")
        case .always: LocalizedStringResource("Altijd", comment: "Instellingen, Agents: agents mogen Pullwatch altijd gebruiken; de helper start de app als die niet draait")
        }
    }
}
