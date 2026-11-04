import MCP
import PullwatchMCP
import Testing

/// Het schema als JSON Schema en als controle van argumenten.
@Suite struct MCPSchemaTests {
    let filters = MCPSchema.object(
        [
            "repo": .string("Repository as owner/name.", maxLength: 10),
            "severity": .string(oneOf: ["low", "high"]),
            "limit": .integer(minimum: 1, maximum: 5),
            "score": .number(),
            "mine": .boolean(),
            "tags": .array(of: .string(), maxItems: 2),
            "nested": .object(["inner": .integer()], required: ["inner"]),
            "counts": .dictionary(of: .integer()),
        ],
        required: ["repo"]
    )

    @Test func `The JSON Schema lists every rule`() throws {
        let schema = try #require(filters.jsonSchema.objectValue)
        #expect(schema["type"] == "object")
        #expect(schema["required"] == ["repo"])
        #expect(schema["additionalProperties"] == false)
        let properties = try #require(schema["properties"]?.objectValue)
        #expect(properties["repo"] == ["type": "string", "maxLength": 10, "description": "Repository as owner/name."])
        #expect(properties["severity"] == ["type": "string", "enum": ["low", "high"]])
        #expect(properties["limit"] == ["type": "integer", "minimum": 1, "maximum": 5])
        #expect(properties["tags"] == ["type": "array", "items": ["type": "string"], "maxItems": 2])
        #expect(properties["counts"] == ["type": "object", "properties": [:], "additionalProperties": ["type": "integer"]])
    }

    @Test(arguments: [
        ["repo": "acme/web"],
        ["repo": "acme/web", "severity": "high", "limit": 5, "score": 9.5, "mine": true],
        ["repo": "acme/web", "limit": 3.0, "score": 2],
        ["repo": "acme/web", "tags": ["a", "b"], "nested": ["inner": 1], "counts": ["high": 2, "low": 0]],
    ] as [Value])
    func `Valid arguments pass`(value: Value) throws {
        try filters.validate(value)
    }

    @Test(arguments: [
        (["severity": "low"], "`repo` is required"),
        (["repo": 1], "`repo` must be a string"),
        (["repo": "far/too/long/name"], "`repo` must be at most 10 characters"),
        (["repo": "a", "severity": "medium"], "`severity` must be one of low, high"),
        (["repo": "a", "limit": 0], "`limit` must be at least 1"),
        (["repo": "a", "limit": 6], "`limit` must be at most 5"),
        (["repo": "a", "limit": "3"], "`limit` must be an integer"),
        (["repo": "a", "score": "high"], "`score` must be a number"),
        (["repo": "a", "mine": "yes"], "`mine` must be true or false"),
        (["repo": "a", "tags": "x"], "`tags` must be an array"),
        (["repo": "a", "tags": ["x", "y", "z"]], "`tags` must have at most 2 items"),
        (["repo": "a", "tags": ["x", 2]], "`tags[1]` must be a string"),
        (["repo": "a", "nested": [:]], "`nested.inner` is required"),
        (["repo": "a", "counts": ["high": "2"]], "`counts.high` must be an integer"),
        (["repo": "a", "colour": "red"], "`colour` is not a known field (known: counts, limit, mine, nested, repo, score, severity, tags)"),
        ("acme/web", "arguments must be an object"),
    ] as [(Value, String)])
    func `Invalid arguments name the field and the rule`(value: Value, message: String) {
        #expect(throws: MCPSchemaViolation(message)) {
            try filters.validate(value)
        }
    }
}
