import Foundation
import Testing
@testable import PullwatchCore

@Suite struct SystemProcessRunnerTests {
    @Test func returnsStatusAndStdout() async throws {
        let output = try await SystemProcessRunner().run(URL(filePath: "/bin/echo"), ["hello"])
        #expect(output == ProcessOutput(status: 0, stdout: "hello\n", stderr: ""))
    }

    /// De timeout gaat pas af als het proces draait en zijn pid schreef (het wordt daarna
    /// `sleep 30` via exec, dus die pid is het proces dat moet stoppen). Zo hangt de test niet af
    /// van hoe snel een drukke runner een proces start of een timer laat aflopen. Van het
    /// aflopen tot de fout mag het hooguit een seconde duren, en het proces moet dan weg zijn.
    @Test func `A timeout terminates the process and names the command`() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appending(path: "pullwatch-timeout-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let timeout = ManualTimeout()
        let runner = SystemProcessRunner(wait: timeout.wait)
        let call = Task {
            try await runner.run(URL(filePath: "/bin/sh"), ["-c", "echo $$ > \"$0\"; exec sleep 30", pidFile.path])
        }

        let pid = try await Self.pid(in: pidFile)
        #expect(kill(pid, 0) == 0, "zonder timeout draait het proces nog")

        let clock = ContinuousClock()
        let fired = clock.now
        timeout.fire()
        await #expect(throws: ProviderError.timeout(command: "sh")) { try await call.value }
        #expect(clock.now - fired < .seconds(1))

        // SIGTERM is verstuurd; het proces is weg zodra de kernel het afhandelt.
        let deadline = clock.now + .seconds(10)
        while kill(pid, 0) == 0 && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }

    /// De pid die het proces in `file` schreef, zodra die er heel staat.
    private static func pid(in file: URL) async throws -> pid_t {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while clock.now < deadline {
            if let data = try? Data(contentsOf: file),
               let pid = pid_t(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try #require(nil as pid_t?, "het proces schreef binnen 10 s geen pid")
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

/// Een timeout die afgaat als de test `fire()` zegt, in plaats van na een tijd op de klok.
private struct ManualTimeout {
    private let fired: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (fired, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    var wait: SystemProcessRunner.Wait {
        let fired = fired
        return {
            for await _ in fired { return }
            // De stream eindigt alleen bij annulering: dan geen timeout.
            throw CancellationError()
        }
    }

    func fire() {
        continuation.yield()
    }
}
