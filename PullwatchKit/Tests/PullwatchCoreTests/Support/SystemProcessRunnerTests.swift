import Foundation
import Testing
@testable import PullwatchCore

@Suite struct SystemProcessRunnerTests {
    @Test func returnsStatusAndStdout() async throws {
        let output = try await SystemProcessRunner().run(URL(filePath: "/bin/echo"), ["hello"])
        #expect(output == ProcessOutput(status: 0, stdout: "hello\n", stderr: ""))
    }

    /// Het proces schrijft zijn pid en wordt dan `sleep` (exec), zodat die pid het proces is dat
    /// moet stoppen. De tijd telt alleen dat er niet op het proces gewacht wordt: naast bijna
    /// duizend parallelle tests komt een timer van 300 ms op een CI-runner met drie kernen
    /// soms pas na ruim twee seconden aan de beurt.
    @Test func `A timeout terminates the process and names the command`() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appending(path: "pullwatch-timeout-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let runner = SystemProcessRunner(timeout: .milliseconds(300))
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: ProviderError.timeout(command: "sh")) {
            try await runner.run(URL(filePath: "/bin/sh"), ["-c", "echo $$ > \"$0\"; exec sleep 30", pidFile.path])
        }
        #expect(clock.now - start < .seconds(10))

        let pid = try #require(pid_t(String(decoding: try Data(contentsOf: pidFile), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        // SIGTERM is verstuurd; het proces is weg zodra de kernel het afhandelt.
        let deadline = clock.now + .seconds(10)
        while kill(pid, 0) == 0 && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }

    @Test func drainsLargeOutputWithoutDeadlock() async throws {
        let output = try await SystemProcessRunner().run(
            URL(filePath: "/bin/sh"),
            ["-c", "head -c 200000 /dev/zero | tr '\\0' a"]
        )
        #expect(output.stdout.utf8.count == 200_000)
    }

    @Test func cancellationTerminatesProcess() async {
        let runner = SystemProcessRunner(timeout: .seconds(20))
        let task = Task { try await runner.run(URL(filePath: "/bin/sh"), ["-c", "sleep 5"]) }
        try? await Task.sleep(for: .milliseconds(100))
        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.now - start < .seconds(1))
    }
}
