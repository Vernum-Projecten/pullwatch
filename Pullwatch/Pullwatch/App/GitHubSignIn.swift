import AppKit
import Observation
import PullwatchCore
import PullwatchGitHub

private let log = Log(category: "github-sign-in")

/// Inloggen met GitHub voor één account, van de code tot de plekken waar de app geïnstalleerd is.
/// De views tekenen alleen deze staat; netwerk, klembord, browser en wachten gebeuren hier.
@Observable
final class GitHubSignIn {
    enum Phase: Equatable {
        case signedOut
        case requestingCode
        /// De code staat op het scherm (en op het klembord); wachten tot hij op github.com is goedgekeurd.
        case waitingForApproval(DeviceCode)
        case signedIn(login: String?)
    }

    /// Waar de GitHub App geïnstalleerd is, voor de keuze van de eigenaar.
    enum Installations: Equatable {
        case unknown
        case none
        case found([GitHubOwner])
    }

    let accountId: UUID
    private(set) var phase: Phase
    private(set) var installations = Installations.unknown
    /// Bezig met opnieuw kijken waar de app geïnstalleerd is (de knop "Opnieuw kijken").
    private(set) var checkingInstallations = false
    private(set) var codeCopied = false
    /// Iemand ging installeren: blijf kijken tot de installatie er is.
    private(set) var waitingForInstall = false
    private(set) var error: String?

    @ObservationIgnored private let accounts: AccountsModel
    @ObservationIgnored private var flow: Task<Void, Never>?
    @ObservationIgnored private var watch: Task<Void, Never>?

    init(accounts: AccountsModel, accountId: UUID) {
        self.accounts = accounts
        self.accountId = accountId
        phase = accounts.hasGitHubAppTokens(accountId) ? .signedIn(login: nil) : .signedOut
        if case .signedIn = phase {
            Task { await self.resume() }
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = phase { true } else { false }
    }

    var login: String? {
        if case .signedIn(let login) = phase { login } else { nil }
    }

    // MARK: Inloggen

    func start() {
        flow?.cancel()
        error = nil
        codeCopied = false
        phase = .requestingCode
        log.info("inloggen gestart voor account \(accountId)")
        flow = Task {
            do {
                let code = try await accounts.startGitHubSignIn()
                guard !Task.isCancelled else { return }
                log.info("code ontvangen, verloopt \(code.expiresAt.formatted(date: .omitted, time: .standard))")
                phase = .waitingForApproval(code)
                copyCode()
                try await accounts.finishGitHubSignIn(code, accountId: accountId)
                guard !Task.isCancelled else { return }
                log.notice("goedgekeurd op GitHub")
                await resume()
            } catch is CancellationError {
                log.info("inloggen geannuleerd")
            } catch {
                fail(error, "inloggen mislukt")
                phase = .signedOut
            }
        }
    }

    func cancel() {
        flow?.cancel()
        flow = nil
        phase = .signedOut
        log.info("inloggen geannuleerd")
    }

    func copyCode() {
        guard case .waitingForApproval(let code) = phase else { return }
        NSPasteboard.general.clearContents()
        codeCopied = NSPasteboard.general.setString(code.userCode, forType: .string)
        if codeCopied {
            log.debug("code op het klembord gezet")
        } else {
            log.warning("code kon niet op het klembord")
        }
    }

    /// Opent de pagina waar de code wordt ingevuld; de code gaat eerst (opnieuw) op het klembord.
    func openVerificationPage() {
        guard case .waitingForApproval(let code) = phase else { return }
        copyCode()
        open(code.verificationURL)
    }

    func signOut() {
        flow?.cancel()
        watch?.cancel()
        accounts.signOutOfGitHub(accountId)
        phase = .signedOut
        installations = .unknown
        waitingForInstall = false
        log.notice("afgemeld")
    }

    // MARK: Installaties

    /// Opent de installatiepagina van de app en blijft daarna kijken tot de installatie er is.
    func install() {
        log.info("installatiepagina geopend")
        #if DEBUG
        if FakeGitHub.isEnabled {
            FakeGitHub.shared.install()
            startWatching()
            return
        }
        #endif
        open(accounts.gitHubApp.installURL)
        startWatching()
    }

    /// Kijkt opnieuw waar de app geïnstalleerd is (bij terugkomen in de app, of met de knop).
    func refreshInstallations() async {
        guard isSignedIn else { return }
        checkingInstallations = true
        defer { checkingInstallations = false }
        do {
            let owners = try await accounts.gitHubInstallationOwners(accountId)
            installations = owners.isEmpty ? .none : .found(owners)
            log.info("installaties: \(owners.isEmpty ? "geen" : owners.map(\.login).joined(separator: ", "))")
            if !owners.isEmpty { error = nil }
        } catch {
            fail(error, "installaties ophalen mislukt")
        }
    }

    /// De plekken waar de app nu geïnstalleerd is.
    private var installedLogins: [String] {
        if case .found(let owners) = installations { owners.map(\.login) } else { [] }
    }

    private func resume() async {
        let login = await accounts.gitHubLogin(accountId)
        phase = .signedIn(login: login)
        log.info("ingelogd als \(login ?? "onbekend")")
        await refreshInstallations()
    }

    /// Om de paar seconden kijken, tot tien minuten lang: terugkomen in de app is niet altijd
    /// te zien (een ander venster, een tweede scherm). Klaar zodra er een plek bij is gekomen die
    /// er bij de start nog niet was, ook als de app al ergens anders geïnstalleerd was.
    private func startWatching() {
        waitingForInstall = true
        let known = Set(installedLogins)
        watch?.cancel()
        watch = Task {
            for _ in 0..<200 {
                try? await Task.sleep(for: .seconds(FakeGitHubTiming.installPoll))
                guard !Task.isCancelled else { return }
                await refreshInstallations()
                if !Set(installedLogins).isSubset(of: known) {
                    waitingForInstall = false
                    return
                }
            }
            waitingForInstall = false
            log.notice("gestopt met wachten op de installatie")
        }
    }

    private func open(_ url: URL) {
        #if DEBUG
        if FakeGitHub.isEnabled { return }
        #endif
        NSWorkspace.shared.open(url)
    }

    private func fail(_ error: any Error, _ context: String) {
        let message = switch error {
        case let error as GitHubSignInError: error.userMessage
        case let error as ProviderError: error.userMessage
        default: error.localizedDescription
        }
        self.error = message
        log.error("\(context): \(message)")
    }
}

/// Hoe snel gekeken wordt; korter met het nagespeelde GitHub, zodat UI-tests niet wachten.
enum FakeGitHubTiming {
    static var installPoll: Double {
        #if DEBUG
        if FakeGitHub.isEnabled { return 0.5 }
        #endif
        return 3
    }

    static var deviceSecond: Duration {
        #if DEBUG
        if FakeGitHub.isEnabled { return .milliseconds(200) }
        #endif
        return .seconds(1)
    }
}
