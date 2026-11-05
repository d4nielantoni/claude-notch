//
//  ClaudeTerminalProbe.swift
//  ClaudeNotchBridge
//
//  Descobre em que terminal o Claude Code está rodando. Nunca falha: na dúvida,
//  devolve campos vazios e o app simplesmente não oferece o atalho.
//

import Darwin
import Foundation

enum ClaudeTerminalProbe {
    /// Limite de saltos subindo pela árvore de processos. A ponte costuma estar
    /// a um ou dois níveis do processo do Claude, que é quem tem a tty.
    private static let maxAncestors = 8
    /// NODEV do C ((dev_t)-1): a macro não chega ao Swift.
    private static let noDevice: dev_t = -1
    /// O Claude Code regrava o título a cada poucas mensagens, sempre perto do
    /// fim da conversa; ler só a cauda mantém a ponte rápida em arquivos de 60 MB.
    private static let titleTailBytes = 1_048_576

    /// `transcriptPath` só vem nos hooks; sem ele a sessão de fundo vai sem
    /// título, e o app mantém o último que conhecia.
    static func current(transcriptPath: String?, claudePid: Int32?) -> ClaudeTerminalInfo {
        let env = ProcessInfo.processInfo.environment
        if env["CLAUDE_CODE_SESSION_KIND"] == "bg" || isBackgroundProcess(claudePid) {
            // O ambiente e a tty aqui são do processo de fundo, não da aba que
            // exibe a sessão; mandá-los só levaria o clique ao lugar errado.
            return ClaudeTerminalInfo(
                bundleId: nil, tty: nil, insideTmux: false,
                background: true,
                title: transcriptPath.flatMap(sessionTitle(transcriptPath:))
            )
        }
        return ClaudeTerminalInfo(
            bundleId: env["__CFBundleIdentifier"],
            tty: controllingTTY(),
            insideTmux: env["TMUX"] != nil
        )
    }

    /// O Claude Code dispara hooks fora da sessão do terminal (sem tty de
    /// controle), então a ponte sobe pelos pais até achar quem tenha uma.
    private static func controllingTTY() -> String? {
        var pid = getpid()
        for _ in 0..<maxAncestors {
            guard pid > 1, let info = processInfo(pid) else { return nil }
            let dev = info.kp_eproc.e_tdev
            if dev != noDevice, let name = devname(dev, S_IFCHR) {
                return String(cString: name)
            }
            pid = info.kp_eproc.e_ppid
        }
        return nil
    }

    private static func processInfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        return info
    }

    // MARK: Sessão de fundo

    /// O ambiente do processo de fundo tem CLAUDE_CODE_SESSION_KIND=bg, mas o
    /// Claude Code não o repassa garantidamente aos hooks. O jeito de nascer
    /// é estável: o processo da sessão roda como `bg-spare`/`--bg-…`, filho de
    /// um `bg-pty-host`.
    private static func isBackgroundProcess(_ pid: Int32?) -> Bool {
        guard let pid, pid > 1 else { return false }
        if arguments(of: pid).dropFirst().contains(where: isBackgroundArgument) { return true }
        guard let parent = processInfo(pid)?.kp_eproc.e_ppid, parent > 1 else { return false }
        return arguments(of: parent).dropFirst().contains(where: isBackgroundArgument)
    }

    private static func isBackgroundArgument(_ arg: String) -> Bool {
        arg.hasPrefix("--bg-") || arg == "bg-spare" || arg == "bg-pty-host"
    }

    /// argv de outro processo do mesmo usuário (KERN_PROCARGS2: argc, caminho
    /// do executável, preenchimento com zeros, depois os argumentos).
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return []
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var i = MemoryLayout<Int32>.size
        while i < size, buffer[i] != 0 { i += 1 }   // caminho do executável
        while i < size, buffer[i] == 0 { i += 1 }   // preenchimento

        var args: [String] = []
        while i < size, args.count < argc {
            let start = i
            while i < size, buffer[i] != 0 { i += 1 }
            args.append(String(decoding: buffer[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    // MARK: Título da conversa

    private struct TitleEntry: Decodable {
        let type: String?
        let customTitle: String?
        let aiTitle: String?
    }

    /// Título que o usuário deu (/rename) vence o gerado pelo Claude, como na aba.
    private static func sessionTitle(transcriptPath: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(titleTailBytes) ? end - UInt64(titleTailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd() else { return nil }

        let marker = Data("-title\"".utf8)
        var latestAITitle: String?
        // A primeira linha pode ter vindo cortada pela metade; o JSON dela
        // simplesmente não decodifica e é ignorado.
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            // Linhas de título são curtas; as de conteúdo nem chegam ao JSON.
            guard line.count < 4096, line.range(of: marker) != nil,
                  let entry = try? JSONDecoder().decode(TitleEntry.self, from: Data(line))
            else { continue }
            if entry.type == "custom-title", let t = entry.customTitle, !t.isEmpty {
                return t
            }
            if latestAITitle == nil, entry.type == "ai-title", let t = entry.aiTitle, !t.isEmpty {
                latestAITitle = t
            }
        }
        return latestAITitle
    }
}
