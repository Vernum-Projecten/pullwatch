import Foundation
import Testing
@testable import PullwatchCore

/// De ene regel voor een link naar de volgende pagina: alleen https op de host en poort van de
/// API van het account, nooit `current` zelf.
@Suite struct PageLinkTests {
    static let api = URL(string: "https://api.github.com")!
    static let current = URL(string: "https://api.github.com/orgs/acme/packages?package_type=npm")!

    @Test(arguments: [
        "https://api.github.com/organizations/7/packages?page=2",
        "https://API.github.com/organizations/7/packages?page=2",
        "https://api.github.com/other/path",
    ])
    func `A link on the API's own host is followed`(link: String) {
        let next = URL(string: link)!
        #expect(PageLink.follow(next, after: Self.current, api: Self.api) == next)
    }

    @Test(arguments: [
        "https://evil.example.com/organizations/7/packages?page=2",
        "http://api.github.com/organizations/7/packages?page=2",
        "https://api.github.com:8443/organizations/7/packages?page=2",
        "https://api.github.com.evil.example.com/packages?page=2",
        "https://github.com/organizations/7/packages?page=2",
        "ftp://api.github.com/packages",
    ])
    func `A link to another host, scheme or port stops paging`(link: String) {
        #expect(PageLink.follow(URL(string: link)!, after: Self.current, api: Self.api) == nil)
    }

    @Test func `No link and the same page again both stop`() {
        #expect(PageLink.follow(nil, after: Self.current, api: Self.api) == nil)
        #expect(PageLink.follow(Self.current, after: Self.current, api: Self.api) == nil)
    }

    @Test func `GitHub Enterprise Server: the server's host with its port, any path`() {
        let api = URL(string: "https://github.example.com:8443/api/v3")!
        let current = URL(string: "https://github.example.com:8443/api/v3/orgs/acme/packages")!
        let same = URL(string: "https://github.example.com:8443/api/v3/organizations/7/packages?page=2")!
        #expect(PageLink.follow(same, after: current, api: api) == same)
        #expect(PageLink.follow(URL(string: "https://github.example.com/api/v3/organizations/7/packages?page=2")!, after: current, api: api) == nil)
    }

    @Test func `GHE.com: the API host, not the web host`() {
        let api = URL(string: "https://api.acme.ghe.com")!
        let current = URL(string: "https://api.acme.ghe.com/orgs/acme/packages")!
        let same = URL(string: "https://api.acme.ghe.com/organizations/7/packages?page=2")!
        #expect(PageLink.follow(same, after: current, api: api) == same)
        #expect(PageLink.follow(URL(string: "https://acme.ghe.com/organizations/7/packages?page=2")!, after: current, api: api) == nil)
    }

    @Test func `Reads rel next from a Link header`() {
        let header = #"<https://api.github.com/a?before=x>; rel="prev", <https://api.github.com/a?after=y>; rel="next""#
        #expect(PageLink.next(inHeader: header)?.absoluteString == "https://api.github.com/a?after=y")
        #expect(PageLink.next(inHeader: #"<https://api.github.com/a>; rel = "next""#)?.absoluteString == "https://api.github.com/a")
        #expect(PageLink.next(inHeader: #"<https://api.github.com/x>; rel="last""#) == nil)
        #expect(PageLink.next(inHeader: "") == nil)
    }
}
