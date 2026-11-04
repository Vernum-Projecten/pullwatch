import SwiftUI

/// De menubalk van de vensters, in de volgorde van Apple's richtlijnen ("The menu bar"):
/// Pullwatch, Archief, Wijzig, Weergave, dan de menu's van de app zelf van algemeen naar
/// specifiek (Ga, Onderdeel, Repository), Venster en Help. Elk onderdeel staat er altijd in en
/// is uitgeschakeld als het nergens op van toepassing is.
struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        AppMenuCommands(model: model)
        FileCommands(model: model)
        EditCommands()
        ViewCommands(model: model)
        GoCommands(model: model)
        ItemCommands(model: model)
        RepositoryCommands(model: model)
        WindowCommands(router: model.router)
        HelpCommands(router: model.router)
    }
}
