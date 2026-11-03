import PullwatchCore
import SwiftUI

/// "Volg een repository": één veld voor eigenaar/repo (of project/repo) of een geplakte link,
/// gecontroleerd met één verzoek voordat de repo bij het account komt. Vanuit het hoofdvenster
/// kies je eerst het account; vanuit de instellingen van een account is dat al gegeven.
struct WatchRepositorySheet: View {
    let model: AppModel
    /// De accounts om uit te kiezen; bij één is er niets te kiezen.
    let accounts: [Account]
    /// Een nieuw token dat nog niet bewaard is (account-editor).
    var pat: String?
    let onAdd: (UUID, RepositoryCheck) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var accountId: UUID?
    @State private var input = ""
    @State private var error: String?
    @State private var checkTask: Task<Void, Never>?

    private var account: Account? {
        accounts.first { $0.id == accountId } ?? accounts.first
    }

    private var canAdd: Bool {
        account != nil && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && checkTask == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if accounts.count > 1 {
                        Picker("Account", selection: $accountId) {
                            ForEach(accounts) { account in
                                Text(verbatim: account.displayName).tag(UUID?.some(account.id))
                            }
                        }
                    }
                    TextField("Repository", text: $input, prompt: Text(verbatim: placeholder))
                        .autocorrectionDisabled()
                        .onSubmit(add)
                        .accessibilityIdentifier("watchRepository.input")
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Volg een repository")
                } footer: {
                    footer
                }
            }
            .formStyle(.grouped)

            HStack {
                if checkTask != nil {
                    ProgressView().controlSize(.small)
                    Text("Controleren…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Annuleren") {
                    checkTask?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Toevoegen", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
            .padding()
        }
        .frame(width: 460)
        .onAppear {
            if accountId == nil { accountId = accounts.first { $0.kind == .gitHub }?.id ?? accounts.first?.id }
            #if DEBUG
            SnapshotCamera.shoot("watch-repository", sheet: true)
            #endif
        }
        .onChange(of: input) { error = nil }
        .onChange(of: accountId) { error = nil }
        .onDisappear { checkTask?.cancel() }
    }

    private var placeholder: String {
        account?.kind == .azureDevOps ? "project/repo" : "openEHR/specifications-AM"
    }

    @ViewBuilder private var footer: some View {
        if account?.kind == .azureDevOps {
            Text("Typ project/repo, of plak de link van dev.azure.com. De repository moet in de organisatie \(account?.organization ?? "") staan.", comment: "Azure DevOps-organisatie")
        } else {
            Text("Typ eigenaar/repo, of plak de link van github.com. Ook een openbare repository van een andere organisatie kan; Pullwatch leest die zo nodig zonder inloggen.")
        }
    }

    private func add() {
        guard canAdd, let account else { return }
        error = nil
        let text = input
        checkTask = Task {
            let result = await model.checkRepository(text, for: account, pat: pat)
            checkTask = nil
            if Task.isCancelled { return }
            switch result {
            case .success(let check):
                onAdd(account.id, check)
                dismiss()
            case .failure(let failure):
                error = failure.message
                #if DEBUG
                SnapshotCamera.shoot("watch-repository-error", sheet: true)
                #endif
            }
        }
    }
}
