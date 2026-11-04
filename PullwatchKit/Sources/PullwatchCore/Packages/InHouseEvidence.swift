import Foundation

/// Of een install aantoonbaar het eigen package van een account is, en niet alleen een package
/// met dezelfde naam (#214). Een organisatie die een fork van een publiek package onder dezelfde
/// naam in haar eigen register zet (een gepatchte `Newtonsoft.Json`), maakt het publieke package
/// in een andere repo daarmee niet eigen: zonder bewijs blijft een install publiek, met de
/// nieuwste versie uit het publieke register en de CVE's van OSV.
///
/// Bewijs is één van:
/// - npm: een naam met scope die de eigenaar bezit (`@acme/ui` van eigenaar `acme`; bij GitLab
///   de groep bovenaan, bij Azure DevOps ook de organisatie).
/// - Go: het modulepad zelf, want dat noemt de host en de eigenaar.
/// - Het register van de install (`Dependency.registry`, uit de lockfile of het manifest) is het
///   eigen register van het account voor dat ecosysteem:
///   - GitHub: `npm.pkg.github.com`, `nuget.pkg.github.com`, `rubygems.pkg.github.com` en
///     `maven.pkg.github.com` met de eigenaar als eerste deel van het pad (`/download/@acme/…`,
///     `/acme/…`); bij GitHub Enterprise `npm.<host>` of `<host>/_registry/npm/`.
///   - GitLab: de host van het account met `/api/v4/…/packages/<npm|nuget|pypi|composer|rubygems|maven>`.
///   - Azure DevOps: `pkgs.dev.azure.com/<organisatie>/…/_packaging/…` of
///     `<organisatie>.pkgs.visualstudio.com/…/_packaging/…`.
///
/// Een register dat het package niet publiceert maakt niets eigen: `InHouseIndex` moet de naam
/// ook bij dat account vinden.
enum InHouseEvidence {
    /// Of `dependency` aantoonbaar het package van `owner` bij `account` is.
    static func proves(_ dependency: Dependency, owner: String, account: Account?) -> Bool {
        if dependency.ecosystem == "Go" { return true }
        if dependency.ecosystem == "npm", isOwnScope(name: dependency.name, owner: owner, account: account) { return true }
        guard let registry = dependency.registry, let account else { return false }
        return isOwnRegistry(registry, ecosystem: dependency.ecosystem, owner: owner, account: account)
    }

    /// `@acme/ui` met eigenaar `acme` (GitLab: `acme/web` telt als `acme`); bij Azure DevOps ook
    /// de organisatie, want een feed hangt aan een project.
    static func isOwnScope(name: String, owner: String, account: Account?) -> Bool {
        guard name.hasPrefix("@"), let slash = name.firstIndex(of: "/") else { return false }
        let scope = name[name.index(after: name.startIndex)..<slash].lowercased()
        guard !scope.isEmpty else { return false }
        var owners = [owner.split(separator: "/").first.map(String.init) ?? owner]
        if let account, account.kind == .azureDevOps { owners.append(account.organization) }
        return owners.contains { $0.lowercased() == scope }
    }

    /// Het deel van het pad dat per ecosysteem het register noemt.
    private static func word(_ ecosystem: String, kind: ProviderKind) -> String? {
        switch (kind, ecosystem) {
        case (_, "npm"): "npm"
        case (_, "NuGet"): "nuget"
        case (_, "RubyGems"): "rubygems"
        case (_, "Maven"): "maven"
        case (.gitLab, "PyPI"): "pypi"
        case (.gitLab, "Packagist"): "composer"
        default: nil
        }
    }

    /// Of `registry` (een URL zonder inloggegevens) het eigen register van `account` voor
    /// `ecosystem` is, en bij GitHub van `owner`.
    static func isOwnRegistry(_ registry: String, ecosystem: String, owner: String, account: Account) -> Bool {
        guard let url = URLComponents(string: registry), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        let segments = url.path.split(separator: "/").map { $0.lowercased() }
        let web = account.effectiveInstanceURL?.host()?.lowercased()
        switch account.kind {
        case .gitHub:
            guard let word = word(ecosystem, kind: .gitHub), let web else { return false }
            var rest = segments[...]
            if host == "\(word).pkg.github.com", web == "github.com" {
                // github.com: één registerhost per ecosysteem.
            } else if host == "\(word).\(web)", web != "github.com" {
                // GitHub Enterprise met subdomeinen, en GHE.com.
            } else if host == web, web != "github.com", segments.starts(with: ["_registry", word]) {
                rest = rest.dropFirst(2)
            } else {
                return false
            }
            if rest.first == "download" { rest = rest.dropFirst() }
            let name = owner.lowercased()
            return rest.first == name || rest.first == "@\(name)"
        case .gitLab:
            guard let word = word(ecosystem, kind: .gitLab), let web, host == web else { return false }
            guard segments.starts(with: ["api", "v4"]), let packages = segments.firstIndex(of: "packages"),
                  segments.index(after: packages) < segments.endIndex else { return false }
            return segments[segments.index(after: packages)] == word
        case .azureDevOps:
            let organization = account.organization.lowercased()
            guard !organization.isEmpty, segments.contains("_packaging") else { return false }
            return (host == "pkgs.dev.azure.com" && segments.first == organization) || host == "\(organization).pkgs.visualstudio.com"
        case .bitbucket, .gitea:
            // Geen packageregister dat Pullwatch leest.
            return false
        }
    }
}
