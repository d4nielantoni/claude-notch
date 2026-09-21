//
//  ClaudeBridgeClient.swift
//  ClaudeNotchBridge
//

import Foundation

enum ClaudeBridgeClient {
    private static let timeoutMicroseconds: Int32 = 250_000

    /// Envia o envelope e devolve silenciosamente em qualquer falha.
    /// Nunca lança, nunca escreve em stderr: travar o Claude Code é inaceitável.
    static func send(_ envelope: ClaudeBridgeEnvelope) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        // Sem isto, um write() numa conexão que o app já fechou mata este
        // processo com SIGPIPE (saída 141) — e a ponte jamais pode falhar
        // de um jeito que o Claude Code perceba.
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: 0, tv_usec: timeoutMicroseconds)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let path = ClaudeBridgePaths.socketPath(sandboxed: false)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else { return }

        withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                _ = path.withCString { strncpy(dst, $0, capacity - 1) }
            }
        }

        let connected = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return }

        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var sent = 0
            while sent < buffer.count {
                let n = write(fd, base.advanced(by: sent), buffer.count - sent)
                if n <= 0 { return }
                sent += n
            }
        }
        // Fecha a escrita para o app enxergar o fim da mensagem.
        shutdown(fd, SHUT_WR)
    }
}
