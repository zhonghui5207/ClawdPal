import Darwin
import Foundation

public final class BridgeServer {
    public typealias EventHandler = @Sendable (BridgeEnvelope) -> Void

    private let socketPath: String
    private let queue = DispatchQueue(label: "clawdpet.bridge.server", qos: .userInitiated)
    private var socketFD: Int32 = -1
    private var isRunning = false

    public init(socketPath: String = BridgePath.defaultSocketPath) {
        self.socketPath = socketPath
    }

    deinit {
        stop()
    }

    public func start(onEvent: @escaping EventHandler) throws {
        guard !isRunning else { return }
        try BridgePath.ensureParentDirectory(for: socketPath)
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        var address = try UnixSocketAddress.make(path: socketPath)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let error = errno
            close(fd)
            throw POSIXError(.init(rawValue: error) ?? .EIO)
        }

        guard listen(fd, 8) == 0 else {
            let error = errno
            close(fd)
            throw POSIXError(.init(rawValue: error) ?? .EIO)
        }

        socketFD = fd
        isRunning = true

        queue.async { [weak self] in
            self?.acceptLoop(onEvent: onEvent)
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        if socketFD >= 0 {
            shutdown(socketFD, SHUT_RDWR)
            close(socketFD)
            socketFD = -1
        }
        unlink(socketPath)
    }

    private func acceptLoop(onEvent: @escaping EventHandler) {
        while isRunning {
            let clientFD = accept(socketFD, nil, nil)
            guard clientFD >= 0 else {
                if isRunning {
                    continue
                }
                break
            }
            handleClient(clientFD, onEvent: onEvent)
        }
    }

    private func handleClient(_ clientFD: Int32, onEvent: EventHandler) {
        defer { close(clientFD) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(clientFD, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        guard !data.isEmpty else { return }
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let envelope = try? JSONDecoder.bridgeDecoder.decode(BridgeEnvelope.self, from: Data(line)) else {
                continue
            }
            onEvent(envelope)
        }
    }
}
