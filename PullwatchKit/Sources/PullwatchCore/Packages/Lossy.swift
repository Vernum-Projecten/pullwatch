import Foundation

/// Een element dat bij het lezen mag mislukken: dan nil in plaats van een fout voor de hele lijst.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
