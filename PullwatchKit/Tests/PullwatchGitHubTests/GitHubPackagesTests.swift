import Foundation
import Testing
@testable import PullwatchCore
@testable import PullwatchGitHub
import PullwatchTestSupport

/// De eigen packages in GitHub Packages: per soort een lijst per eigenaar, gekoppeld aan de
/// gevolgde repo's, met de recente versies, en een 401 of 403 als `.needsPermission`.
@Suite struct GitHubPackagesTests {
    /// Eén package zoals `/orgs/{org}/packages` het geeft (ingekort tot de velden die Pullwatch leest).
    func package(_ name: String, type: String, repo: String?, owner: String = "acme", visibility: String = "private") -> String {
        let repository = repo.map { #"{"id":1,"name":"x","full_name":"\#($0)","private":true}"# } ?? "null"
        return #"""
        {"id":15185987,"name":"\#(name)","package_type":"\#(type)","owner":{"login":"\#(owner)","type":"Organization"},
         "visibility":"\#(visibility)","url":"https://api.github.com/orgs/\#(owner)/packages/\#(type)/\#(name)",
         "created_at":"2026-09-18T10:46:06Z","updated_at":"2026-10-30T21:59:04Z","repository":\#(repository),
         "html_url":"https://github.com/orgs/\#(owner)/packages/\#(type)/package/\#(name)"}
        """#
    }

    /// Eén versie zoals `/…/packages/{type}/{name}/versions` hem geeft; bij een image is de naam
    /// een digest en staan de tags in de metadata.
    func version(_ name: String, type: String, tags: [String]? = nil, at date: String = "2026-10-30T21:59:01Z") -> String {
        let metadata = tags.map { tags in
            let list = tags.map { #""\#($0)""# }.joined(separator: ",")
            return #"{"package_type":"\#(type)","container":{"tags":[\#(list)]}}"#
        } ?? #"{"package_type":"\#(type)"}"#
        return #"""
        {"id":1476627939,"name":"\#(name)","created_at":"\#(date)","updated_at":"\#(date)",
         "html_url":"https://github.com/orgs/acme/packages/\#(type)/web/1476627939","metadata":\#(metadata)}
        """#
    }

    func organization(_ http: MockHTTPClient, _ owner: String = "acme") {
        http.on("users/\(owner)", body: #"{"login":"\#(owner)","type":"Organization"}"#)
    }

    var urls: (MockHTTPClient) -> [String] { { $0.requests.compactMap(\.url?.absoluteString) } }

    // MARK: - Soorten en eigenaren

    @Test(arguments: GitHubProvider.packageTypes)
    func `Lists the packages of an organization for each type`(type: PublishedPackageType) async throws {
        let http = MockHTTPClient()
        organization(http)
        let isImage = type == .container
        http.on("packages/\(type.rawValue)/web/versions", body: "[\(version(isImage ? "sha256:abc" : "1.2.0", type: type.rawValue, tags: isImage ? ["latest", "1.2.0"] : nil))]")
        http.on("orgs/acme/packages?package_type=\(type.rawValue)&", body: "[\(package("web", type: type.rawValue, repo: "acme/web"))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        let found = try #require(result.packages.first)
        #expect(result.packages.count == 1)
        #expect(found.type == type)
        #expect(found.name == "web")
        #expect(found.owner == "acme")
        #expect(found.repository == "acme/web")
        #expect(found.accountId == fixedAccountId)
        #expect(found.latestVersion == "1.2.0", "bij een image de tag naast latest, niet de digest")
        #expect(found.publishedAt == DateParsing.parse("2026-10-30T21:59:01Z"))
        #expect(found.visibility == .private)
        #expect(found.webURL?.absoluteString == "https://github.com/orgs/acme/packages/\(type.rawValue)/package/web")
        #expect(found.versions.first?.webURL?.absoluteString == "https://github.com/orgs/acme/packages/\(type.rawValue)/web/1476627939")
        #expect(found.id == "acme/\(type.rawValue)/web")
    }

    @Test func `Asks every type once per owner with the type as a parameter`() async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("orgs/acme/packages?package_type=", body: "[]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        #expect(result == .packages([]))
        let listings = urls(http).filter { $0.contains("/packages?") }
        #expect(listings == GitHubProvider.packageTypes.map {
            "https://api.github.com/orgs/acme/packages?package_type=\($0.rawValue)&per_page=100"
        })
    }

    @Test func `A user account lists through the users endpoint`() async throws {
        let http = MockHTTPClient()
        http.on("packages/npm/tool/versions", body: "[\(version("0.4.1", type: "npm"))]")
        http.on("users/ruben/packages?package_type=npm&", body: "[\(package("tool", type: "npm", repo: "ruben/tool", owner: "ruben"))]")
        http.on("users/ruben/packages?package_type=", body: "[]")
        // Na de packages: de eerste route die past wint, en "users/ruben" past ook op de lijsten.
        http.on("users/ruben", body: #"{"login":"ruben","type":"User"}"#)

        let result = try await makeProvider(http, owner: "ruben").publishedPackages(followedRepos: ["ruben/tool"])

        #expect(result.packages.map(\.latestVersion) == ["0.4.1"])
        #expect(result.packages.first?.owner == "ruben")
        #expect(urls(http).contains("https://api.github.com/users/ruben/packages/npm/tool/versions?per_page=30"))
        #expect(!urls(http).contains { $0.contains("/orgs/") })
    }

    @Test func `Follows the next link through every page`() async throws {
        let http = MockHTTPClient()
        organization(http)
        let next = "https://api.github.com/organizations/7/packages?package_type=npm&per_page=100&page=2"
        http.on("package_type=npm&per_page=100&page=2", body: "[\(package("two", type: "npm", repo: nil))]")
        http.on("orgs/acme/packages?package_type=npm&", headers: ["Link": #"<\#(next)>; rel="next", <\#(next)>; rel="last""#],
                body: "[\(package("one", type: "npm", repo: nil))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: [])

        #expect(result.packages.map(\.name) == ["one", "two"])
        #expect(urls(http).contains(next))
    }

    // MARK: - Koppelen aan gevolgde repo's

    @Test func `Keeps packages of followed repositories and drops the others`() async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("packages/npm/web/versions", body: "[\(version("2.3.0", type: "npm"))]")
        http.on("orgs/acme/packages?package_type=npm&", body: """
            [\(package("web", type: "npm", repo: "ACME/Web")), \(package("other", type: "npm", repo: "acme/other"))]
            """)
        http.on("orgs/acme/packages?package_type=", body: "[]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        #expect(result.packages.map(\.name) == ["web"])
        #expect(result.packages.first?.repository == "acme/web", "in de spelling van de gevolgde repo")
        #expect(!urls(http).contains { $0.contains("packages/npm/other/versions") }, "geen versies voor een repo die niet gevolgd wordt")
    }

    @Test func `A package without a repository stays without asking its versions`() async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("orgs/acme/packages?package_type=container&", body: "[\(package("mqtt-service", type: "container", repo: nil))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        let found = try #require(result.packages.first)
        #expect(found.repository == nil)
        #expect(found.versions.isEmpty)
        #expect(found.latestVersion == nil)
        #expect(found.publishedAt == DateParsing.parse("2026-10-30T21:59:04Z"), "dan de laatste wijziging van het package")
        #expect(!urls(http).contains { $0.contains("/versions") })
    }

    // MARK: - Versies

    @Test func `Keeps only the newest tagged versions`() async throws {
        let http = MockHTTPClient()
        organization(http)
        var versions = [version("sha256:untagged", type: "container", tags: [])]
        versions += (0..<15).map { version("sha256:\($0)", type: "container", tags: ["1.\(20 - $0).0"]) }
        http.on("packages/container/web/versions", body: "[\(versions.joined(separator: ","))]")
        http.on("orgs/acme/packages?package_type=container&", body: "[\(package("web", type: "container", repo: "acme/web"))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")

        let found = try #require(try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"]).packages.first)

        #expect(found.versions.count == PublishedPackage.recentVersionLimit)
        #expect(found.versions.first?.version == "1.20.0", "een image zonder tag telt niet")
        #expect(found.latestVersion == "1.20.0")
    }

    // MARK: - Versies van een image

    /// Een pagina van een image zoals ferroehr op ghcr.io: per push naar main een image met
    /// `sha-<commit>`, een cosign-handtekening `sha256-<digest>` en digests zonder tag.
    func commitPage(_ page: Int, count: Int = 100, main: Bool = false) -> [String] {
        (0..<count).map { index in
            let digest = "sha256:\(page)x\(index)"
            let date = "2026-11-0\(5 - page)T\(String(format: "%02d", 23 - index / 5)):00:00Z"
            switch index % 3 {
            case 0: return version(digest, type: "container", tags: ["sha256-\(String(repeating: "7e0f", count: 16))"], at: date)
            case 1: return version(digest, type: "container", tags: ["sha-\(String(format: "%07x", page * 1000 + index))"] + (main && index == 1 ? ["main"] : []), at: date)
            default: return version(digest, type: "container", tags: [], at: date)
            }
        }
    }

    /// `per_page=100`, de volgende pagina via de `Link`-header.
    func containerPages(_ http: MockHTTPClient, name packageName: String = "web", pages: [[String]]) {
        let name = packageName.replacingOccurrences(of: "/", with: "%2F")
        let base = "https://api.github.com/orgs/acme/packages/container/\(name)/versions"
        for (index, page) in pages.enumerated().reversed() {
            let number = index + 1
            let link = number < pages.count ? ["Link": #"<\#(base)?per_page=100&page=\#(number + 1)>; rel="next""#] : [:]
            let route = number == 1 ? "container/\(name)/versions?per_page=100" : "container/\(name)/versions?per_page=100&page=\(number)"
            http.on(route, headers: link, body: "[\(page.joined(separator: ","))]")
        }
        http.on("orgs/acme/packages?package_type=container&", body: "[\(package(packageName, type: "container", repo: "acme/web"))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")
    }

    @Test func `Finds a release older than the newest hundred commit and signature images`() async throws {
        let http = MockHTTPClient()
        organization(http)
        let release = version("sha256:release", type: "container", tags: ["5.6.0-rc10", "sha-7b4246a"], at: "2026-11-02T13:22:10Z")
        containerPages(http, pages: [commitPage(1, main: true), commitPage(2), [release] + commitPage(3, count: 40)])

        let found = try #require(try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"]).packages.first)

        #expect(found.latestVersion == "5.6.0-rc10")
        #expect(found.latestKind == .version)
        #expect(found.publishedAt == DateParsing.parse("2026-11-02T13:22:10Z"))
        #expect(found.versions.map(\.version) == ["5.6.0-rc10"], "nooit een digest, handtekening of commit")
        #expect(urls(http).filter { $0.contains("container/web/versions") }.count == 3)
        #expect(urls(http).contains("https://api.github.com/orgs/acme/packages/container/web/versions?per_page=100"))
    }

    @Test func `Stops paging once ten versions carry a version tag`() async throws {
        let http = MockHTTPClient()
        organization(http)
        // Zoals ferrobridge: per release drie handtekeningen en een digest zonder tag.
        let page = (0..<100).map { index in
            index % 5 == 0
                ? version("sha256:r\(index)", type: "container", tags: index == 0 ? ["0.0.\(40 - index / 5)", "latest", "0.0"] : ["0.0.\(40 - index / 5)"])
                : version("sha256:s\(index)", type: "container", tags: index % 5 == 4 ? [] : ["sha256-\(String(repeating: "4a69", count: 16))"])
        }
        containerPages(http, pages: [page, commitPage(2)])

        let found = try #require(try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"]).packages.first)

        #expect(found.latestVersion == "0.0.40")
        #expect(found.versions.count == PublishedPackage.recentVersionLimit)
        #expect(found.versions.first?.isLatestTag == true)
        #expect(found.latestTag == .onLatestVersion)
        #expect(urls(http).filter { $0.contains("container/web/versions") }.count == 1, "genoeg op de eerste pagina")
    }

    @Test func `Reads at most five pages`() async throws {
        let http = MockHTTPClient()
        organization(http)
        containerPages(http, pages: (1...7).map { commitPage($0, main: $0 == 1) })

        let found = try #require(try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"]).packages.first)

        #expect(urls(http).filter { $0.contains("container/web/versions") }.count == GitHubProvider.containerVersionPages)
        #expect(found.latestVersion == "main", "geen versietag: de nieuwste zwevende tag")
        #expect(found.latestKind == .floatingTag)
        #expect(found.versions.isEmpty)
    }

    @Test func `Commit tags with latest show latest as the newest tag`() async throws {
        let http = MockHTTPClient()
        organization(http)
        // Zoals ferropulse: elke push een volle commit als tag, latest op de nieuwste.
        containerPages(http, pages: [[
            version("sha256:a", type: "container", tags: ["f83df34cc968f5e0f916834508336c8eeb4c9e41", "latest"], at: "2026-10-24T13:27:33Z"),
            version("sha256:b", type: "container", tags: [], at: "2026-10-24T13:27:30Z"),
            version("sha256:c", type: "container", tags: ["2c62de91744b01c2c4e1b400b076260a0dca7777"], at: "2026-10-24T13:25:36Z"),
        ]])

        let found = try #require(try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"]).packages.first)

        #expect(found.latestVersion == "latest")
        #expect(found.latestKind == .floatingTag)
        #expect(found.releasedVersion == nil)
        #expect(found.publishedAt == DateParsing.parse("2026-10-24T13:27:33Z"))
    }

    @Test func `An image without any tag is untagged`() async throws {
        let http = MockHTTPClient()
        organization(http)
        containerPages(http, pages: [[
            #"{"id":1,"name":"sha256:f889","created_at":"2026-11-04T11:43:41Z","html_url":"https://github.com/x","metadata":{"package_type":"container","container":{}}}"#,
            version("sha256:b", type: "container", tags: [], at: "2026-11-03T11:00:00Z"),
        ]])

        let found = try #require(try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"]).packages.first)

        #expect(found.latestVersion == nil)
        #expect(found.latestKind == .untagged)
        #expect(found.versions.isEmpty)
    }

    @Test func `A Helm chart shows its chart version, not artifacthub.io`() async throws {
        let http = MockHTTPClient()
        organization(http)
        containerPages(http, name: "charts/web", pages: [[
            version("sha256:meta", type: "container", tags: ["artifacthub.io"], at: "2026-11-02T13:35:40Z"),
            version("sha256:sig", type: "container", tags: ["sha256-\(String(repeating: "9622", count: 16))"], at: "2026-11-02T13:35:29Z"),
            version("sha256:rc9", type: "container", tags: ["21.0.0-rc9"], at: "2026-11-02T13:35:14Z"),
            version("sha256:20", type: "container", tags: ["20.0.0"], at: "2026-10-27T22:12:23Z"),
        ]])

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])
        let found = try #require(result.packages.first)

        #expect(found.name == "charts/web")
        #expect(found.latestVersion == "20.0.0", "de stabiele release voor de hogere pre-release")
        #expect(found.newestPrerelease == "21.0.0-rc9")
        #expect(found.versions.map(\.version) == ["21.0.0-rc9", "20.0.0"])
    }

    @Test func `A failed later page keeps what the first pages said`() async throws {
        let http = MockHTTPClient()
        organization(http)
        let first = [version("sha256:a", type: "container", tags: ["1.2.0"])]
        http.on("container/web/versions?per_page=100&page=2", status: 502, body: "{}")
        http.on("container/web/versions?per_page=100", headers: ["Link": #"<https://api.github.com/orgs/acme/packages/container/web/versions?per_page=100&page=2>; rel="next""#],
                body: "[\(first.joined(separator: ","))]")
        http.on("orgs/acme/packages?package_type=container&", body: "[\(package("web", type: "container", repo: "acme/web"))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")

        let found = try #require(try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"]).packages.first)

        #expect(found.latestVersion == "1.2.0")
    }

    @Test func `A package name with a slash is one path component`() async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("packages/container/acme%2Fweb/versions", body: "[\(version("sha256:a", type: "container", tags: ["3.0.0"]))]")
        http.on("orgs/acme/packages?package_type=container&", body: "[\(package("acme/web", type: "container", repo: "acme/web"))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        #expect(result.packages.first?.latestVersion == "3.0.0")
    }

    @Test func `Versions that fail leave the package without versions`() async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("packages/npm/web/versions", status: 500, body: "{}")
        http.on("orgs/acme/packages?package_type=npm&", body: "[\(package("web", type: "npm", repo: "acme/web"))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        #expect(result.packages.map(\.name) == ["web"])
        #expect(result.packages.first?.versions == [])
    }

    // MARK: - Rechten

    @Test(arguments: [401, 403])
    func `A refused registry needs permission instead of failing`(status: Int) async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("orgs/acme/packages?package_type=", status: status, body: #"{"message":"Resource not accessible by integration"}"#)

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        #expect(result == .needsPermission(reason: GitHubPackagesReason.tokenMissesScope))
        #expect(urls(http).filter { $0.contains("/packages?") }.count == 1, "na de eerste weigering niets meer")
    }

    /// Zo ging het met een echt account (#204-onderzoek, 4 november): het eigen account gaf 403,
    /// de organisaties niet. Die weigering mag de packages van de organisatie niet tegenhouden.
    @Test func `A refused owner does not hide the packages of the other owners`() async throws {
        let http = MockHTTPClient()
        http.on("users/ruben/packages?package_type=", status: 403, body: #"{"message":"Resource not accessible by integration"}"#)
        http.on("users/ruben", body: #"{"login":"ruben","type":"User"}"#)
        http.on("packages/npm/web/versions", body: "[\(version("1.2.0", type: "npm"))]")
        http.on("orgs/acme/packages?package_type=npm&", body: "[\(package("web", type: "npm", repo: "acme/web"))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")
        organization(http)
        let provider = appProvider(http, owners: ["ruben", "acme"], packages: StaticTokenSource(token: "gho_cli"))

        let result = try await provider.publishedPackages(followedRepos: ["acme/web"])

        #expect(result.packages.map(\.name) == ["web"])
        #expect(result.packages.first?.owner == "acme")
    }

    @Test func `Refused versions need permission too`() async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("packages/npm/web/versions", status: 403, body: #"{"message":"Must have admin rights"}"#)
        http.on("orgs/acme/packages?package_type=npm&", body: "[\(package("web", type: "npm", repo: "acme/web"))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        #expect(result == .needsPermission(reason: GitHubPackagesReason.tokenMissesScope))
    }

    /// Een token of de GitHub CLI als manier van inloggen leest met zijn eigen token: dan is de
    /// scope read:packages wat er ontbreekt.
    @Test(arguments: [AuthMethod.cli, .pat])
    func `A token or the CLI as the way of signing in misses read packages`(authMethod: AuthMethod) async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("orgs/acme/packages?package_type=", status: 403, body: #"{"message":"Resource not accessible by integration"}"#)
        let provider = GitHubProvider(
            accountId: fixedAccountId, owners: ["acme"], authMethod: authMethod, tokenSource: StaticTokenSource(token: "ghtok"), http: http
        )

        let result = try await provider.publishedPackages(followedRepos: ["acme/web"])

        #expect(result == .needsPermission(reason: GitHubPackagesReason.tokenMissesScope))
        #expect(GitHubPackagesReason.tokenMissesScope.contains("read:packages"))
        #expect(http.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer ghtok" })
    }

    // MARK: - GitHub App via de GitHub CLI (#206)

    /// Een GitHub App-account: het eigen token "ghu_app", en voor de packages `packages`.
    func appProvider(
        _ http: MockHTTPClient, owners: [String] = ["acme"], instanceURL: URL? = nil, packages: (any TokenSource)?
    ) -> GitHubProvider {
        GitHubProvider(
            accountId: fixedAccountId, owners: owners, instanceURL: instanceURL, authMethod: .gitHubApp,
            tokenSource: StaticTokenSource(token: "ghu_app"), packagesTokenSource: packages, http: http
        )
    }

    /// `gh auth token` zoals een `gh` die is ingelogd het geeft.
    func loggedInGh(_ token: String = "gho_cli") -> MockProcessRunner {
        let runner = MockProcessRunner()
        runner.output = ProcessOutput(status: 0, stdout: "\(token)\n", stderr: "")
        return runner
    }

    @Test func `A GitHub App account reads its packages with the gh token and never with the app token`() async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("packages/npm/web/versions", body: "[\(version("1.2.0", type: "npm"))]")
        http.on("orgs/acme/packages?package_type=npm&", headers: ["X-OAuth-Scopes": "repo, read:org, read:packages"],
                body: "[\(package("web", type: "npm", repo: "acme/web"))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")
        let runner = loggedInGh()
        let provider = appProvider(http, packages: GhCLISource(runner: runner, locator: .homebrew, host: "github.com"))

        let result = try await provider.publishedPackages(followedRepos: ["acme/web"])

        #expect(result.packages.map(\.latestVersion) == ["1.2.0"])
        let registry = http.requests.filter { $0.url?.path().contains("/packages") == true }
        #expect(registry.count == GitHubProvider.packageTypes.count + 1, "elke soort en de versies van web")
        #expect(registry.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer gho_cli" })
        #expect(!registry.contains { $0.value(forHTTPHeaderField: "Authorization")?.contains("ghu_app") == true })
        #expect(runner.calls.map(\.1) == [["auth", "token"]], "één keer gh, daarna uit de cache")
    }

    @Test func `Turned off reads no packages and asks nothing`() async throws {
        let http = MockHTTPClient()
        organization(http)

        let result = try await appProvider(http, packages: nil).publishedPackages(followedRepos: ["acme/web"])

        #expect(result == .needsPermission(reason: GitHubPackagesReason.cliTurnedOff))
        #expect(http.requests.isEmpty)
    }

    @Test func `Without gh the reason says how to install it`() async throws {
        let http = MockHTTPClient()
        let runner = loggedInGh()
        let provider = appProvider(http, packages: GhCLISource(runner: runner, locator: .nothing, host: "github.com"))

        let result = try await provider.publishedPackages(followedRepos: ["acme/web"])

        #expect(result == .needsPermission(reason: GitHubPackagesReason.cliMissing(host: "github.com")))
        #expect(http.requests.isEmpty)
        #expect(runner.calls.isEmpty)
    }

    @Test func `A gh that is not logged in gives the login command`() async throws {
        let http = MockHTTPClient()
        let runner = MockProcessRunner()
        runner.output = ProcessOutput(status: 1, stdout: "", stderr: "no oauth token found for github.com")
        let provider = appProvider(http, packages: GhCLISource(runner: runner, locator: .homebrew, host: "github.com"))

        let result = try await provider.publishedPackages(followedRepos: ["acme/web"])

        #expect(result == .needsPermission(reason: GitHubPackagesReason.cliLoggedOut(host: "github.com")))
        #expect(http.requests.isEmpty)
    }

    /// GitHub weigert een `gh`-token zonder de scope met 403 en noemt de scopes in `X-OAuth-Scopes`.
    @Test(arguments: [["X-OAuth-Scopes": "gist, read:org, repo, workflow"], [:]])
    func `A gh token without read packages gives the refresh command`(headers: [String: String]) async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("orgs/acme/packages?package_type=", status: 403, headers: headers,
                body: #"{"message":"You need at least read:packages scope to list packages."}"#)
        let provider = appProvider(http, packages: GhCLISource(runner: loggedInGh(), locator: .homebrew, host: "github.com"))

        let result = try await provider.publishedPackages(followedRepos: ["acme/web"])

        #expect(result == .needsPermission(reason: GitHubPackagesReason.cliMissesScope(host: "github.com")))
    }

    /// Een ander `gh`-account dan wie er met de app inlogde: werkt als het de eigenaren mag zien, en
    /// anders zegt de reden dat, niet dat de scope ontbreekt.
    @Test func `Another gh user that may not see the owners says so`() async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("orgs/acme/packages?package_type=", status: 403, headers: ["X-OAuth-Scopes": "repo, read:packages"],
                body: #"{"message":"Forbidden"}"#)
        let provider = appProvider(http, packages: GhCLISource(runner: loggedInGh("gho_other"), locator: .homebrew, host: "github.com"))

        let result = try await provider.publishedPackages(followedRepos: ["acme/web"])

        #expect(result == .needsPermission(reason: GitHubPackagesReason.cliNoAccess(host: "github.com")))
    }

    @Test func `GitHub Enterprise asks gh for its own host and names it in the reason`() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"login":"acme","type":"Organization"}"#)
        http.on("packages?package_type=", status: 403, headers: ["X-OAuth-Scopes": "repo"], body: "{}")
        let runner = loggedInGh()
        let provider = appProvider(
            http, instanceURL: URL(string: "https://github.example.com"),
            packages: GhCLISource(runner: runner, locator: .homebrew, host: "github.example.com")
        )

        let result = try await provider.publishedPackages(followedRepos: ["acme/web"])

        let reason = GitHubPackagesReason.cliMissesScope(host: "github.example.com")
        #expect(result == .needsPermission(reason: reason))
        #expect(runner.calls.first?.1 == ["auth", "token", "--hostname", "github.example.com"])
        #expect(urls(http).contains("https://github.example.com/api/v3/orgs/acme/packages?package_type=npm&per_page=100"))
    }

    /// De opdrachten blijven in elke taal letterlijk staan, met de host.
    @Test func `The reasons carry the exact commands`() {
        #expect(GitHubPackagesReason.cliMissesScope(host: "github.com").contains("gh auth refresh -h github.com -s read:packages"))
        #expect(GitHubPackagesReason.cliMissesScope(host: "acme.ghe.com").contains("gh auth refresh -h acme.ghe.com -s read:packages"))
        #expect(GitHubPackagesReason.cliLoggedOut(host: "github.com").contains("gh auth login -h github.com -s read:packages"))
        #expect(GitHubPackagesReason.cliMissing(host: "github.com").contains("brew install gh"))
        #expect(GitHubPackagesReason.cliMissing(host: "github.com").contains("gh auth login -h github.com -s read:packages"))
        #expect(GitHubPackagesReason.cliNoAccess(host: "github.com").contains("gh auth login -h github.com"))
        #expect(!GitHubPackagesReason.cliTurnedOff.isEmpty)
    }

    @Test func `A rate limit is an error for the next check, not missing permission`() async {
        let http = MockHTTPClient()
        organization(http)
        http.on("orgs/acme/packages?package_type=", status: 403, headers: ["Retry-After": "60"], body: "{}")

        await #expect(throws: ProviderError.self) {
            try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])
        }
    }

    @Test(arguments: [404, 422])
    func `An account without packages is an empty list`(status: Int) async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("orgs/acme/packages?package_type=", status: status, body: #"{"message":"Not Found"}"#)

        let result = try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"])

        #expect(result == .packages([]))
    }

    // MARK: - GitHub Enterprise

    @Test func `GitHub Enterprise Server asks its own API`() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"login":"acme","type":"Organization"}"#)
        http.on("packages?package_type=", body: "[]")
        let provider = GitHubProvider(
            accountId: fixedAccountId, owner: "acme", instanceURL: URL(string: "https://github.example.com"),
            tokenSource: StaticTokenSource(token: "ghes-token"), http: http
        )

        _ = try await provider.publishedPackages(followedRepos: ["acme/web"])

        #expect(urls(http).contains("https://github.example.com/api/v3/orgs/acme/packages?package_type=npm&per_page=100"))
        #expect(!urls(http).contains { $0.contains("api.github.com") })
    }

    // MARK: - Volgende pagina's alleen op de API (#217)

    static let foreignLinks = [
        "https://evil.example.com/orgs/acme/packages?package_type=npm&page=2",
        "http://api.github.com/orgs/acme/packages?package_type=npm&page=2",
        "https://api.github.com:8443/orgs/acme/packages?package_type=npm&page=2",
    ]

    @Test(arguments: foreignLinks)
    func `A next link off the API stops listing packages and gets no token`(link: String) async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("page=2", body: "[\(package("two", type: "npm", repo: nil))]")
        http.on("orgs/acme/packages?package_type=npm&", headers: ["Link": #"<\#(link)>; rel="next""#],
                body: "[\(package("one", type: "npm", repo: nil))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")

        let result = try await makeProvider(http).publishedPackages(followedRepos: [])

        #expect(result.packages.map(\.name) == ["one"])
        #expect(!urls(http).contains { $0.contains("page=2") })
    }

    @Test(arguments: foreignLinks)
    func `A next link off the API stops the versions of an image`(link: String) async throws {
        let http = MockHTTPClient()
        organization(http)
        http.on("page=2", body: "[\(version("sha256:b", type: "container", tags: ["1.0.0"]))]")
        http.on("container/web/versions?per_page=100", headers: ["Link": #"<\#(link)>; rel="next""#],
                body: "[\(version("sha256:a", type: "container", tags: ["1.2.0"]))]")
        http.on("orgs/acme/packages?package_type=container&", body: "[\(package("web", type: "container", repo: "acme/web"))]")
        http.on("orgs/acme/packages?package_type=", body: "[]")

        let found = try #require(try await makeProvider(http).publishedPackages(followedRepos: ["acme/web"]).packages.first)

        #expect(found.latestVersion == "1.2.0")
        #expect(!urls(http).contains { $0.contains("page=2") })
    }

    @Test func `GitHub Enterprise Server follows next links on its own API host only`() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"login":"acme","type":"Organization"}"#)
        let next = "https://github.example.com/api/v3/organizations/7/packages?package_type=npm&per_page=100&page=2"
        http.on("page=2", headers: ["Link": #"<https://api.github.com/organizations/7/packages?package_type=npm&page=3>; rel="next""#],
                body: "[\(package("two", type: "npm", repo: nil))]")
        http.on("orgs/acme/packages?package_type=npm&", headers: ["Link": #"<\#(next)>; rel="next""#],
                body: "[\(package("one", type: "npm", repo: nil))]")
        http.on("packages?package_type=", body: "[]")
        let provider = GitHubProvider(
            accountId: fixedAccountId, owner: "acme", instanceURL: URL(string: "https://github.example.com"),
            tokenSource: StaticTokenSource(token: "ghes-token"), http: http
        )

        let result = try await provider.publishedPackages(followedRepos: [])

        #expect(result.packages.map(\.name) == ["one", "two"])
        #expect(urls(http).contains(next))
        #expect(!urls(http).contains { $0.contains("api.github.com") })
    }

    @Test func `GHE.com follows next links on its API host and not on the web host`() async throws {
        let http = MockHTTPClient()
        http.on("users/acme", body: #"{"login":"acme","type":"Organization"}"#)
        let next = "https://api.acme.ghe.com/organizations/7/packages?package_type=npm&per_page=100&page=2"
        http.on("page=2", headers: ["Link": #"<https://acme.ghe.com/organizations/7/packages?package_type=npm&page=3>; rel="next""#],
                body: "[\(package("two", type: "npm", repo: nil))]")
        http.on("orgs/acme/packages?package_type=npm&", headers: ["Link": #"<\#(next)>; rel="next""#],
                body: "[\(package("one", type: "npm", repo: nil))]")
        http.on("packages?package_type=", body: "[]")
        let provider = GitHubProvider(
            accountId: fixedAccountId, owner: "acme", instanceURL: URL(string: "https://acme.ghe.com"),
            tokenSource: StaticTokenSource(token: "ghe-token"), http: http
        )

        let result = try await provider.publishedPackages(followedRepos: [])

        #expect(result.packages.map(\.name) == ["one", "two"])
        #expect(urls(http).allSatisfy { URL(string: $0)?.host() == "api.acme.ghe.com" })
    }
}
