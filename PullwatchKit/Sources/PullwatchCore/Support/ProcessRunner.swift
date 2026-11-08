public import Foundation
import Synchronization

public struct ProcessOutput: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol ProcessRunner: Sendable {
    func run(_ executable: URL, _ arguments: [String]) async throws -> ProcessOutput
}

public struct SystemProcessRunner: ProcessRunner {
    /// Wacht de timeout af; gooit bij annulering. Tests geven hun eigen, zodat de timeout afgaat
    /// wanneer de test dat zegt in plaats van na een tijd op de klok.
    typealias Wait = @Sendable () async throws -> Void

    private let wait: Wait

    public init(timeout: Duration = .seconds(20)) {
        self.wait = { try await Task.sleep(for: timeout) }
    }

    init(wait: @escaping Wait) {
        self.wait = wait
    }

    public func run(_ executable: URL, _ arguments: [String]) async throws -> ProcessOutput {
        let run = ProcessRun(executable: executable, arguments: arguments, wait: wait)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                run.start(continuation)
            }
        } onCancel: {
            run.stop(.failure(CancellationError()))
        }
    }
}

/// Eén uitvoering van een proces. De continuation wordt precies één keer hervat:
/// bij normale afronding, timeout of annulering. Alle toestand zit achter `state`.
private final class ProcessRun: Sendable {
    private struct State {
        var continuation: CheckedContinuation<ProcessOutput, any Error>?
        var pendingResult: Result<ProcessOutput, any Error>?
        var finished = false
        var timer: Task<Void, Never>?
    }

    private let state = Mutex(State())
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let executable: URL
    private let arguments: [String]
    private let wait: SystemProcessRunner.Wait

    init(executable: URL, arguments: [String], wait: @escaping SystemProcessRunner.Wait) {
        self.executable = executable
        self.arguments = arguments
        self.wait = wait
    }

    func start(_ continuation: CheckedContinuation<ProcessOutput, any Error>) {
        state.withLock { locked in
            if let pendingResult = locked.pendingResult {
                continuation.resume(with: pendingResult)
                return
            }
            locked.continuation = continuation

            process.executableURL = executable
            process.arguments = arguments
            // GUI-apps erven geen shell-PATH; az/gh hebben zelf ook tools uit Homebrew nodig.
            var environment = ProcessInfo.processInfo.environment
            let inherited = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            environment["PATH"] = (CLILocator.defaultSearchPaths + inherited).joined(separator: ":")
            process.environment = environment
            // Een CLI die op stdin wacht (interactieve prompt) mag niet blokkeren.
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            // De exitcode wacht in de stream: terminationHandler kan op een andere thread vuren
            // voordat start() klaar is.
            let (exits, exit) = AsyncStream.makeStream(of: Int32.self, bufferingPolicy: .bufferingNewest(1))
            process.terminationHandler = { finishedProcess in
                exit.yield(finishedProcess.terminationStatus)
                exit.finish()
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                Self.finish(&locked, .failure(error))
                return
            }

            // Pipes tegelijk leegtrekken, anders blokkeert een grote output het proces. De
            // uitvoer is compleet als het proces klaar is en beide pipes leeg zijn.
            let stdout = Self.readToEnd(stdoutPipe.fileHandleForReading)
            let stderr = Self.readToEnd(stderrPipe.fileHandleForReading)
            Task { [self] in
                var status: Int32 = 0
                for await code in exits { status = code }
                let output = ProcessOutput(
                    status: status,
                    stdout: String(decoding: await stdout.value, as: UTF8.self),
                    stderr: String(decoding: await stderr.value, as: UTF8.self)
                )
                state.withLock { Self.finish(&$0, .success(output)) }
            }

            locked.timer = Task { [self] in
                do {
                    try await wait()
                } catch {
                    return
                }
                stop(.failure(ProviderError.timeout(command: executable.lastPathComponent)))
            }
        }
    }

    /// Beëindigt het proces (indien nog actief) en hervat met `result`, tenzij al afgerond.
    func stop(_ result: Result<ProcessOutput, any Error>) {
        state.withLock { locked in
            guard !locked.finished else { return }
            if process.isRunning {
                process.terminate()
            }
            Self.finish(&locked, result)
        }
    }

    /// Alles tot het einde van de pipe, zonder een thread te blokkeren: `readabilityHandler`
    /// geeft elk stuk dat binnenkomt, en een leeg stuk is het einde.
    private static func readToEnd(_ handle: FileHandle) -> Task<Data, Never> {
        let (chunks, chunk) = AsyncStream.makeStream(of: Data.self)
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                chunk.finish()
            } else {
                chunk.yield(data)
            }
        }
        return Task {
            var data = Data()
            for await part in chunks {
                data.append(part)
            }
            return data
        }
    }

    /// Alleen binnen `state.withLock` aanroepen.
    private static func finish(_ locked: inout State, _ result: Result<ProcessOutput, any Error>) {
        guard !locked.finished else { return }
        locked.finished = true
        locked.timer?.cancel()
        locked.timer = nil
        if let continuation = locked.continuation {
            continuation.resume(with: result)
            locked.continuation = nil
        } else {
            locked.pendingResult = result
        }
    }
}

public struct CLILocator: Sendable {
    public static let defaultSearchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    private let searchPaths: [String]
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        searchPaths: [String] = CLILocator.defaultSearchPaths,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.searchPaths = searchPaths
        self.isExecutable = isExecutable
    }

    public func locate(_ name: String) -> URL? {
        searchPaths
            .map { "\($0)/\(name)" }
            .first(where: isExecutable)
            .map { URL(filePath: $0) }
    }
}
