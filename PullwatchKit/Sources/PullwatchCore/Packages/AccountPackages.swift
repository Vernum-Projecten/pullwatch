public import Foundation

/// De gepubliceerde packages van één account, zoals de dagelijkse versiecheck ze bewaart
/// (`VersionReport.publishedPackages`).
public struct AccountPackages: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID { accountId }
    public let accountId: UUID
    public let result: PublishedPackages
    public let checkedAt: Date

    public init(accountId: UUID, result: PublishedPackages, checkedAt: Date) {
        self.accountId = accountId
        self.result = result
        self.checkedAt = checkedAt
    }
}
