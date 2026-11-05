//
//  ClaudeSession.swift
//  boringNotch
//

import Defaults
import Foundation
import SwiftUI

enum ClaudeSessionState: String {
    case idle
    case working
    case waiting
    case compacting
    case error

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .waiting: return "Waiting for you"
        case .compacting: return "Compacting"
        case .error: return "Error"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .gray
        case .working: return .green
        case .waiting: return .orange
        case .compacting: return .blue
        case .error: return .red
        }
    }

    /// Estados que merecem roubar o notch fechado da animação de rosto.
    var demandsAttention: Bool {
        self == .working || self == .waiting || self == .error
    }

    /// Estados em que o Claude está esperando VOCÊ. Bem mais estreito que
    /// `demandsAttention`: só estes justificam tomar o notch da música, porque
    /// "trabalhando" é o estado comum e tomaria a música quase o tempo todo.
    var needsUser: Bool {
        self == .waiting || self == .error
    }
}

struct ClaudeSession: Identifiable, Equatable {
    let id: String              // session_id
    var projectPath: String?    // cwd
    var state: ClaudeSessionState = .idle
    var currentTool: String?
    var subagentCount: Int = 0
    var modelName: String?
    var contextPercentage: Double?
    var costUSD: Double?
    var lastEventAt: Date = .now
    /// Onde a sessão roda; nil quando a ponte é antiga ou não descobriu.
    var terminal: ClaudeTerminalInfo?
    /// Processo do Claude Code dono da sessão; nil quando a ponte é antiga.
    var process: ClaudeProcessIdentity?

    /// Só o último componente do caminho — é o que cabe no notch.
    var projectName: String {
        guard let p = projectPath, !p.isEmpty else { return "session" }
        return (p as NSString).lastPathComponent
    }

    /// Uma sondagem que não achou nada não pode apagar uma que achou.
    mutating func adoptTerminal(_ info: ClaudeTerminalInfo?) {
        guard let info else { return }
        if info.background {
            // A barra de status de uma sessão de fundo vem sem título (só os
            // hooks o trazem): fica o último conhecido.
            let known = terminal?.background == true ? terminal?.title : nil
            terminal = ClaudeTerminalInfo(
                bundleId: nil, tty: nil, insideTmux: false,
                background: true, title: info.title ?? known
            )
            return
        }
        guard info.bundleId != nil || info.tty != nil else { return }
        terminal = info
    }

    /// A raiz do projeto, não a pasta atual: o Claude anda por subpastas
    /// (`cd mobile`) e o notch passava a mostrar "mobile".
    mutating func updateProjectPath(cwd: String?, transcriptPath: String?) {
        guard let cwd, !cwd.isEmpty else { return }
        if let root = Self.projectRoot(cwd: cwd, transcriptPath: transcriptPath) {
            projectPath = root
        } else if projectPath == nil {
            // Sem como achar a raiz, a pasta atual ainda é melhor que nada,
            // mas nunca substitui uma raiz já conhecida.
            projectPath = cwd
        }
    }

    /// O Claude Code guarda a conversa em ~/.claude/projects/<projeto>/, com o
    /// caminho do projeto codificado: tudo que não é letra ou número vira "-".
    /// A raiz é a pasta, de cwd para cima, cujo código bate com esse nome.
    static func projectRoot(cwd: String, transcriptPath: String?) -> String? {
        guard let transcriptPath else { return nil }
        let parts = transcriptPath.split(separator: "/").map(String.init)
        // A pasta logo depois de "projects" (subagentes guardam a conversa
        // mais fundo, então não dá para usar só a pasta do arquivo).
        guard let i = parts.firstIndex(of: "projects"), i + 1 < parts.count else { return nil }
        let encoded = parts[i + 1]

        var path = cwd
        while path.count > 1 {
            if encodedProjectName(path) == encoded { return path }
            path = (path as NSString).deletingLastPathComponent
        }
        return nil
    }

    private static func encodedProjectName(_ path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    /// `claude --resume` retoma a mesma sessão em outro processo: vale o mais novo.
    mutating func adoptProcess(_ pid: Int32?) {
        guard let pid, process?.pid != pid,
              let identity = ClaudeProcessIdentity(pid: pid) else { return }
        process = identity
    }

    func isStale(now: Date, staleAfterMinutes: Int) -> Bool {
        now.timeIntervalSince(lastEventAt) > Double(staleAfterMinutes) * 60
    }
}

/// Um processo pelo pid E pela hora em que nasceu: o sistema reaproveita pids,
/// e um processo novo com o número do antigo não pode manter a sessão viva.
struct ClaudeProcessIdentity: Equatable {
    let pid: pid_t
    let startedAt: Int64   // microssegundos desde 1970

    init?(pid: pid_t) {
        guard pid > 1, let start = Self.startTime(of: pid) else { return nil }
        self.pid = pid
        self.startedAt = start
    }

    var isAlive: Bool { Self.startTime(of: pid) == startedAt }

    /// nil se o processo não existe ou já morreu (zumbi esperando o pai).
    /// Funciona dentro do sandbox: consultar processos do mesmo usuário é permitido.
    private static func startTime(of pid: pid_t) -> Int64? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0,
              info.kp_proc.p_stat != SZOMB
        else { return nil }
        let t = info.kp_proc.p_un.__p_starttime
        return Int64(t.tv_sec) * 1_000_000 + Int64(t.tv_usec)
    }
}

/// Uma leitura de uma janela de limite (5 horas ou 7 dias).
struct ClaudeLimitWindow: Equatable {
    var percentage: Double
    var resetsAt: Date?
    /// Instante do envelope que trouxe a leitura, em milissegundos.
    var sentAt: Int64

    /// Dois horários de reset mais próximos que isto são a mesma janela.
    static let sameWindowTolerance: TimeInterval = 60

    /// Cada sessão do Claude Code repete na barra de status o número da ÚLTIMA
    /// resposta que ELA recebeu. Uma sessão parada há uma hora continua
    /// mandando o valor velho, com carimbo de envio novo — e "o mais recente
    /// vence" fazia o medidor descer e subir conforme a sessão que falava.
    /// O horário de reset é o que diz de que janela é a leitura; dentro da
    /// mesma janela o uso só cresce.
    func merged(with new: ClaudeLimitWindow) -> ClaudeLimitWindow {
        let mine: Date, theirs: Date
        switch (resetsAt, new.resetsAt) {
        case let (m?, t?):
            (mine, theirs) = (m, t)
        case (nil, nil):
            // Nenhum dos dois diz a janela: resta confiar no mais recente.
            return new.sentAt >= sentAt ? new : self
        case (nil, _?):
            return new          // a nova pelo menos sabe quando vira
        case (_?, nil):
            return self         // sem janela não dá para saber se é velha
        }
        let tolerance = Self.sameWindowTolerance
        if theirs.timeIntervalSince(mine) > tolerance { return new }   // janela nova
        if mine.timeIntervalSince(theirs) > tolerance { return self }  // janela que já passou
        return ClaudeLimitWindow(
            percentage: max(percentage, new.percentage),
            resetsAt: max(mine, theirs),
            sentAt: max(sentAt, new.sentAt)
        )
    }

    /// Depois do reset, o que foi usado na janela velha não conta mais.
    func isExpired(now: Date) -> Bool {
        resetsAt.map { $0 <= now } ?? false
    }

    /// O que mostrar agora: 0 a 100, e zero se a janela já virou.
    func displayedPercentage(now: Date) -> Double {
        isExpired(now: now) ? 0 : min(max(percentage, 0), 100)
    }

    /// Cor do medidor conforme os limiares das preferências; cinza sem dados.
    static func tint(for percentage: Double?) -> Color {
        guard let p = percentage else { return .gray }
        if p >= Defaults[.claudeLimitCriticalThreshold] { return .red }
        if p >= Defaults[.claudeLimitWarningThreshold] { return .orange }
        return .green
    }
}

struct ClaudeAccountLimits: Equatable {
    var fiveHour: ClaudeLimitWindow?
    var sevenDay: ClaudeLimitWindow?

    var isEmpty: Bool { fiveHour == nil && sevenDay == nil }
}
