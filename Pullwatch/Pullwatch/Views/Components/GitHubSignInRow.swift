import PullwatchCore
import PullwatchGitHub
import SwiftUI

/// Inloggen met GitHub: een knop, dan de code (op het klembord) met "Open github.com", dan wie
/// er is ingelogd. Tekent alleen `GitHubSignIn`; alle werk gebeurt daar.
struct GitHubSignInRow: View {
    let signIn: GitHubSignIn

    var body: some View {
        switch signIn.phase {
        case .signedOut:
            LabeledContent {
                Button("Inloggen met GitHub") { signIn.start() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("github.signIn")
            } label: {
                Text("GitHub")
                Text("Je logt in op github.com; Pullwatch krijgt alleen leestoegang tot pull requests, tags en bestanden.")
            }
            errorRow
        case .requestingCode:
            LabeledContent("GitHub") {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("Code ophalen"))
            }
        case .waitingForApproval(let code):
            WaitingForApproval(code: code, signIn: signIn)
            errorRow
        case .signedIn(let login):
            LabeledContent {
                Button("Afmelden") { signIn.signOut() }
            } label: {
                Label {
                    if let login {
                        Text("Ingelogd als @\(login)")
                    } else {
                        Text("Ingelogd bij GitHub")
                    }
                } icon: {
                    if let login {
                        AccountAvatar(gitHubLogin: login, size: 20)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
            .accessibilityIdentifier("github.signedIn")
        }
    }

    @ViewBuilder private var errorRow: some View {
        if let error = signIn.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityIdentifier("github.error")
        }
    }
}

/// De code om op github.com in te vullen, groot en selecteerbaar, met de acties eronder en het
/// wachten op een eigen rij, zodat in elke taal alles past.
private struct WaitingForApproval: View {
    let code: DeviceCode
    let signIn: GitHubSignIn

    var body: some View {
        LabeledContent {
            Text(verbatim: code.userCode)
                .font(.system(.title, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
                .accessibilityIdentifier("github.userCode")
        } label: {
            Text("Je code")
            Text("Plak hem op github.com/login/device en keur Pullwatch goed. Pullwatch wacht hier tot dat gebeurd is.")
        }
        LabeledContent {
            Button("Annuleren") { signIn.cancel() }
        } label: {
            Label {
                Text("Wachten op goedkeuring…")
            } icon: {
                ProgressView().controlSize(.small)
            }
            .foregroundStyle(.secondary)
        }
        HStack {
            Button("Open github.com") { signIn.openVerificationPage() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("github.openVerification")
            Button {
                signIn.copyCode()
            } label: {
                if signIn.codeCopied {
                    Label("Gekopieerd", systemImage: "checkmark")
                } else {
                    Label("Kopieer code", systemImage: "doc.on.doc")
                }
            }
            .accessibilityIdentifier("github.copyCode")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Waar de app geïnstalleerd is, met per plek een schakelaar Volgen (eigen account eerst, dan de
/// organisaties); aan = de PR's en tags van die plek verschijnen in Pullwatch. Of eerst
/// installeren; na "installeren" blijft hij kijken tot die er is.
struct GitHubInstallationsRow: View {
    let signIn: GitHubSignIn
    @Binding var owners: [String]

    var body: some View {
        switch signIn.installations {
        case .unknown:
            LabeledContent("Repositories van") {
                ProgressView().controlSize(.small)
            }
        case .none:
            LabeledContent {
                Button("Pullwatch installeren") { signIn.install() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("github.install")
            } label: {
                Text("Installeer Pullwatch op GitHub")
                Text("Pullwatch ziet alleen repositories waar de app geïnstalleerd is: op je eigen account, of op een organisatie (daar installeert een eigenaar hem, of keurt je verzoek goed).")
            }
            LabeledContent {
                Button("Opnieuw kijken") { signIn.recheckInstallations() }
                    .disabled(signIn.checkingInstallations)
                    .accessibilityIdentifier("github.recheck")
            } label: {
                if signIn.waitingForInstall {
                    Label {
                        Text("Wachten op de installatie op github.com…")
                    } icon: {
                        ProgressView().controlSize(.small)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            errorRow
        case .found(let owners):
            ForEach(owners) { candidate in
                OwnerRow(owner: candidate, isFollowed: following(candidate.login))
            }
            Button {
                signIn.install()
            } label: {
                HStack {
                    Label("Op een ander account of organisatie installeren…", systemImage: "plus.circle")
                    Spacer()
                    if signIn.waitingForInstall {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(Text("Wachten op de installatie op github.com…"))
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityIdentifier("github.installElsewhere")
            errorRow
        }
    }

    private func following(_ login: String) -> Binding<Bool> {
        Binding(
            get: { owners.contains(login) },
            set: { follow in
                if follow, !owners.contains(login) { owners.append(login) }
                if !follow { owners.removeAll { $0 == login } }
            }
        )
    }

    @ViewBuilder private var errorRow: some View {
        if let error = signIn.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

/// Eén plek in de lijst: foto, naam en soort, met de schakelaar Volgen. VoiceOver leest
/// "Volg octocat, Je persoonlijke account, aan".
private struct OwnerRow: View {
    let owner: GitHubOwner
    @Binding var isFollowed: Bool

    var body: some View {
        Toggle(isOn: $isFollowed) {
            HStack(spacing: 10) {
                AccountAvatar(gitHubLogin: owner.login, size: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: owner.login)
                    Text(kind).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .accessibilityLabel(Text("Volg \(owner.login)"))
        .accessibilityValue(Text(kind))
        .accessibilityIdentifier("github.owner.\(owner.login)")
    }

    private var kind: LocalizedStringKey {
        if owner.isSignedInUser { "Je persoonlijke account" } else if owner.isOrganization { "Organisatie" } else { "Account" }
    }
}
