/// Bladeren door een lange lijst: `limit` en `cursor` in, `next_cursor` en `total` uit, zodat een
/// grote organisatie de context van de agent niet vult. De cursor is de positie van het eerste
/// item van de volgende pagina, als tekst; het model geeft hem alleen terug.
struct MCPPaging {
    static let defaultLimit = 25
    static let maxLimit = 100

    let offset: Int
    let limit: Int

    /// De invoervelden die elke lijst-tool erbij krijgt.
    static let inputFields: [String: MCPSchema] = [
        "limit": .integer("How many items to return (default \(defaultLimit), at most \(maxLimit)).", minimum: 1, maximum: maxLimit),
        "cursor": .string("The next_cursor of the previous page, to get the page after it. Leave it out for the first page.", maxLength: 32),
    ]

    /// De uitvoervelden van een pagina.
    static let outputFields: [String: MCPSchema] = [
        "total": .integer("How many items match the filters, over all pages."),
        "next_cursor": .string("Pass this as cursor to get the next page; absent on the last page."),
    ]

    init(_ arguments: MCPArguments) throws(MCPToolError) {
        limit = arguments.integer("limit") ?? Self.defaultLimit
        guard let cursor = arguments.string("cursor") else {
            offset = 0
            return
        }
        guard let offset = Int(cursor), offset >= 0 else {
            throw MCPToolError("`cursor` is not a cursor from this tool; pass the next_cursor of the previous page, or leave it out for the first page.")
        }
        self.offset = offset
    }

    /// De items van deze pagina en de cursor van de volgende (nil op de laatste).
    func page<Item>(_ items: [Item]) -> (items: [Item], nextCursor: String?) {
        let start = min(offset, items.count)
        let end = min(start + limit, items.count)
        return (Array(items[start..<end]), end < items.count ? String(end) : nil)
    }
}
