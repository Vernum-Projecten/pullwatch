import AppKit
import PullwatchCore
import SwiftUI

/// "Inloggen met GitHub" via de device flow: Pullwatch zet de code op het klembord en opent
/// github.com/login/device, de persoon plakt de code en keurt goed, en de rij wacht tot GitHub
/// het token geeft. Daarna een link om de app te installeren waar de repositories staan.
struct GitHubSignInRow: View {
    let model: AppModel
    let accountId: UUID
    /// Na inloggen: de login van wie er inlogde.
    let onSignedIn: (String) -> Void
    var onSignedOut: () -> Void = {}

    private enum Phase: Equatable {
        case signedOut
        case starting
        case waiting(DeviceCode)
        case signedIn(String?)
    }

    @State private var phase = Phase.signedOut
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        Group {
            switch phase {
            case .signedOut, .starting:
                HStack {
                    Button("Inloggen met GitHub") { start() }
                        .disabled(phase == .starting)
                        .accessibilityIdentifier("github.signIn")
                    if phase == .starting { ProgressView().controlSize(.small) }
                }
                Text("Je logt in op github.com; Pullwatch krijgt alleen leestoegang tot pull requests, tags en bestanden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .waiting(let code):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plak deze code op github.com en keur Pullwatch goed:")
                    HStack(spacing: 12) {
                        Text(verbatim: code.userCode)
                            .font(.system(.title2, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("github.userCode")
                        Button("Kopieer") { copy(code.userCode) }
                        Button("Open github.com") { NSWorkspace.shared.open(code.verificationURL) }
                    }
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Wachten op goedkeuring…").foregroundStyle(.secondary)
                        Spacer()
                        Button("Annuleren") {
                            task?.cancel()
                            phase = .signedOut
                        }
                    }
                }
            case .signedIn(let login):
                HStack {
                    Label {
                        if let login {
                            Text("Ingelogd als @\(login)")
                        } else {
                            Text("Ingelogd bij GitHub")
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Spacer()
                    Button("Afmelden") {
                        model.signOutOfGitHub(accountId)
                        phase = .signedOut
                        onSignedOut()
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Link("Installeer Pullwatch op een account of organisatie", destination: model.gitHubApp.installURL)
                    Text("Pullwatch ziet alleen repositories waar de app geïnstalleerd is. Bij een organisatie installeert een eigenaar hem, of keurt je verzoek goed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear {
            if case .signedOut = phase, model.hasGitHubAppTokens(accountId) { phase = .signedIn(nil) }
        }
        .onDisappear { task?.cancel() }
    }

    private func copy(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    private func start() {
        error = nil
        phase = .starting
        task = Task {
            do {
                let code = try await model.startGitHubSignIn()
                // Zoals `gh auth login`: de code staat al op het klembord en de browser gaat open.
                copy(code.userCode)
                NSWorkspace.shared.open(code.verificationURL)
                phase = .waiting(code)
                try await model.finishGitHubSignIn(code, accountId: accountId)
                let login = await model.gitHubLogin(accountId)
                phase = .signedIn(login)
                if let login { onSignedIn(login) }
            } catch is CancellationError {
                phase = .signedOut
            } catch let failure as GitHubSignInError {
                error = failure.userMessage
                phase = .signedOut
            } catch let failure as ProviderError {
                error = failure.userMessage
                phase = .signedOut
            } catch {
                self.error = error.localizedDescription
                phase = .signedOut
            }
        }
    }
}
