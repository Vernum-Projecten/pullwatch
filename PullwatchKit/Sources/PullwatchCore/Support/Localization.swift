package import Foundation

extension Bundle {
    /// De teksten van PullwatchCore in de taal die de app gekozen heeft. Zonder dit kiest
    /// de package-bundle zelf, en valt bij een niet-ondersteunde taal terug op Nederlands
    /// terwijl de app Engels toont.
    static let localizedCore: Bundle = core(for: Bundle.main.preferredLocalizations.first)

    static func core(for language: String?) -> Bundle {
        localized(#bundle, for: language)
    }

    /// De `.lproj` van `language` in de bundle van een module van dit package, of die bundle zelf.
    /// Elke module met een String Catalog maakt hiermee zijn eigen `localized…`-bundle.
    package static func localized(_ bundle: Bundle, for language: String?) -> Bundle {
        language.flatMap { bundle.path(forResource: $0, ofType: "lproj") }.flatMap(Bundle.init(path:)) ?? bundle
    }
}
