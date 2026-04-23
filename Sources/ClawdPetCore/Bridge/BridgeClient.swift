import Darwin
import Foundation

public enum BridgeClientError: Error {
    case invalidSocketPath
    case socketCreateFailed
    case connectFailed(errno: Int32)
    case encodeFailed
}

public struct BridgeClient {
    public var socketPath: String

    public init(socketPath: String = BridgePath.defaultSocketPath) {
        self.socketPath = socketPath
    }

    public func send(_ envelope: BridgeEnvelope) throws {
        let data = try JSONEncoder.bridgeEncoder.encode(envelope)
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw BridgeClientError.socketCreateFailed
        }
        defer { close(socketFD) }

        var address = try UnixSocketAddress.make(path: socketPath)

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw BridgeClientError.connectFailed(errno: errno)
        }

        var bytes = [UInt8](data)
        bytes.append(UInt8(ascii: "\n"))
        var sent = 0
        while sent < bytes.count {
            let result = bytes.withUnsafeBytes { buffer in
                Darwin.write(socketFD, buffer.baseAddress!.advanced(by: sent), bytes.count - sent)
            }
            guard result > 0 else {
                throw BridgeClientError.connectFailed(errno: errno)
            }
            sent += result
        }
    }
}

extension JSONEncoder {
    static var bridgeEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var bridgeDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
