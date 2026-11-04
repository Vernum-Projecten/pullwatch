import Foundation

/// Rekent de score van een CVSS-vector uit, zoals FIRST dat doet: CVSS 3.0 en 3.1 (de basisscore
/// uit de specificatie) en CVSS 4.0 (de MacroVector-tabel met interpolatie uit FIRSTs eigen
/// calculator, github.com/FIRSTdotorg/cvss-v4-calculator). OSV geeft alleen de vector, geen getal.
enum CVSSCalculator {
    /// De score van 0.0 t/m 10.0; nil als de vector geen geldige CVSS 3.x of 4.0 is.
    /// Bij 3.x telt alleen de basisgroep; bij 4.0 tellen threat- en omgevingsmetrieken mee als
    /// de vector ze noemt (CVSS-BT, -BE, -BTE), zoals in FIRSTs calculator.
    public static func score(_ vector: String) -> Double? {
        switch version(of: vector) {
        case "3.0": v3Score(vector, roundUp: roundUp30)
        case "3.1": v3Score(vector, roundUp: roundUp31)
        case "4.0": v4Score(vector)
        default: nil
        }
    }

    /// "3.1" of "4.0" uit "CVSS:3.1/…"; nil zonder voorvoegsel.
    public static func version(of vector: String) -> String? {
        guard vector.hasPrefix("CVSS:") else { return nil }
        return vector.dropFirst("CVSS:".count).split(separator: "/").first.map(String.init)
    }

    /// De kwalitatieve ernst bij een score, met de namen van GitHub en OSV: "CRITICAL" (9.0 en
    /// hoger), "HIGH" (7.0), "MODERATE" (4.0), "LOW" (0.1); nil bij 0.0 ("None").
    static func rating(_ score: Double) -> String? {
        switch score {
        case 9.0...: "CRITICAL"
        case 7.0..<9.0: "HIGH"
        case 4.0..<7.0: "MODERATE"
        case 0.1..<4.0: "LOW"
        default: nil
        }
    }

    /// "CVSS:3.1/AV:N/AC:L/…" → ["AV": "N", …]; nil als een metriek dubbel staat of geen waarde heeft.
    static func metrics(_ vector: String) -> [String: String]? {
        var result: [String: String] = [:]
        for part in vector.split(separator: "/").dropFirst() {
            let pair = part.split(separator: ":", omittingEmptySubsequences: false)
            guard pair.count == 2, !pair[1].isEmpty, result[String(pair[0])] == nil else { return nil }
            result[String(pair[0])] = String(pair[1])
        }
        return result
    }

    // MARK: CVSS 3.x

    /// Roundup uit bijlage A van de 3.1-specificatie: vrij van afrondingsfouten van drijvende komma.
    static func roundUp31(_ value: Double) -> Double {
        let scaled = Int((value * 100_000).rounded())
        return scaled % 10_000 == 0 ? Double(scaled) / 100_000 : (Double(scaled / 10_000) + 1) / 10
    }

    /// Roundup uit de 3.0-specificatie: het kleinste getal met één decimaal dat niet kleiner is.
    static func roundUp30(_ value: Double) -> Double {
        (value * 10).rounded(.up) / 10
    }

    static func v3Score(_ vector: String, roundUp: (Double) -> Double) -> Double? {
        guard let m = metrics(vector) else { return nil }
        let scopeChanged: Bool
        switch m["S"] {
        case "U": scopeChanged = false
        case "C": scopeChanged = true
        default: return nil
        }
        let impactWeights = ["H": 0.56, "L": 0.22, "N": 0.0]
        let privilegeWeights = scopeChanged ? ["N": 0.85, "L": 0.68, "H": 0.5] : ["N": 0.85, "L": 0.62, "H": 0.27]
        guard let av = ["N": 0.85, "A": 0.62, "L": 0.55, "P": 0.2][m["AV"] ?? ""],
              let ac = ["L": 0.77, "H": 0.44][m["AC"] ?? ""],
              let pr = privilegeWeights[m["PR"] ?? ""],
              let ui = ["N": 0.85, "R": 0.62][m["UI"] ?? ""],
              let c = impactWeights[m["C"] ?? ""],
              let i = impactWeights[m["I"] ?? ""],
              let a = impactWeights[m["A"] ?? ""]
        else { return nil }
        let iss = 1 - ((1 - c) * (1 - i) * (1 - a))
        let impact = scopeChanged ? 7.52 * (iss - 0.029) - 3.25 * pow(iss - 0.02, 15) : 6.42 * iss
        let exploitability = 8.22 * av * ac * pr * ui
        guard impact > 0 else { return 0 }
        return scopeChanged
            ? roundUp(min(1.08 * (impact + exploitability), 10))
            : roundUp(min(impact + exploitability, 10))
    }

    // MARK: CVSS 4.0

    /// Elke metriek van 4.0 met zijn toegestane waarden, in de volgorde van de specificatie. De
    /// eerste elf (de basisgroep) zijn verplicht; de rest is standaard "X" (niet gedefinieerd).
    static let v4Metrics: [(name: String, values: Set<String>)] = [
        ("AV", ["N", "A", "L", "P"]), ("AC", ["L", "H"]), ("AT", ["N", "P"]), ("PR", ["N", "L", "H"]), ("UI", ["N", "P", "A"]),
        ("VC", ["H", "L", "N"]), ("VI", ["H", "L", "N"]), ("VA", ["H", "L", "N"]),
        ("SC", ["H", "L", "N"]), ("SI", ["H", "L", "N"]), ("SA", ["H", "L", "N"]),
        ("E", ["X", "A", "P", "U"]), ("CR", ["X", "H", "M", "L"]), ("IR", ["X", "H", "M", "L"]), ("AR", ["X", "H", "M", "L"]),
        ("MAV", ["X", "N", "A", "L", "P"]), ("MAC", ["X", "L", "H"]), ("MAT", ["X", "N", "P"]), ("MPR", ["X", "N", "L", "H"]),
        ("MUI", ["X", "N", "P", "A"]), ("MVC", ["X", "H", "L", "N"]), ("MVI", ["X", "H", "L", "N"]), ("MVA", ["X", "H", "L", "N"]),
        ("MSC", ["X", "H", "L", "N"]), ("MSI", ["X", "S", "H", "L", "N"]), ("MSA", ["X", "S", "H", "L", "N"]),
        ("S", ["X", "N", "P"]), ("AU", ["X", "N", "Y"]), ("R", ["X", "A", "U", "I"]), ("V", ["X", "D", "C"]),
        ("RE", ["X", "L", "M", "H"]), ("U", ["X", "Clear", "Green", "Amber", "Red"]),
    ]

    /// De gekozen waarden van een 4.0-vector, met de regels van FIRSTs `m()`: E:X telt als E:A,
    /// CR/IR/AR:X als H, en een gezette omgevingsmetriek (MAV …) vervangt de basiswaarde.
    struct V4Selection {
        let raw: [String: String]

        init?(_ vector: String) {
            guard let given = CVSSCalculator.metrics(vector) else { return nil }
            var raw: [String: String] = [:]
            for (index, metric) in CVSSCalculator.v4Metrics.enumerated() {
                if let value = given[metric.name] {
                    guard metric.values.contains(value) else { return nil }
                    raw[metric.name] = value
                } else {
                    guard index >= 11 else { return nil }
                    raw[metric.name] = "X"
                }
            }
            guard given.keys.allSatisfy({ raw[$0] != nil }) else { return nil }
            self.raw = raw
        }

        subscript(_ metric: String) -> String {
            let selected = raw[metric] ?? "X"
            if metric == "E", selected == "X" { return "A" }
            if ["CR", "IR", "AR"].contains(metric), selected == "X" { return "H" }
            if let modified = raw["M" + metric], modified != "X" { return modified }
            return selected
        }
    }

    /// De MacroVector: zes cijfers, één per equivalentieklasse (EQ1 … EQ6).
    static func macroVector(_ m: V4Selection) -> [Int] {
        let eq1: Int
        if m["AV"] == "N", m["PR"] == "N", m["UI"] == "N" {
            eq1 = 0
        } else if m["AV"] == "N" || m["PR"] == "N" || m["UI"] == "N", m["AV"] != "P" {
            eq1 = 1
        } else {
            eq1 = 2
        }
        let eq2 = m["AC"] == "L" && m["AT"] == "N" ? 0 : 1
        let eq3: Int
        if m["VC"] == "H", m["VI"] == "H" {
            eq3 = 0
        } else if m["VC"] == "H" || m["VI"] == "H" || m["VA"] == "H" {
            eq3 = 1
        } else {
            eq3 = 2
        }
        let eq4: Int
        if m["MSI"] == "S" || m["MSA"] == "S" {
            eq4 = 0
        } else if m["SC"] == "H" || m["SI"] == "H" || m["SA"] == "H" {
            eq4 = 1
        } else {
            eq4 = 2
        }
        let eq5 = switch m["E"] {
        case "A": 0
        case "P": 1
        default: 2
        }
        let highRequirement = (m["CR"] == "H" && m["VC"] == "H") || (m["IR"] == "H" && m["VI"] == "H") || (m["AR"] == "H" && m["VA"] == "H")
        return [eq1, eq2, eq3, eq4, eq5, highRequirement ? 0 : 1]
    }

    static func v4Score(_ vector: String) -> Double? {
        guard let m = V4Selection(vector) else { return nil }
        // Geen gevolg voor het kwetsbare of een volgend systeem: altijd 0.
        if ["VC", "VI", "VA", "SC", "SI", "SA"].allSatisfy({ m[$0] == "N" }) { return 0 }

        let macro = macroVector(m)
        func lookup(_ eq: [Int]) -> Double? { v4Lookup[eq.map(String.init).joined()] }
        func lower(_ indices: Int...) -> [Int] {
            var next = macro
            for index in indices { next[index] += 1 }
            return next
        }
        guard let value = lookup(macro) else { return nil }
        let (eq1, eq2, eq3, eq4, eq5, eq6) = (macro[0], macro[1], macro[2], macro[3], macro[4], macro[5])

        // 1a. De MacroVector één stap lager per EQ, als die bestaat. EQ3 en EQ6 horen bij elkaar.
        let lowerEq3Eq6: Double?
        switch (eq3, eq6) {
        case (1, 1), (0, 1): lowerEq3Eq6 = lookup(lower(2))
        case (1, 0): lowerEq3Eq6 = lookup(lower(5))
        case (0, 0):
            // Twee wegen omlaag; zoals bij FIRST telt links alleen als die hoger scoort.
            let left = lookup(lower(5))
            let right = lookup(lower(2))
            if let left, let right, left > right { lowerEq3Eq6 = left } else { lowerEq3Eq6 = right }
        default: lowerEq3Eq6 = lookup(lower(2, 5))
        }
        let lowerScores = [lookup(lower(0)), lookup(lower(1)), lowerEq3Eq6, lookup(lower(3)), lookup(lower(4))]

        // 1b. De ernstafstand tot een vector met de hoogste ernst in dezelfde MacroVector.
        var maxVectors: [String] = []
        for a in v4MaxComposed.eq1[eq1] ?? [] {
            for b in v4MaxComposed.eq2[eq2] ?? [] {
                for c in v4MaxComposed.eq3[eq3]?[eq6] ?? [] {
                    for d in v4MaxComposed.eq4[eq4] ?? [] {
                        for e in v4MaxComposed.eq5[eq5] ?? [] {
                            maxVectors.append(a + b + c + d + e)
                        }
                    }
                }
            }
        }
        let distanceMetrics = ["AV", "PR", "UI", "AC", "AT", "VC", "VI", "VA", "SC", "SI", "SA", "CR", "IR", "AR"]
        var distance: [String: Double] = [:]
        for maxVector in maxVectors {
            let maxValues = metrics("CVSS:4.0/" + maxVector) ?? [:]
            for metric in distanceMetrics {
                let levels = v4Levels[metric] ?? [:]
                distance[metric] = (levels[m[metric]] ?? .nan) - (levels[maxValues[metric] ?? ""] ?? .nan)
            }
            // Een negatieve afstand: dit is niet de juiste hoogste vector. Anders is de eerste genoeg.
            if distanceMetrics.contains(where: { (distance[$0] ?? 0) < 0 }) { continue }
            break
        }
        func d(_ metric: String) -> Double { distance[metric] ?? .nan }
        let current = [
            d("AV") + d("PR") + d("UI"),
            d("AC") + d("AT"),
            d("VC") + d("VI") + d("VA") + d("CR") + d("IR") + d("AR"),
            d("SC") + d("SI") + d("SA"),
            0,
        ]

        // 1c/1d. Het deel van de afstand (gedeeld door de diepte van de MacroVector), maal het
        // verschil met de lagere MacroVector. Voor EQ5 is dat deel altijd 0.
        let step = 0.1
        let depth = [
            Double(v4MaxSeverity.eq1[eq1] ?? 0) * step,
            Double(v4MaxSeverity.eq2[eq2] ?? 0) * step,
            Double(v4MaxSeverity.eq3Eq6[eq3]?[eq6] ?? 0) * step,
            Double(v4MaxSeverity.eq4[eq4] ?? 0) * step,
            1,
        ]
        var existingLower = 0
        var total = 0.0
        for (index, lowerScore) in lowerScores.enumerated() {
            guard let lowerScore else { continue }
            existingLower += 1
            total += index == 4 ? (value - lowerScore) * 0 : (value - lowerScore) * (current[index] / depth[index])
        }

        // 2/3. De score van de MacroVector min het gemiddelde, op één decimaal.
        let mean = existingLower == 0 ? 0 : total / Double(existingLower)
        let score = min(max(value - mean, 0), 10)
        return (score * 10 + 0.5).rounded(.down) / 10
    }

    /// De niveaus per metriek voor de ernstafstand (`*_levels` in FIRSTs `cvss_score.js`).
    static let v4Levels: [String: [String: Double]] = [
        "AV": ["N": 0.0, "A": 0.1, "L": 0.2, "P": 0.3],
        "PR": ["N": 0.0, "L": 0.1, "H": 0.2],
        "UI": ["N": 0.0, "P": 0.1, "A": 0.2],
        "AC": ["L": 0.0, "H": 0.1],
        "AT": ["N": 0.0, "P": 0.1],
        "VC": ["H": 0.0, "L": 0.1, "N": 0.2],
        "VI": ["H": 0.0, "L": 0.1, "N": 0.2],
        "VA": ["H": 0.0, "L": 0.1, "N": 0.2],
        "SC": ["H": 0.1, "L": 0.2, "N": 0.3],
        "SI": ["S": 0.0, "H": 0.1, "L": 0.2, "N": 0.3],
        "SA": ["S": 0.0, "H": 0.1, "L": 0.2, "N": 0.3],
        "CR": ["H": 0.0, "M": 0.1, "L": 0.2],
        "IR": ["H": 0.0, "M": 0.1, "L": 0.2],
        "AR": ["H": 0.0, "M": 0.1, "L": 0.2],
    ]

    /// De vectoren met de hoogste ernst per EQ-niveau (`max_composed.js`).
    static let v4MaxComposed: (
        eq1: [Int: [String]], eq2: [Int: [String]], eq3: [Int: [Int: [String]]], eq4: [Int: [String]], eq5: [Int: [String]]
    ) = (
        eq1: [0: ["AV:N/PR:N/UI:N/"], 1: ["AV:A/PR:N/UI:N/", "AV:N/PR:L/UI:N/", "AV:N/PR:N/UI:P/"], 2: ["AV:P/PR:N/UI:N/", "AV:A/PR:L/UI:P/"]],
        eq2: [0: ["AC:L/AT:N/"], 1: ["AC:H/AT:N/", "AC:L/AT:P/"]],
        eq3: [
            0: [0: ["VC:H/VI:H/VA:H/CR:H/IR:H/AR:H/"], 1: ["VC:H/VI:H/VA:L/CR:M/IR:M/AR:H/", "VC:H/VI:H/VA:H/CR:M/IR:M/AR:M/"]],
            1: [
                0: ["VC:L/VI:H/VA:H/CR:H/IR:H/AR:H/", "VC:H/VI:L/VA:H/CR:H/IR:H/AR:H/"],
                1: [
                    "VC:L/VI:H/VA:L/CR:H/IR:M/AR:H/", "VC:L/VI:H/VA:H/CR:H/IR:M/AR:M/", "VC:H/VI:L/VA:H/CR:M/IR:H/AR:M/",
                    "VC:H/VI:L/VA:L/CR:M/IR:H/AR:H/", "VC:L/VI:L/VA:H/CR:H/IR:H/AR:M/",
                ],
            ],
            2: [1: ["VC:L/VI:L/VA:L/CR:H/IR:H/AR:H/"]],
        ],
        eq4: [0: ["SC:H/SI:S/SA:S/"], 1: ["SC:H/SI:H/SA:H/"], 2: ["SC:L/SI:L/SA:L/"]],
        eq5: [0: ["E:A/"], 1: ["E:P/"], 2: ["E:U/"]]
    )

    /// De diepte (hoogste ernstafstand + 1) per EQ-niveau (`max_severity.js`).
    static let v4MaxSeverity: (eq1: [Int: Int], eq2: [Int: Int], eq3Eq6: [Int: [Int: Int]], eq4: [Int: Int]) = (
        eq1: [0: 1, 1: 4, 2: 5],
        eq2: [0: 1, 1: 2],
        eq3Eq6: [0: [0: 7, 1: 6], 1: [0: 8, 1: 8], 2: [1: 10]],
        eq4: [0: 6, 1: 5, 2: 4]
    )

    /// De score per MacroVector (`cvss_lookup.js` van FIRST en Red Hat, BSD-2-Clause), als tekst
    /// zodat de compiler geen woordenboek van 270 elementen hoeft af te leiden.
    static let v4Lookup: [String: Double] = {
        var table: [String: Double] = [:]
        for pair in v4LookupText.split(whereSeparator: \.isWhitespace) {
            let parts = pair.split(separator: ":")
            if parts.count == 2, let score = Double(parts[1]) { table[String(parts[0])] = score }
        }
        return table
    }()

    private static let v4LookupText = """
        000000:10 000001:9.9 000010:9.8 000011:9.5 000020:9.5 000021:9.2 000100:10 000101:9.6
        000110:9.3 000111:8.7 000120:9.1 000121:8.1 000200:9.3 000201:9 000210:8.9 000211:8
        000220:8.1 000221:6.8 001000:9.8 001001:9.5 001010:9.5 001011:9.2 001020:9 001021:8.4
        001100:9.3 001101:9.2 001110:8.9 001111:8.1 001120:8.1 001121:6.5 001200:8.8 001201:8
        001210:7.8 001211:7 001220:6.9 001221:4.8 002001:9.2 002011:8.2 002021:7.2 002101:7.9
        002111:6.9 002121:5 002201:6.9 002211:5.5 002221:2.7 010000:9.9 010001:9.7 010010:9.5
        010011:9.2 010020:9.2 010021:8.5 010100:9.5 010101:9.1 010110:9 010111:8.3 010120:8.4
        010121:7.1 010200:9.2 010201:8.1 010210:8.2 010211:7.1 010220:7.2 010221:5.3 011000:9.5
        011001:9.3 011010:9.2 011011:8.5 011020:8.5 011021:7.3 011100:9.2 011101:8.2 011110:8
        011111:7.2 011120:7 011121:5.9 011200:8.4 011201:7 011210:7.1 011211:5.2 011220:5
        011221:3 012001:8.6 012011:7.5 012021:5.2 012101:7.1 012111:5.2 012121:2.9 012201:6.3
        012211:2.9 012221:1.7 100000:9.8 100001:9.5 100010:9.4 100011:8.7 100020:9.1 100021:8.1
        100100:9.4 100101:8.9 100110:8.6 100111:7.4 100120:7.7 100121:6.4 100200:8.7 100201:7.5
        100210:7.4 100211:6.3 100220:6.3 100221:4.9 101000:9.4 101001:8.9 101010:8.8 101011:7.7
        101020:7.6 101021:6.7 101100:8.6 101101:7.6 101110:7.4 101111:5.8 101120:5.9 101121:5
        101200:7.2 101201:5.7 101210:5.7 101211:5.2 101220:5.2 101221:2.5 102001:8.3 102011:7
        102021:5.4 102101:6.5 102111:5.8 102121:2.6 102201:5.3 102211:2.1 102221:1.3 110000:9.5
        110001:9 110010:8.8 110011:7.6 110020:7.6 110021:7 110100:9 110101:7.7 110110:7.5
        110111:6.2 110120:6.1 110121:5.3 110200:7.7 110201:6.6 110210:6.8 110211:5.9 110220:5.2
        110221:3 111000:8.9 111001:7.8 111010:7.6 111011:6.7 111020:6.2 111021:5.8 111100:7.4
        111101:5.9 111110:5.7 111111:5.7 111120:4.7 111121:2.3 111200:6.1 111201:5.2 111210:5.7
        111211:2.9 111220:2.4 111221:1.6 112001:7.1 112011:5.9 112021:3 112101:5.8 112111:2.6
        112121:1.5 112201:2.3 112211:1.3 112221:0.6 200000:9.3 200001:8.7 200010:8.6 200011:7.2
        200020:7.5 200021:5.8 200100:8.6 200101:7.4 200110:7.4 200111:6.1 200120:5.6 200121:3.4
        200200:7 200201:5.4 200210:5.2 200211:4 200220:4 200221:2.2 201000:8.5 201001:7.5
        201010:7.4 201011:5.5 201020:6.2 201021:5.1 201100:7.2 201101:5.7 201110:5.5 201111:4.1
        201120:4.6 201121:1.9 201200:5.3 201201:3.6 201210:3.4 201211:1.9 201220:1.9 201221:0.8
        202001:6.4 202011:5.1 202021:2 202101:4.7 202111:2.1 202121:1.1 202201:2.4 202211:0.9
        202221:0.4 210000:8.8 210001:7.5 210010:7.3 210011:5.3 210020:6 210021:5 210100:7.3
        210101:5.5 210110:5.9 210111:4 210120:4.1 210121:2 210200:5.4 210201:4.3 210210:4.5
        210211:2.2 210220:2 210221:1.1 211000:7.5 211001:5.5 211010:5.8 211011:4.5 211020:4
        211021:2.1 211100:6.1 211101:5.1 211110:4.8 211111:1.8 211120:2 211121:0.9 211200:4.6
        211201:1.8 211210:1.7 211211:0.7 211220:0.8 211221:0.2 212001:5.3 212011:2.4 212021:1.4
        212101:2.4 212111:1.2 212121:0.5 212201:1 212211:0.3 212221:0.1
        """
}
