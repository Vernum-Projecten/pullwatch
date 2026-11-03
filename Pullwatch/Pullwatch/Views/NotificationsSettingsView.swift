import PullwatchCore
import SwiftUI

/// Instellingen > Meldingen: per soort aan of uit met een voorbeeld van de melding, stille uren
/// en de badges. Welke repo's melden staat bij de repo zelf (de bel, of Repo dempen op een melding).
struct NotificationsSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(NotificationsModel.self) private var notifications

    private var samples: NotificationSamples { NotificationSamples(builder: NotificationContentBuilder()) }

    var body: some View {
        Form {
            if !notifications.notificationsAllowed && !Notifier.isSuppressed {
                Section {
                    LabeledContent {
                        Button("Systeeminstellingen openen") { Notifier.openSystemSettings() }
                    } label: {
                        Label("Meldingen staan uit in Systeeminstellingen", systemImage: "bell.slash")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                kindToggle(.pullRequest, "Nieuwe pull requests", isOn: Bindable(app).notificationSettings.pullRequests)
                kindToggle(.merged, "Gemergede pull requests", isOn: Bindable(app).notificationSettings.merged)
                kindToggle(.checksFailed, "Mislukte checks van je eigen pull requests", isOn: Bindable(app).notificationSettings.checksFailed)
                    .help("Een melding als de checks (CI) van een open pull request van jou mislukken, ook als je eigen PR's verborgen zijn")
                kindToggle(.release, "Nieuwe releases", isOn: Bindable(app).notificationSettings.releases)
                kindToggle(.tag, "Nieuwe tags zonder release", isOn: Bindable(app).notificationSettings.tags)
            } header: {
                Text("Pull requests en tags")
            } footer: {
                Text("Per repo zet je meldingen uit met de bel bij de repo, of met Repo dempen op een melding. Meer dan 20 tegelijk worden één melding per repo.")
            }

            Section {
                kindToggle(.vulnerability, "Nieuwe kwetsbaarheden", isOn: Bindable(app).notificationSettings.vulnerabilities)
                kindToggle(.securityAlert, "Nieuwe kritieke of hoge beveiligingsmeldingen", isOn: Bindable(app).notificationSettings.securityAlerts)
                    .help("Code scanning op GitHub en Advanced Security op Azure DevOps, per repo")
                kindToggle(.packageUpdate, "Nieuwe versies", isOn: Bindable(app).notificationSettings.packageUpdates)
                Toggle("Alleen voor updates die nu kunnen", isOn: Bindable(app).notificationSettings.onlyUpdatesYouCanTake)
                    .disabled(!app.notificationSettings.packageUpdates)
                    .help("Alleen een melding als een repo de nieuwe versie binnen zijn bereik kan nemen, zonder manifest aan te passen of eerst iets anders bij te werken")
            } header: {
                Text("Afhankelijkheden en kwetsbaarheden")
            } footer: {
                if app.checksVersionsDaily {
                    Text("Na de dagelijkse check van je gevolgde repo's.")
                } else {
                    Text("De dagelijkse check staat uit onder Algemeen, dus deze meldingen komen nu niet.")
                }
            }
            .disabled(!app.checksVersionsDaily)

            Section {
                Toggle("Stille uren", isOn: Bindable(app).notificationSettings.quietHours.isOn)
                    .accessibilityIdentifier("settings.notifications.quietHours")
                DatePicker("Van", selection: time(\.start), displayedComponents: .hourAndMinute)
                    .disabled(!app.notificationSettings.quietHours.isOn)
                DatePicker("Tot", selection: time(\.end), displayedComponents: .hourAndMinute)
                    .disabled(!app.notificationSettings.quietHours.isOn)
            } header: {
                Text("Stille uren")
            } footer: {
                Text("In de stille uren komen meldingen zonder geluid binnen, en alleen in het Berichtencentrum. Focus en Niet storen stel je in bij Systeeminstellingen.")
            }

            Section {
                Toggle("Aantal ongelezen op het Dock-icoon", isOn: Bindable(app).notificationSettings.dockBadge)
                    .help("Pullwatch staat alleen in het Dock zolang er een venster open is")
                Toggle("Stip in de menubalk bij ongelezen", isOn: Bindable(app).notificationSettings.menuBarDot)
            } header: {
                Text("Ongelezen")
            }

            Section {
                LabeledContent {
                    Button("Systeeminstellingen openen") { Notifier.openSystemSettings() }
                } label: {
                    Text("Stijl, geluid en voorbeelden")
                    Text("Banners of meldingen, en wat het toegangsscherm toont, regelt macOS.")
                }
            }
        }
        .formStyle(.grouped)
        .task { _ = await notifications.notificationStatus() }
    }

    /// De schakelaar van een soort met daaronder hoe de melding eruitziet.
    private func kindToggle(_ kind: NotificationKind, _ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: isOn)
                .accessibilityIdentifier("settings.notifications.\(kind.rawValue)")
            if let content = samples.content(for: kind) {
                NotificationPreview(content: content)
                    .opacity(isOn.wrappedValue ? 1 : 0.45)
            }
        }
    }

    /// Minuten na middernacht als tijd van vandaag, voor de `DatePicker`.
    private func time(_ field: WritableKeyPath<QuietHours, Int>) -> Binding<Date> {
        Binding {
            let minutes = app.notificationSettings.quietHours[keyPath: field]
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            app.notificationSettings.quietHours[keyPath: field] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}

/// Een melding zoals macOS hem ongeveer toont: het icoon van Pullwatch, titel, ondertitel en
/// tekst, en rechts het plaatje. Alleen een voorbeeld; de echte tekent macOS.
struct NotificationPreview: View {
    let content: NotificationContent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: content.title).font(.callout.weight(.semibold))
                if !content.subtitle.isEmpty {
                    Text(verbatim: content.subtitle).font(.callout)
                }
                Text(verbatim: content.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let glyph = NotificationGlyph(kind: content.kind) {
                glyph.view
                    .frame(width: 32, height: 32)
                    .scaleEffect(0.5)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
