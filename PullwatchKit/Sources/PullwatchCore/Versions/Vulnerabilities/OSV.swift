public import Foundation

/// Details van één OSV-record, voor zover Pullwatch ze toont.
public struct OSVRecord: Equatable, Sendable {
    public let id: String
    public let aliases: [String]
    public let summary: String?
    /// `database_specific.severity` in hoofdletters ("MODERATE"); de meeste databases buiten GitHub
    /// geven die niet.
    public let severity: String?
    /// "ecosysteem/naam" → alle "fixed"-versies uit de ranges.
    public let fixed: [String: [String]]
    public let related: [String]
    public let references: [VulnerabilityReference]
    public let published: Date?
    public let modified: Date?
    let withdrawn: Date?
    /// De beste CVSS uit `severity[]` (4.0 vóór 3.x), anders uit `affected[].severity`.
    public let cvss: CVSSRating?
    /// Uit het voorvoegsel van de id, anders uit `affected[].database_specific.source` of
    /// `database_specific.url`.
    public let database: AdvisorySource

    public init(
        id: String, aliases: [String], summary: String?, severity: String?, fixed: [String: [String]],
        related: [String] = [], references: [VulnerabilityReference] = [], published: Date? = nil, modified: Date? = nil,
        withdrawn: Date? = nil, cvss: CVSSRating? = nil, database: AdvisorySource? = nil
    ) {
        self.id = id
        self.aliases = aliases
        self.summary = summary
        self.severity = severity
        self.fixed = fixed
        self.related = related
        self.references = references
        self.published = published
        self.modified = modified
        self.withdrawn = withdrawn
        self.cvss = cvss
        self.database = database ?? AdvisorySource.of(id: id) ?? .other
    }

    /// De ernst die dit record zelf geeft: de CVSS-score, anders `database_specific.severity`.
    var ownSeverity: String? { cvss?.level ?? severity }
}

/// De bekende kwetsbaarheden van packages bij OSV.dev: eerst de ids per package in batches, dan de details.
public enum OSV {
    /// OSV staat maximaal 1000 queries per batch toe.
    static let batchSize = 1000
    static let detailConcurrency = 8

    /// Ids van kwetsbaarheden per dependency, in dezelfde volgorde als `dependencies`.
    public static func query(_ dependencies: [Dependency], http: any HTTPClient, now: Date = Date()) async throws -> [[String]] {
        struct Query: Encodable {
            struct Package: Encodable { let name: String; let ecosystem: String }
            let package: Package
            let version: String
        }
        struct Response: Decodable {
            struct Result: Decodable {
                struct Vuln: Decodable { let id: String }
                let vulns: [Vuln]?
            }
            let results: [Result]
        }
        var ids: [[String]] = []
        for start in stride(from: 0, to: dependencies.count, by: batchSize) {
            let chunk = dependencies[start..<min(start + batchSize, dependencies.count)]
            var request = URLRequest(url: URL(string: "https://api.osv.dev/v1/querybatch")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["queries": chunk.map {
                Query(package: .init(name: $0.name, ecosystem: $0.ecosystem), version: $0.version)
            }])
            let (data, response) = try await http.send(request)
            try HTTPStatus.check(response, now: now)
            let decoded = try JSONDecoding.decode(Response.self, from: data)
            guard decoded.results.count == chunk.count else {
                throw ProviderError.decoding(String(localized: "OSV: het aantal resultaten (\(decoded.results.count)) past niet bij het aantal vragen (\(chunk.count))", bundle: .localizedCore))
            }
            ids += decoded.results.map { ($0.vulns ?? []).map(\.id) }
        }
        return ids
    }

    static func decodeRecord(_ data: Data) throws -> OSVRecord {
        /// `database_specific` is vrij per database: elk veld los, zodat een ander type
        /// (een getal als ernst, een object als bron) het record niet onleesbaar maakt.
        struct DatabaseSpecific: Decodable {
            let severity: String?
            let source: String?
            let url: String?

            enum CodingKeys: String, CodingKey { case severity, source, url }

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                severity = try? c.decodeIfPresent(String.self, forKey: .severity)
                source = try? c.decodeIfPresent(String.self, forKey: .source)
                url = try? c.decodeIfPresent(String.self, forKey: .url)
            }
        }
        struct Severity: Decodable {
            let type: String
            let score: String
            let source: String?
        }
        struct Reference: Decodable {
            let type: String?
            let url: String
        }
        struct Record: Decodable {
            struct Affected: Decodable {
                struct Package: Decodable { let name: String; let ecosystem: String }
                struct Range: Decodable {
                    struct Event: Decodable { let fixed: String? }
                    let type: String?
                    let events: [Event]
                }
                let package: Package?
                let ranges: [Range]?
                let severity: [Severity]?
                let databaseSpecific: DatabaseSpecific?
            }
            let id: String
            let aliases: [String]?
            let related: [String]?
            let summary: String?
            let published: String?
            let modified: String?
            let withdrawn: String?
            let severity: [Severity]?
            let references: [Reference]?
            let databaseSpecific: DatabaseSpecific?
            let affected: [Affected]?
        }
        let record = try JSONDecoding.decode(Record.self, from: data, snakeCase: true)
        var fixed: [String: [String]] = [:]
        for affected in record.affected ?? [] {
            guard let package = affected.package else { continue }
            // GIT-ranges hebben commit-hashes in plaats van versies.
            let versions = (affected.ranges ?? []).filter { $0.type != "GIT" }.flatMap { $0.events.compactMap(\.fixed) }
            fixed["\(package.ecosystem)/\(package.name)", default: []] += versions
        }
        // CVSS 4.0 vóór 3.x; CVSS_V2 en andere soorten (Ubuntu-prioriteit) rekent Pullwatch niet.
        func best(_ severities: [Severity]) -> CVSSRating? {
            let ratings = severities.compactMap { item -> CVSSRating? in
                guard item.type == "CVSS_V4" || item.type == "CVSS_V3", let score = CVSSCalculator.score(item.score) else { return nil }
                return CVSSRating(vector: item.score, score: score, assessor: item.source)
            }
            return ratings.first { $0.version == "4.0" } ?? ratings.first
        }
        let sources = [record.databaseSpecific?.url, record.databaseSpecific?.source]
            + (record.affected ?? []).flatMap { [$0.databaseSpecific?.source, $0.databaseSpecific?.url] }
        let references = (record.references ?? []).compactMap { reference -> VulnerabilityReference? in
            guard let url = URL(string: reference.url), url.scheme == "https" || url.scheme == "http" else { return nil }
            return VulnerabilityReference(type: (reference.type ?? "WEB").uppercased(), url: url)
        }
        return OSVRecord(
            id: record.id,
            aliases: record.aliases ?? [],
            summary: record.summary,
            severity: record.databaseSpecific?.severity?.uppercased(),
            fixed: fixed,
            related: record.related ?? [],
            references: VulnerabilityReference.ordered(references),
            published: record.published.flatMap(DateParsing.parse),
            modified: record.modified.flatMap(DateParsing.parse),
            withdrawn: record.withdrawn.flatMap(DateParsing.parse),
            cvss: best(record.severity ?? []) ?? best((record.affected ?? []).flatMap { $0.severity ?? [] }),
            database: AdvisorySource.of(id: record.id) ?? sources.compactMap { $0.flatMap(AdvisorySource.of(sourceURL:)) }.first
        )
    }

    public static func record(id: String, http: any HTTPClient, now: Date = Date()) async throws -> OSVRecord {
        let (data, response) = try await http.send(URLRequest(url: URL(string: "https://api.osv.dev/v1/vulns")!.appending(path: id)))
        try HTTPStatus.check(response, now: now)
        return try decodeRecord(data)
    }

    /// Haalt de details van alle ids op, maximaal `detailConcurrency` tegelijk. Mislukte ids ontbreken.
    /// `failed` telt de ids zonder details: dan ontbreken ernst, fix-versie en het samenvoegen
    /// van aliassen, en moet de check als onvolledig gemeld worden.
    public static func records(ids: Set<String>, http: any HTTPClient, now: Date = Date()) async -> (records: [String: OSVRecord], failed: Int) {
        await withTaskGroup(of: OSVRecord?.self) { group in
            var pending = ids.sorted().makeIterator()
            var result: [String: OSVRecord] = [:]
            var failed = 0
            for _ in 0..<detailConcurrency {
                guard let id = pending.next() else { break }
                group.addTask { try? await record(id: id, http: http, now: now) }
            }
            for await record in group {
                if let record { result[record.id] = record } else { failed += 1 }
                if let id = pending.next() {
                    group.addTask { try? await OSV.record(id: id, http: http, now: now) }
                }
            }
            return (result, failed)
        }
    }

    /// De database die een ecosysteem zelf bijhoudt; die wint van GitHubs kopie van hetzelfde lek.
    static let nativeDatabases: [String: AdvisorySource] = ["crates.io": .rustSec, "Go": .go, "PyPI": .pyPA]

    /// Welke van twee ids voor hetzelfde lek blijft: niet ingetrokken eerst, dan de eigen database
    /// van het ecosysteem, dan GitHub (met de meeste gegevens), dan alfabetisch.
    static func preference(_ id: String, record: OSVRecord?, ecosystem: String) -> (Int, Int, String) {
        let database = record?.database ?? AdvisorySource.of(id: id) ?? .other
        let origin = database == nativeDatabases[ecosystem] ? 0 : database == .gitHub ? 1 : 2
        return (record?.withdrawn == nil ? 0 : 1, origin, id)
    }

    /// GHSA eerst, dan CVE, dan de rest alfabetisch; elk één keer en zonder `id`.
    static func orderedAliases(_ aliases: [String], without id: String) -> [String] {
        func rank(_ alias: String) -> Int { alias.hasPrefix("GHSA-") ? 0 : alias.hasPrefix("CVE-") ? 1 : 2 }
        return Set(aliases).subtracting([id]).sorted { (rank($0), $0) < (rank($1), $1) }
    }

    /// Kwetsbaarheden per dependency (install); een id die alias is van een andere id voor hetzelfde
    /// package valt weg (GitHub, RustSec, PyPA en Go melden vaak hetzelfde lek onder twee ids). Wat
    /// blijft krijgt de ids, de ernst en de fix-versies van wat wegviel. Ingetrokken adviezen
    /// blijven erin, met `withdrawn`; de check houdt ze apart.
    public static func vulnerabilities(
        dependencies: [Dependency],
        ids: [[String]],
        records: [String: OSVRecord]
    ) -> [Vulnerability] {
        var result: [Vulnerability] = []
        for (dependency, found) in zip(dependencies, ids) where !found.isEmpty {
            let ordered = found.sorted {
                preference($0, record: records[$0], ecosystem: dependency.ecosystem)
                    < preference($1, record: records[$1], ecosystem: dependency.ecosystem)
            }
            var kept: [(id: String, duplicates: [String])] = []
            for id in ordered {
                let index = kept.firstIndex { other in
                    records[other.id]?.aliases.contains(id) == true || records[id]?.aliases.contains(other.id) == true
                }
                if let index { kept[index].duplicates.append(id) } else { kept.append((id, [])) }
            }
            let key = "\(dependency.ecosystem)/\(dependency.name)"
            for (id, duplicates) in kept {
                let record = records[id]
                let group = ([id] + duplicates).compactMap { records[$0] }
                let ids = group.flatMap { [$0.id] + $0.aliases } + duplicates
                let fixes = group.lazy.map { $0.fixed[key] ?? [] }.first { !$0.isEmpty } ?? []
                let fixedIn = fixes
                    .filter { VersionChecker.isOlder(dependency.version, than: $0) }
                    .min { VersionChecker.isOlder($0, than: $1) }
                // De beste ernst van de groep: een CVSS-vector, anders `database_specific.severity`.
                let rated = group.first { $0.cvss != nil } ?? group.first { $0.severity != nil }
                let aliases = orderedAliases(ids, without: id)
                result.append(Vulnerability(
                    id: id,
                    cve: id.hasPrefix("CVE-") ? id : aliases.first { $0.hasPrefix("CVE-") },
                    ghsa: id.hasPrefix("GHSA-") ? id : aliases.first { $0.hasPrefix("GHSA-") },
                    summary: record?.summary ?? group.lazy.compactMap(\.summary).first,
                    severity: rated?.ownSeverity,
                    ecosystem: dependency.ecosystem,
                    package: dependency.name,
                    version: dependency.version,
                    fixedIn: fixedIn,
                    source: dependency.source,
                    workspace: dependency.workspace,
                    scope: dependency.scope,
                    kind: dependency.kind,
                    via: dependency.via,
                    requested: dependency.requested,
                    database: record?.database,
                    aliases: aliases,
                    related: Array(Set(group.flatMap(\.related)).subtracting(ids)).sorted(),
                    references: VulnerabilityReference.ordered(group.flatMap(\.references)),
                    published: record?.published,
                    modified: record?.modified,
                    withdrawn: record?.withdrawn,
                    cvss: rated?.cvss,
                    severityFrom: rated?.id
                ))
            }
        }
        return result.sorted {
            if $0.severityRank != $1.severityRank { return $0.severityRank > $1.severityRank }
            return ($0.package, $0.id, $0.workspace, $0.version) < ($1.package, $1.id, $1.workspace, $1.version)
        }
    }
}
