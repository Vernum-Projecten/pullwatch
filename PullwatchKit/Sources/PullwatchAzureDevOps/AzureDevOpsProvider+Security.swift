import Foundation
import PullwatchCore

/// Advanced Security van Azure DevOps: de actieve meldingen van een repo (code, dependencies en
/// geheimen, die alleen geteld worden) via `advsec.dev.azure.com`. Zonder Advanced Security of
/// zonder recht geeft dat een stille `SecurityFeed`, geen fout.
extension AzureDevOpsProvider {
    public func securityAlerts(in repo: String) async throws -> SecurityScan? {
        guard let slash = repo.firstIndex(of: "/") else { return nil }
        let project = String(repo[..<slash])
        let name = String(repo[repo.index(after: slash)...])
        let alertsPage = baseURL.appending(path: project).appending(path: "_git").appending(path: name).appending(path: "alerts")
        let url = URL(string: "https://advsec.dev.azure.com")!.appending(path: organization).appending(path: project)
            .appending(path: "_apis/alert/repositories").appending(path: name).appending(path: "alerts")

        var items: [AdvancedSecurityAlertDTO] = []
        var continuation: String?
        var pages = 0
        do {
            repeat {
                var query = [
                    URLQueryItem(name: "criteria.states", value: "active"),
                    URLQueryItem(name: "top", value: String(pageSize)),
                ]
                if let continuation { query.append(URLQueryItem(name: "continuationToken", value: continuation)) }
                let (data, response) = try await send(url, apiVersion: "7.2-preview.1", query: query)
                switch response.statusCode {
                case 404:
                    return SecurityScan(feeds: [SecurityFeed(kind: .advancedSecurity, availability: .notEnabled, link: alertsPage)])
                case 401, 403:
                    return SecurityScan(feeds: [SecurityFeed(
                        kind: .advancedSecurity, availability: .needsPermission,
                        link: baseURL.appending(path: "_usersSettings/tokens")
                    )])
                default:
                    try HTTPStatus.check(response, now: now())
                }
                items += try Self.decodeAlerts(data)
                continuation = response.value(forHTTPHeaderField: "x-ms-continuationtoken").flatMap { $0.isEmpty ? nil : $0 }
                pages += 1
            } while continuation != nil && pages < 10
        } catch {
            return SecurityScan(feeds: [SecurityFeed(
                kind: .advancedSecurity, availability: .failed,
                message: (error as? ProviderError)?.userMessage ?? error.localizedDescription
            )])
        }

        let secrets = items.filter { $0.alertType == "secret" }.count
        let alerts = items.filter { $0.alertType != "secret" }.map { $0.alert(alertsPage: alertsPage) }
        return SecurityScan(
            feeds: [SecurityFeed(kind: .advancedSecurity, availability: .available, link: alertsPage)],
            alerts: alerts,
            secretCount: secrets
        )
    }

    /// Een lijst van Azure DevOps staat meestal in `{"count": …, "value": [...]}`; ook een kale lijst mag.
    static func decodeAlerts(_ data: Data) throws -> [AdvancedSecurityAlertDTO] {
        if let wrapped = try? JSONDecoder().decode(ValueList<AdvancedSecurityAlertDTO>.self, from: data) { return wrapped.value }
        return try JSONDecoding.decode([AdvancedSecurityAlertDTO].self, from: data)
    }
}

struct AdvancedSecurityAlertDTO: Decodable {
    struct Tool: Decodable {
        struct Rule: Decodable {
            let opaqueId: String?
            let friendlyName: String?
        }
        let name: String?
        let rules: [Rule]?
    }

    struct PhysicalLocation: Decodable {
        struct Region: Decodable { let lineStart: Int? }
        let filePath: String?
        let region: Region?
    }

    struct LogicalLocation: Decodable {
        let fullyQualifiedName: String?
        let kind: String?
    }

    let alertId: Int
    let alertType: String?
    let severity: String?
    let title: String?
    let firstSeenDate: String?
    let tools: [Tool]?
    let physicalLocations: [PhysicalLocation]?
    let logicalLocations: [LogicalLocation]?

    func alert(alertsPage: URL) -> SecurityAlert {
        let isDependency = alertType == "dependency" || alertType == "malware"
        let component = logicalLocations?.first { $0.kind == "component" || $0.kind == "vulnerableDependency" }
            ?? logicalLocations?.first
        let rule = tools?.first?.rules?.first
        let location = physicalLocations?.first
        let toolSeverity = ["error", "warning", "note"].contains(severity ?? "") ? severity : nil
        return SecurityAlert(
            source: .advancedSecurity,
            kind: isDependency ? .dependency : .code,
            number: alertId,
            title: title ?? rule?.friendlyName ?? "#\(alertId)",
            rule: rule?.opaqueId ?? rule?.friendlyName,
            tool: tools?.first?.name,
            severity: GitHubAdvisory.securitySeverity(severity),
            toolSeverity: toolSeverity,
            path: location?.filePath.map { String($0.drop { $0 == "/" }) },
            line: location?.region?.lineStart,
            package: isDependency ? component?.fullyQualifiedName : nil,
            url: alertsPage.appending(path: String(alertId)),
            createdAt: firstSeenDate.flatMap(DateParsing.parse)
        )
    }
}
