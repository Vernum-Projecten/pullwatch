/// De tools die Pullwatch aan agents geeft, allemaal alleen lezend, over één `MCPDataSource`.
/// De app bouwt er het register mee (`MCPToolRegistry(PullwatchMCPTools.all(dataSource:))`).
public enum PullwatchMCPTools {
    /// Elke tool, in de volgorde waarin `tools/list` ze toont: eerst de status, dan PR's en tags,
    /// dan repo's en hun bevindingen.
    public static func all(dataSource: any MCPDataSource) -> [MCPTool] {
        [
            GetStatusTool.make(dataSource),
            ListPullRequestsTool.make(dataSource),
            GetPullRequestTool.make(dataSource),
            ListTagsTool.make(dataSource),
            ListRepositoriesTool.make(dataSource),
            GetRepositoryReportTool.make(dataSource),
            ListVulnerabilitiesTool.make(dataSource),
            ListPackagesTool.make(dataSource),
            ExplainUpdateTool.make(dataSource),
            GetAgentBriefTool.make(dataSource),
        ]
    }

    /// Het register met elke tool. Kan alleen falen door een fout in deze code (een ongeldige
    /// naam of schema); de tests bewijzen dat dat niet zo is.
    public static func registry(dataSource: any MCPDataSource, limits: MCPLimits = .standard) throws(MCPToolRegistry.InvalidTool) -> MCPToolRegistry {
        try MCPToolRegistry(all(dataSource: dataSource), limits: limits)
    }
}
