import Darwin
import Foundation
import Synchronization

/// Een bestandsdescriptor (socket, pipe, stdin of stdout) die nooit een thread blokkeert. Lezen
/// gebeurt in de `readabilityHandler` van `FileHandle`, die pas komt als er iets te lezen is, en
/// komt binnen als `AsyncStream`; schrijven wacht bij een volle buffer op de
/// `writeabilityHandler`. Dat zijn de enige callbacks, hier één keer ingepakt. Elke systeemaanroep
/// gebeurt onder het slot en alleen zolang de descriptor open is, zodat `close()` nooit een
/// nummer sluit dat een andere aanroep nog gebruikt.
package final class NonBlockingDescriptor: Sendable {
    private struct State {
        var descriptor: Int32?
        /// De stroom van `readStream`, zodat `close()` hem kan afsluiten.
        var finishReading: (@Sendable () -> Void)?
        /// Een schrijver die op ruimte in de buffer wacht.
        var writeWaiter: CheckedContinuation<Void, Never>?
    }

    private let state: Mutex<State>
    private let handle: FileHandle

    /// Neemt `descriptor` over (hij wordt gesloten door `close()`) en zet hem op niet-blokkerend.
    package init(adopting descriptor: Int32) throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw MCPSocketError.system("fcntl", errno)
        }
        state = Mutex(State(descriptor: descriptor))
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    }

    deinit {
        close()
    }

    /// Het nummer, voor tests die er een systeemaanroep op doen; -1 als hij dicht is.
    var rawDescriptorForTesting: Int32 {
        state.withLock { $0.descriptor ?? -1 }
    }

    // MARK: - Lezen

    /// Wat een leesstap oplevert.
    package enum ReadStep<Element> {
        case element(Element)
        /// Nu niets meer; wacht op de volgende melding.
        case wouldBlock
        /// Het einde: de andere kant sloot, of een fout.
        case end
    }

    /// Roept `step` aan zodra de descriptor iets te lezen heeft, tot hij `.wouldBlock` geeft, en
    /// levert de elementen. Eindigt bij `.end`, bij `close()` en als de lezer stopt. Eén lezer
    /// per descriptor.
    package func readStream<Element: Sendable>(
        _ step: @escaping @Sendable (Int32) -> ReadStep<Element>
    ) -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream.makeStream(of: Element.self)
        let finish: @Sendable () -> Void = { continuation.finish() }
        let isOpen = state.withLock { state in
            guard state.descriptor != nil else { return false }
            state.finishReading = finish
            return true
        }
        guard isOpen else {
            continuation.finish()
            return stream
        }
        handle.readabilityHandler = { [self] handle in
            while true {
                let next: ReadStep<Element> = state.withLock { state in
                    guard let descriptor = state.descriptor else { return .end }
                    return step(descriptor)
                }
                switch next {
                case .element(let element):
                    continuation.yield(element)
                case .wouldBlock:
                    return
                case .end:
                    handle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
            }
        }
        continuation.onTermination = { [handle] _ in handle.readabilityHandler = nil }
        return stream
    }

    /// Alles wat binnenkomt, in stukken; eindigt als de andere kant sluit.
    package func chunks() -> AsyncStream<Data> {
        readStream { descriptor in
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 { return .element(Data(buffer[..<count])) }
            if count < 0, errno == EAGAIN || errno == EINTR { return .wouldBlock }
            return .end
        }
    }

    // MARK: - Schrijven

    /// Schrijft alles van `data`, ook als dat in delen moet. Gooit als de descriptor dicht is of
    /// de andere kant weg is. Eén schrijver tegelijk: wie meer schrijvers heeft, zet ze in de rij.
    package func write(_ data: Data) async throws {
        var offset = 0
        while offset < data.count {
            let result: Result<Int, MCPSocketError> = data.withUnsafeBytes { buffer in
                state.withLock { state in
                    guard let descriptor = state.descriptor, let base = buffer.baseAddress else { return .failure(.closed) }
                    let written = Darwin.write(descriptor, base + offset, buffer.count - offset)
                    if written >= 0 { return .success(written) }
                    if errno == EAGAIN || errno == EINTR { return .success(0) }
                    return .failure(.system("write", errno))
                }
            }
            let written = try result.get()
            offset += written
            if written == 0 { await writable() }
        }
    }

    /// Wacht tot er weer ruimte is in de buffer, of tot de descriptor dicht gaat.
    private func writable() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let waits = state.withLock { state in
                guard state.descriptor != nil else { return false }
                state.writeWaiter = continuation
                return true
            }
            guard waits else {
                continuation.resume()
                return
            }
            handle.writeabilityHandler = { [self] handle in
                handle.writeabilityHandler = nil
                state.withLock { $0.writeWaiter.take() }?.resume()
            }
        }
    }

    // MARK: - Sluiten

    /// Sluit beide richtingen zonder de descriptor vrij te geven: de lezer krijgt het einde, een
    /// schrijver een fout. Veilig vanuit elke thread, ook vanuit een annulering.
    package func shutdown() {
        state.withLock { state in
            if let descriptor = state.descriptor { _ = Darwin.shutdown(descriptor, SHUT_RDWR) }
        }
    }

    /// Geeft de descriptor vrij, beëindigt de lezer en wekt een wachtende schrijver. Twee keer
    /// sluiten kan geen kwaad.
    package func close() {
        let (descriptor, finishReading, writeWaiter) = state.withLock { state in
            defer {
                state.descriptor = nil
                state.finishReading = nil
                state.writeWaiter = nil
            }
            return (state.descriptor, state.finishReading, state.writeWaiter)
        }
        guard let descriptor else { return }
        handle.readabilityHandler = nil
        handle.writeabilityHandler = nil
        finishReading?()
        writeWaiter?.resume()
        _ = Darwin.close(descriptor)
    }
}
