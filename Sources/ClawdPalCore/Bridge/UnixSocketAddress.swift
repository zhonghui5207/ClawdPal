import Darwin
import Foundation

enum UnixSocketAddress {
    static func make(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            throw POSIXError(.ENAMETOOLONG)
        }

        path.withCString { pointer in
            withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
                rawBuffer.initializeMemory(as: CChar.self, repeating: 0)
                guard let baseAddress = rawBuffer.baseAddress else { return }
                strncpy(baseAddress.assumingMemoryBound(to: CChar.self), pointer, capacity - 1)
            }
        }

        return address
    }
}
