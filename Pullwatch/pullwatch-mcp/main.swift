import Darwin
import Foundation
import PullwatchMCP

// pullwatch-mcp: de helper die een coding agent met stdio start
// (`claude mcp add --scope user --transport stdio pullwatch -- /Applications/Pullwatch.app/Contents/Helpers/pullwatch-mcp`).
// Alle logica staat in `MCPBridge` (PullwatchMCP, getest); hier alleen het aansluiten.

// Een agent die stdout sluit, geeft een schrijffout in plaats van een stop zonder opruimen.
signal(SIGPIPE, SIG_IGN)

let helper = Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])
let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
let launcher = WorkspaceLauncher(
    app: PullwatchAppLocation.appBundle(forHelperAt: helper),
    arguments: PullwatchAppLocation.launchArguments(from: arguments)
)
await MCPBridge.standard(launcher: launcher).runOnStandardIO()
exit(0)
