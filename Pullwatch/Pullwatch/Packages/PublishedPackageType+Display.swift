import PullwatchCore
import SimpleIcons
import SwiftUI

// Hoe het onderdeel Packages een soort package toont: een SF Symbol en een naam. Waarden, geen
// UI-state: ook buiten de main actor bruikbaar (sorteren, tests).
nonisolated extension PublishedPackageType {
    /// Eén vast symbool per soort, zodat de soort zonder lezen te herkennen is: een doos voor npm,
    /// lagen voor een image, een kopje voor Maven (Java), een diamant voor RubyGems, een stuurwiel
    /// voor Helm; een letter waar geen beeld voor is. Een soort die Pullwatch niet kent: een archief.
    var symbol: String {
        switch self {
        case .npm: "shippingbox"
        case .container, .docker: "square.stack.3d.up"
        case .nuGet: "n.square"
        case .maven: "cup.and.saucer"
        case .rubyGems: "diamond"
        case .pyPI: "p.square"
        case .helm: "steeringwheel"
        case .composer: "music.note"
        case .conan: "c.square"
        case .golang: "g.square"
        case .terraformModule: "t.square"
        case .cargo: "gearshape.2"
        case .generic: "doc.zipper"
        default: "archivebox"
        }
    }

    /// Het logo van het ecosysteem uit Simple Icons, voor elke soort waar het pakket een logo voor
    /// heeft (keuze van de eigenaar, net als bij de logo's van Gitea en Bitbucket); nil houdt het SF
    /// Symbol (`symbol`): algemeen, universeel en een soort die Pullwatch niet kent. Een
    /// container-image (OCI, zoals ghcr.io) krijgt het logo van het Open Container Initiative, het
    /// oude Docker-register dat van Docker, een crate dat van Rust. De licentie per logo staat in
    /// NOTICE. Alleen de iconen die hier staan komen in de app; nooit `SimpleIcon.allCases`, dat
    /// neemt elk icoon mee.
    var simpleIcon: SimpleIcon? {
        switch self {
        case .npm: .npm()
        case .container: .opencontainersinitiative()
        case .docker: .docker()
        case .maven: .apachemaven()
        case .golang: .go()
        case .terraformModule: .terraform()
        case .cargo: .rust()
        case .nuGet: .nuget()
        case .rubyGems: .rubygems()
        case .pyPI: .pypi()
        case .helm: .helm()
        case .composer: .composer()
        case .conan: .conan()
        default: nil
        }
    }

    /// De naam van de soort. De namen van registers en ecosystemen zijn eigennamen; alleen
    /// container-image, algemeen en universeel worden vertaald. nil voor een soort die Pullwatch
    /// niet kent; die toont zijn eigen naam (`rawValue`).
    var title: LocalizedStringResource? {
        switch self {
        case .npm: "npm"
        case .container: "Container-image"
        case .docker: "Docker"
        case .nuGet: "NuGet"
        case .maven: "Maven"
        case .rubyGems: "RubyGems"
        case .pyPI: "PyPI"
        case .helm: "Helm"
        case .composer: "Composer"
        case .conan: "Conan"
        case .golang: "Go"
        case .terraformModule: "Terraform"
        case .cargo: "Cargo"
        case .generic: "Algemeen package"
        case .universal: "Universal Package"
        default: nil
        }
    }

    /// Elke soort die de diensten noemen, voor de test van de symbolen.
    static let known: [PublishedPackageType] = [
        .npm, .container, .docker, .nuGet, .maven, .rubyGems, .pyPI, .helm, .composer, .conan, .golang, .terraformModule,
        .cargo, .generic, .universal,
    ]
}

extension PublishedPackageType {
    /// De naam als tekst, ook van een soort die Pullwatch niet kent.
    var text: Text {
        title.map { Text($0) } ?? Text(verbatim: rawValue)
    }
}
