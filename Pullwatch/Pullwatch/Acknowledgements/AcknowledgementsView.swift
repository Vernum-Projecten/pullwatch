import SwiftUI

/// Het venster Erkenningen: links Pullwatch en de open-sourcesoftware in de app (naam, versie,
/// licentie), rechts de volledige licentietekst. Geopend vanuit het Over-venster en het menu Help.
struct AcknowledgementsView: View {
    @Environment(AcknowledgementsModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Section {
                    ForEach(model.app) { AcknowledgementRow(component: $0) }
                }
                Section("Open-sourcesoftware") {
                    ForEach(model.components) { AcknowledgementRow(component: $0) }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            AcknowledgementsDetail(component: model.selected, texts: model.selected.flatMap { model.texts[$0.id] } ?? [],
                                   isMissing: model.isMissing)
            // Breed genoeg voor 80 tekens vaste breedte: de licenties zijn zo opgemaakt.
            .navigationSplitViewColumnWidth(min: 660, ideal: 680)
        }
        .frame(minHeight: 420)
        .task { model.load() }
        #if DEBUG
        .onAppear { SnapshotCamera.shoot("acknowledgements", windowId: WindowID.acknowledgements.rawValue) }
        #endif
    }
}
