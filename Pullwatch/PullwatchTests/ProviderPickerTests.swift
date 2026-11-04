import Testing

@testable import Pullwatch

/// De kaarten van het welkomstvenster in rijen: zo min mogelijk rijen van hooguit drie, zo
/// gelijk mogelijk verdeeld, de langere rijen eerst.
@MainActor @Suite struct ProviderPickerTests {
    @Test(arguments: [
        (3, [3]), (4, [2, 2]), (5, [3, 2]), (6, [3, 3]), (7, [3, 2, 2]), (1, [1]), (0, []),
    ])
    func `Cards are spread over balanced rows`(count: Int, lengths: [Int]) {
        let rows = ProviderPicker.rows(of: count)
        #expect(rows.map(\.count) == lengths)
        #expect(rows.first?.lowerBound ?? 0 == 0)
        #expect(rows.last?.upperBound ?? 0 == count)
    }
}
