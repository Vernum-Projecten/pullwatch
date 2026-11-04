import Foundation
import PullwatchAzureDevOps
import PullwatchCore
import PullwatchGitHub
import PullwatchGitLab

/// Maakt bij een account de provider van zijn dienst, met de juiste tokenbron; de enige plek die
/// elke provider kent.
public enum ProviderFactory {
    /// `pat` overschrijft de Keychain (gebruikt bij "Test verbinding" vóór opslaan).
    public static func make(
        _ account: Account,
        pat: String? = nil,
        secrets: any SecretStore = SecretStores.shared,
        http: any HTTPClient = URLSessionHTTPClient(),
        runner: any ProcessRunner = SystemProcessRunner(),
        gitHubApp: GitHubAppConfig = .main
    ) -> any PRProvider {
        let tokens: any TokenSource
        switch account.authMethod {
        case .pat:
            if let pat {
                tokens = StaticTokenSource(token: pat)
            } else {
                tokens = KeychainPATSource(store: secrets, accountId: account.id)
            }
        case .cli:
            switch account.kind {
            case .azureDevOps: tokens = AzCLISource(runner: runner)
            case .gitHub:
                tokens = GhCLISource(
                    runner: runner, user: account.cliUser,
                    host: GitHubEndpoints(instanceURL: account.effectiveInstanceURL).cliHost
                )
            case .gitLab: tokens = GlabCLISource(runner: runner, host: account.effectiveInstanceURL?.host() ?? "gitlab.com")
            }
        case .gitHubApp:
            tokens = GitHubAppTokenSource(
                flow: GitHubDeviceFlow(config: gitHubApp, http: http),
                store: GitHubAppTokenStore(accountId: account.id, secrets: secrets)
            )
        }

        switch account.kind {
        case .azureDevOps:
            return AzureDevOpsProvider(
                accountId: account.id,
                organization: account.organization,
                tokenSource: tokens,
                authMethod: account.authMethod,
                http: http
            )
        case .gitHub:
            return GitHubProvider(
                accountId: account.id,
                owners: account.owners,
                extraRepos: account.extraRepos,
                instanceURL: account.effectiveInstanceURL,
                tokenSource: tokens,
                http: http
            )
        case .gitLab:
            return GitLabProvider(
                accountId: account.id,
                owners: account.owners,
                extraRepos: account.extraRepos,
                instanceURL: account.effectiveInstanceURL,
                tokenSource: tokens,
                http: http
            )
        }
    }
}
