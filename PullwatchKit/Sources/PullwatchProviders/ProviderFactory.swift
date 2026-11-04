import Foundation
import PullwatchAzureDevOps
import PullwatchBitbucket
public import PullwatchCore
public import PullwatchGitHub
import PullwatchGitea
import PullwatchGitLab

/// Maakt bij een account de provider van zijn dienst, met de juiste tokenbron; de enige plek die
/// elke provider kent.
public enum ProviderFactory {
    /// `pat` overschrijft de Keychain (gebruikt bij "Test verbinding" vóór opslaan). `locator`
    /// vindt `gh` voor de packages van een GitHub App-account.
    public static func make(
        _ account: Account,
        pat: String? = nil,
        secrets: any SecretStore = SecretStores.shared,
        http: any HTTPClient = URLSessionHTTPClient(),
        runner: any ProcessRunner = SystemProcessRunner(),
        locator: CLILocator = CLILocator(),
        gitHubApp: GitHubAppConfig = .main
    ) -> any PRProvider {
        // Een eigen server zonder bruikbaar adres (Forgejo zonder server, een http-adres in de
        // config): geen provider die het token ergens heen stuurt.
        if let problem = account.serverProblem {
            return UnusableServerProvider(error: .unusableServer(service: account.productName, problem: problem))
        }
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
            case .bitbucket:
                // Bitbucket heeft geen officiële CLI die een token leesbaar bewaart: dan geen token.
                tokens = KeychainPATSource(store: secrets, accountId: account.id)
            // `tea` heeft geen commando dat een token geeft; een Gitea-account logt altijd met een
            // token in (de editor biedt de CLI niet aan). Een config met `cli` faalt dan duidelijk.
            case .gitea: tokens = KeychainPATSource(store: secrets, accountId: account.id)
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
            // GitHubs Packages-API weigert elk token van een GitHub App: zo'n account leest zijn
            // packages met het token van `gh` voor zijn host (het actieve `gh`-account), tenzij
            // dat uitstaat (`Account.packagesViaCLI`).
            let packagesTokens: (any TokenSource)? = account.authMethod == .gitHubApp && account.readsPackagesWithCLI
                ? GhCLISource(runner: runner, locator: locator, host: GitHubEndpoints(instanceURL: account.effectiveInstanceURL).cliHost)
                : nil
            return GitHubProvider(
                accountId: account.id,
                owners: account.owners,
                extraRepos: account.extraRepos,
                instanceURL: account.effectiveInstanceURL,
                authMethod: account.authMethod,
                tokenSource: tokens,
                packagesTokenSource: packagesTokens,
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
        case .bitbucket:
            return BitbucketProvider(
                accountId: account.id,
                workspaces: account.owners,
                email: account.email,
                extraRepos: account.extraRepos,
                tokenSource: tokens,
                http: http
            )
        case .gitea:
            // Zonder adres (Forgejo zonder server) heeft `serverProblem` hierboven al gestopt.
            guard let instanceURL = account.effectiveInstanceURL else {
                return UnusableServerProvider(error: .unusableServer(service: account.productName, problem: .missing))
            }
            return GiteaProvider(
                accountId: account.id,
                owners: account.owners,
                extraRepos: account.extraRepos,
                instanceURL: instanceURL,
                serviceName: account.productName,
                tokenSource: tokens,
                http: http
            )
        }
    }
}
