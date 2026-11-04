import Charts
import PullwatchCore
import SwiftUI

/// Hoe de PR's achter een staaf in de ranglijst nu staan, met het icoon en de kleur per status.
private struct StateBreakdown: View {
    let counts: PRStateCounts
    let saysCompleted: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 3) {
            ForEach(PRStatus.allCases.filter { counts.count($0) > 0 }, id: \.self) { status in
                GridRow {
                    status.glyph.image.foregroundStyle(status.color)
                    Text(counts.count(status), format: .number).monospacedDigit().gridColumnAlignment(.trailing)
                    Text(status.stateName(saysCompleted: saysCompleted))
                }
            }
        }
        .font(.caption)
    }
}

/// Een top tien als liggende staven; klikken op een staaf kiest die naam.
struct RankingChart: View {
    let title: LocalizedStringResource
    let items: [RankedName]
    /// De huidige status van de PR's per naam, voor de tooltip.
    let states: [String: PRStateCounts]
    let saysCompleted: Bool
    let selected: String?
    let select: (String) -> Void

    /// De naam onder de muis en waar de muis staat.
    @State private var hover: (name: String, location: CGPoint)?
    @State private var tooltipSize: CGSize = .zero

    private func spokenStates(_ name: String) -> Text {
        let counts = states[name] ?? PRStateCounts()
        return saysCompleted
            ? Text("Open: \(counts.open), draft: \(counts.draft), afgerond: \(counts.merged), gesloten: \(counts.closed)")
            : Text("Open: \(counts.open), draft: \(counts.draft), gemerged: \(counts.merged), gesloten: \(counts.closed)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if items.isEmpty {
                Text("Geen PR's in deze periode").foregroundStyle(.secondary).font(.callout)
            } else {
                Chart(items) { item in
                    BarMark(
                        x: .value("PR's", item.count),
                        y: .value("Naam", item.name),
                        height: .fixed(8)
                    )
                    .foregroundStyle(item.name == selected || selected == nil ? Color.accentColor : Color.accentColor.opacity(0.35))
                    // De naam boven de staaf en het aantal erachter: lange namen passen zo altijd.
                    .annotation(position: .top, alignment: .leading, spacing: 3) {
                        Text(verbatim: item.name)
                            .font(.callout)
                            .fontWeight(item.name == selected ? .semibold : .regular)
                            .lineLimit(1)
                    }
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(item.count, format: .number)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(Text(verbatim: item.name))
                    .accessibilityValue(spokenStates(item.name))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartXScale(domain: 0...(Double(items.first?.count ?? 1) * 1.1))
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    guard let frame = proxy.plotFrame else { return }
                                    let y = location.y - geometry[frame].origin.y
                                    if let name: String = proxy.value(atY: y) { select(name) }
                                }
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        guard let frame = proxy.plotFrame else { return }
                                        let y = location.y - geometry[frame].origin.y
                                        let name: String? = proxy.value(atY: y)
                                        hover = name.map { ($0, location) }
                                    case .ended:
                                        hover = nil
                                    }
                                }
                            if let hover, let counts = states[hover.name] {
                                tooltip(counts, at: hover.location, in: geometry.size)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(items.count) * 38 + 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// De uitsplitsing naast de muis, binnen de breedte van de grafiek: rechts van de muis, of
    /// links als hij daar niet past; onder de muis in de bovenste helft, anders erboven.
    private func tooltip(_ counts: PRStateCounts, at location: CGPoint, in size: CGSize) -> some View {
        let width = tooltipSize.width
        let height = tooltipSize.height
        let right = location.x + 14 + width / 2
        let x = right + width / 2 <= size.width ? right : max(width / 2, location.x - 14 - width / 2)
        let y = location.y < size.height / 2 ? location.y + 14 + height / 2 : location.y - 10 - height / 2
        return StateBreakdown(counts: counts, saysCompleted: saysCompleted)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator) }
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { tooltipSize = $0 }
            .position(x: x, y: y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
