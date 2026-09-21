//
//  ClaudeBridgeServer.swift
//  boringNotch
//
//  Escuta o soquete de domínio Unix onde a ponte entrega os eventos.
//

import Foundation

final class ClaudeBridgeServer {
    static let shared = ClaudeBridgeServer()

    private var listenerFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "claude-notch.bridge-server")
    private var handler: ((ClaudeBridgeEnvelope) -> Void)?

    private init() {}

    /// Sobe o ouvinte. Chamar de novo depois de start é seguro: reinicia limpo.
    func start(onEnvelope: @escaping (ClaudeBridgeEnvelope) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopLocked()
            self.handler = onEnvelope

            let path = ClaudeBridgePaths.socketPath(sandboxed: true)

            // Garante a pasta e remove soquete órfão de uma execução anterior
            // que tenha morrido sem limpar.
            try? FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            unlink(path)

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                NSLog("[claude-notch] não consegui criar o soquete")
                return
            }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let capacity = MemoryLayout.size(ofValue: addr.sun_path)
            guard path.utf8.count < capacity else {
                NSLog("[claude-notch] caminho do soquete longo demais: \(path.utf8.count) bytes")
                close(fd)
                return
            }
            withUnsafeMutablePointer(to: &addr.sun_path) { raw in
                raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                    _ = path.withCString { strncpy(dst, $0, capacity - 1) }
                }
            }

            let bound = withUnsafePointer(to: &addr) { raw in
                raw.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bound == 0, listen(fd, 16) == 0 else {
                NSLog("[claude-notch] não consegui escutar em \(path)")
                close(fd)
                return
            }

            // Só o dono alcança.
            chmod(path, 0o600)

            self.listenerFD = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: self.queue)
            source.setEventHandler { [weak self] in self?.acceptOne() }
            source.resume()
            self.acceptSource = source
            NSLog("[claude-notch] ouvindo em \(path)")
        }
    }

    func stop() {
        queue.async { [weak self] in self?.stopLocked() }
    }

    private func stopLocked() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenerFD >= 0 {
            close(listenerFD)
            listenerFD = -1
        }
        unlink(ClaudeBridgePaths.socketPath(sandboxed: true))
    }

    private func acceptOne() {
        let client = accept(listenerFD, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(client, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(contentsOf: buffer[0..<n])
            // Proteção contra remetente maluco.
            if data.count > 4_000_000 { return }
        }

        guard !data.isEmpty,
              let envelope = try? JSONDecoder().decode(ClaudeBridgeEnvelope.self, from: data)
        else {
            NSLog("[claude-notch] envelope ilegível, descartado")
            return
        }
        guard envelope.v == 1 else { return }

        let handler = self.handler
        DispatchQueue.main.async { handler?(envelope) }
    }
}
