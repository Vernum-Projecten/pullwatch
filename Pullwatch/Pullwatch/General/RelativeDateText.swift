import Foundation
import SwiftUI

/// Een datum als "5 minuten geleden" of "gisteren" die zelf bijblijft (#238). `Text(date, format:
/// .relative(presentation: .named))` maakt de tekst één keer; een cel van een `Table` tekent pas
/// opnieuw als de rij verandert of de muis erover gaat, en bleef dus op "2 minuten geleden" staan.
/// Hier rekent het systeem de tekst opnieuw uit tegen de klok (`TimeDataSource.currentDate`): elke
/// seconde zolang het om seconden gaat, elke minuut daarna, zonder timer in een model. Leest geen
/// model uit de environment, want hij staat in cellen van tabellen.
struct RelativeDateText: View {
    let date: Date

    var body: some View {
        Text(.currentDate, format: Self.style(for: date))
    }

    /// De stijl voor `date`. Hij geeft hetzelfde als `.relative(presentation: .named)` (met
    /// "gisteren"), maar tegen de tijd die hij krijgt in plaats van tegen nu. Zo past hij ook in een
    /// zin: `Text("Gepubliceerd \(.currentDate, format: RelativeDateText.style(for: date))")`.
    nonisolated static func style(for date: Date) -> Date.AnchoredRelativeFormatStyle {
        Date.AnchoredRelativeFormatStyle(anchor: date, presentation: .named)
    }

    /// De tekst voor `date` zoals hij er op het moment `now` staat.
    nonisolated static func text(for date: Date, at now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        style(for: date).locale(locale).format(now)
    }
}
