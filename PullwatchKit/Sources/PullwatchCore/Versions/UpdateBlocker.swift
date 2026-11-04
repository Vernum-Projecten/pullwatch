import Foundation

/// Waarom een nieuwere versie (nog) niet kan, en wat eerst moet.
public enum UpdateBlocker: Codable, Hashable, Sendable {
    /// Een ander package houdt hem tegen: de ouder van een transitieve install met zijn bereik,
    /// of een package dat dit package als peer met een bereik vraagt. `minimumParentVersion` is de
    /// laagste versie van dat package die de nieuwe versie toelaat; nil als die er niet is of
    /// (nog) niet bekend is.
    case package(parent: String, parentRange: String, minimumParentVersion: String?)
    /// De nieuwe versie vraagt een peer (`name`) in `needs`, en de workspace heeft `installed`.
    case peer(name: String, needs: String, installed: String)
    /// De nieuwe versie vraagt een runtime (`nodejs`, `php`, `python`, `rust`, `dotnet`, `ruby`,
    /// `go`) in `needs`, en de repo gebruikt `installed`.
    case runtime(runtime: String, needs: String, installed: String)
}

extension VersionReport {
    /// De context voor de blokkades van `repo`, met de metadata uit dit rapport.
    public func updateContext(for repo: RepoVersions) -> UpdateContext {
        UpdateContext(repo: repo, metadata: packageMetadata)
    }

    /// Wat de blokkades van elke install en elke kwetsbaarheid nog nodig hebben.
    func updateNeeds() -> UpdateNeeds {
        var needs = UpdateNeeds()
        let index = RegistryIndex(packageMetadata)
        for repo in repos where repo.error == nil {
            let context = UpdateContext(repo: repo, index: index)
            for package in repo.packages + repo.otherPackages {
                guard let latest = latestPackages[package.key]?.version else { continue }
                for install in package.installs {
                    _ = PackageUpdate(ecosystem: package.ecosystem, name: package.name, install: install, latest: latest, context: context, needs: &needs)
                }
            }
            for vulnerability in repo.vulnerabilities {
                _ = vulnerability.fix(in: context, needs: &needs)
            }
        }
        return needs
    }
}
