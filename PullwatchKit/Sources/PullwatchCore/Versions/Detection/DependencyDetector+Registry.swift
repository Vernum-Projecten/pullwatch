import Foundation

extension DependencyDetector {
    // MARK: - Register van een install

    /// De publieke standaardregisters: een install daarvandaan bewijst niets over een eigen
    /// register, dus die bewaart de check niet (een grote lockfile zou er anders duizend keer
    /// dezelfde URL in versions.json zetten).
    static let publicRegistryHosts: Set<String> = [
        "registry.npmjs.org", "registry.yarnpkg.com",
        "index.crates.io", "static.crates.io",
        "rubygems.org", "index.rubygems.org",
        "pypi.org", "pypi.python.org", "files.pythonhosted.org",
        "packagist.org", "repo.packagist.org",
        "api.nuget.org", "www.nuget.org",
    ]

    /// Het register zoals een lockfile of manifest het noemt ("https://npm.pkg.github.com/…",
    /// Cargo's "registry+https://…" of "sparse+https://…"), als https-URL zonder inloggegevens,
    /// query en fragment: een pip-index heeft vaak een token in de URL, en dat komt nooit in het
    /// rapport. nil voor iets dat geen http(s)-URL is, voor het publieke standaardregister en voor
    /// de index van crates.io op GitHub.
    static func registry(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        for prefix in ["registry+", "sparse+"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        guard var components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        guard !publicRegistryHosts.contains(host),
              !(host == "github.com" && components.path.lowercased().hasPrefix("/rust-lang/crates.io-index")) else { return nil }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.host = host
        components.scheme = scheme
        return components.string
    }

    /// De index van een requirements-bestand: `--index-url` of `-i` als dat geen publiek register
    /// is, anders de eerste `--extra-index-url` die dat niet is. Een eigen index naast PyPI is geen bewijs
    /// dat juist dit package daarvandaan komt, maar wel dat het bestand een eigen register noemt;
    /// `InHouseEvidence` vraagt daarnaast dat dat register het package publiceert.
    static func requirementsIndex(_ content: String) -> String? {
        var index: String?
        var extra: String?
        for raw in content.split(whereSeparator: \.isNewline) {
            let line = (raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
                .trimmingCharacters(in: .whitespaces)
            guard let m = line.wholeMatch(of: /(--index-url|-i|--extra-index-url)(?:\s*=\s*|\s+)(\S+)/) else { continue }
            let value = String(m.output.2)
            if m.output.1 == "--extra-index-url" {
                if extra == nil { extra = registry(value) }
            } else if index == nil {
                index = value
            }
        }
        return registry(index) ?? extra
    }
}
