import Foundation
import PullwatchCore

/// Een dependency die een gevolgde repository zelf publiceert, zoals de tools het noemen: waar het
/// vandaan komt, en of de versiecheck de nieuwste versie uit dat eigen register kon lezen.
struct MCPInHouse: Encodable, Hashable {
    /// De repository die het publiceert, anders de eigenaar (het Azure-project).
    let source: String
    let repository: String?
    let owner: String
    /// De pagina van de repository bij de dienst.
    let url: URL?
    /// De pagina van het package in het eigen register.
    let registryUrl: URL?
    /// checked, source_off, needs_permission of read_failed.
    let status: String
    let reason: String?

    init(_ inHouse: InHousePackage) {
        source = inHouse.source
        repository = inHouse.repository
        owner = inHouse.owner
        url = inHouse.repositoryURL?.withoutCredentials
        registryUrl = inHouse.registryURL?.withoutCredentials
        switch inHouse.status {
        case .checked:
            status = "checked"
            reason = nil
        case .sourceOff:
            status = "source_off"
            reason = nil
        case .needsPermission(let text):
            status = "needs_permission"
            reason = text.isEmpty ? nil : text
        case .readFailed:
            status = "read_failed"
            reason = nil
        }
    }

    static let schema = MCPSchema.object(
        [
            "source": .string("The followed repository that publishes it (owner/name), or the Azure DevOps project."),
            "repository": .string("The publishing repository, when the service links the package to one."),
            "owner": .string("The user, organization, group or project the package is published under."),
            "url": .string("The publishing repository's web page."),
            "registry_url": .string("The package's page in your own registry."),
            "status": .string(
                "checked: the latest version comes from your own registry, never from the public one. "
                    + "source_off, needs_permission or read_failed (your registry gave no latest version): "
                    + "not checked, never read as up to date.",
                oneOf: ["checked", "source_off", "needs_permission", "read_failed"]
            ),
            "reason": .string("What permission is missing, when status is needs_permission."),
        ],
        required: ["source", "owner", "status"],
        "Set when a followed repository publishes this package to your own registry (an in-house package)."
    )

    /// Wat de tools in `not_checked` zetten als het eigen register niet gelezen is; nil als wel.
    func notChecked(repository: String) -> MCPSourceOff? {
        switch status {
        case "source_off": MCPSourceOff(.packageRegistries, repository: repository)
        case "needs_permission": MCPSourceOff(permission: reason, repository: repository)
        case "read_failed": MCPSourceOff(readFailedFor: repository)
        default: nil
        }
    }
}
