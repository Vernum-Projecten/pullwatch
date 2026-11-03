import Foundation
import PullwatchCore

/// Ververst de tokens van een GitHub App-account, één keer tegelijk per account.
///
/// GitHub geeft bij elke refresh een nieuwe refresh token en laat de oude meteen vervallen. Twee
/// polls die tegelijk met dezelfde refresh token verversen, laten de tweede dus mislukken; daarom
/// wacht een tweede vraag op de refresh die al loopt. Elke provider maakt zijn eigen
/// `GitHubAppTokenSource`, dus de afspraak geldt voor het hele proces (`shared`), per sleutel van de
/// token store. Verversen en bewaren zijn één geheel dat het afbreken van de vrager niet onderbreekt:
/// anders is het nieuwe paar weg terwijl GitHub het oude al heeft laten vervallen.
actor GitHubAppTokenRefresher {
    static let shared = GitHubAppTokenRefresher()

    /// Per token store de vragers die wachten op de refresh die nu loopt; geen sleutel: er loopt er geen.
    private var waiting: [String: [CheckedContinuation<GitHubAppTokens, any Error>]] = [:]

    /// Tokens die nog minstens twee minuten gelden; ververst en bewaart ze zo nodig eerst.
    func validTokens(
        store: GitHubAppTokenStore,
        flow: GitHubDeviceFlow,
        now: @Sendable () -> Date
    ) async throws -> GitHubAppTokens {
        // Pas hier laden: wie na een refresh komt, krijgt meteen het nieuwe paar.
        guard let tokens = store.load() else { throw ProviderError.unauthorized }
        if tokens.accessExpires > now().addingTimeInterval(120) { return tokens }
        if waiting[store.key] != nil {
            return try await withCheckedThrowingContinuation { waiting[store.key]?.append($0) }
        }
        waiting[store.key] = []
        let result: Result<GitHubAppTokens, any Error>
        do {
            result = .success(try await refreshUninterrupted(tokens, store: store, flow: flow))
        } catch {
            result = .failure(error)
        }
        for waiter in waiting.removeValue(forKey: store.key) ?? [] {
            waiter.resume(with: result)
        }
        return try result.get()
    }

    /// Zet het token op verlopen, zodat de volgende vraag ververst. Loopt er al een refresh, dan komt
    /// er toch een nieuw paar; het oude terugschrijven zou dat overschrijven.
    func invalidate(store: GitHubAppTokenStore) {
        guard waiting[store.key] == nil, var tokens = store.load() else { return }
        tokens.accessExpires = .distantPast
        try? store.save(tokens)
    }

    // MARK: - Verversen

    /// Verversen en bewaren zonder dat het afbreken van de vrager ertussen komt.
    private func refreshUninterrupted(
        _ tokens: GitHubAppTokens,
        store: GitHubAppTokenStore,
        flow: GitHubDeviceFlow
    ) async throws -> GitHubAppTokens {
        if #available(macOS 27, *) {
            return try await withTaskCancellationShield {
                try await refreshAndSave(tokens, store: store, flow: flow)
            }
        }
        // Vóór macOS 27: een losse taak, die het afbreken van de vrager niet bereikt; de vrager
        // wacht op de uitkomst.
        return try await Task {
            try await self.refreshAndSave(tokens, store: store, flow: flow)
        }.value
    }

    private func refreshAndSave(
        _ tokens: GitHubAppTokens,
        store: GitHubAppTokenStore,
        flow: GitHubDeviceFlow
    ) async throws -> GitHubAppTokens {
        let fresh = try await flow.refresh(tokens)
        try store.save(fresh)
        return fresh
    }
}
