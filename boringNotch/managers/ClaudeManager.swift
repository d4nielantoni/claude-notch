//
//  ClaudeManager.swift
//  boringNotch
//
//  Registro em memória das sessões vivas do Claude Code e dos limites da conta.
//

import Combine
import Defaults
import Foundation

final class ClaudeManager: ObservableObject {
    static let shared = ClaudeManager()

    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var limits = ClaudeAccountLimits()

    private var byID: [String: ClaudeSession] = [:]
    private var sweepTimer: Timer?

    private init() {}

    // MARK: Ciclo de vida

    func start() {
        ClaudeBridgeServer.shared.start { [weak self] envelope in
            self?.handle(envelope)
        }
        // Curto porque é ele que tira do notch a sessão cuja aba foi fechada.
        // Custa uma consulta ao sistema por sessão.
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.sweepStaleSessions()
        }
    }

    func stop() {
        ClaudeBridgeServer.shared.stop()
        sweepTimer?.invalidate()
        sweepTimer = nil
        byID.removeAll()
        publish()
    }

    /// A sessão que o notch fechado mostra: prioriza quem pede atenção,
    /// e desempata pelo evento mais recente.
    var highlighted: ClaudeSession? {
        sessions.first { $0.state.demandsAttention } ?? sessions.first
    }

    var hasAttention: Bool {
        sessions.contains { $0.state.demandsAttention }
    }

    /// Alguma sessão parada esperando você. É o único caso que interrompe a música.
    var needsUser: Bool {
        sessions.contains { $0.state.needsUser }
    }

    // MARK: Entrada

    private func handle(_ envelope: ClaudeBridgeEnvelope) {
        guard let data = envelope.payload.data(using: .utf8) else { return }
        switch envelope.kind {
        case .hook:
            applyHook(data, envelope: envelope)
        case .statusline:
            applyStatusLine(data, envelope: envelope)
        }
        publish()
    }

    private func applyHook(_ data: Data, envelope: ClaudeBridgeEnvelope) {
        guard let p = try? ClaudeBridgeContract.decoder()
            .decode(ClaudeHookPayload.self, from: data),
              let id = p.sessionId, let event = p.hookEventName
        else { return }

        if event == "SessionEnd" {
            byID.removeValue(forKey: id)
            return
        }

        guard var s = session(id, claudePid: envelope.claudePid) else { return }
        s.lastEventAt = .now
        s.updateProjectPath(cwd: p.cwd, transcriptPath: p.transcriptPath)
        s.adoptTerminal(envelope.terminal)
        s.adoptProcess(envelope.claudePid)

        switch event {
        case "SessionStart":          s.state = .idle
        case "UserPromptSubmit":      s.state = .working
        case "PreToolUse":            s.state = .working; s.currentTool = p.toolName
        case "PostToolUse",
             "PostToolUseFailure":    s.state = .working; s.currentTool = nil
        case "SubagentStart":         s.subagentCount += 1
        case "SubagentStop":          s.subagentCount = max(0, s.subagentCount - 1)
        case "PreCompact":            s.state = .compacting
        case "PostCompact":           s.state = .working
        case "Notification":          s.state = .waiting
        case "Stop":                  s.state = .idle; s.currentTool = nil
        case "StopFailure":           s.state = .error; s.currentTool = nil
        default:                      break
        }
        byID[id] = s
    }

    private func applyStatusLine(_ data: Data, envelope: ClaudeBridgeEnvelope) {
        guard let p = try? ClaudeBridgeContract.decoder()
            .decode(ClaudeStatusLinePayload.self, from: data) else { return }

        if let id = p.sessionId, var s = session(id, claudePid: envelope.claudePid) {
            s.lastEventAt = .now
            s.updateProjectPath(cwd: p.cwd, transcriptPath: p.transcriptPath)
            s.adoptTerminal(envelope.terminal)
            s.adoptProcess(envelope.claudePid)
            s.modelName = p.model?.displayName
            s.contextPercentage = p.contextWindow?.usedPercentage
            s.costUSD = p.cost?.totalCostUsd
            byID[id] = s
        }

        // Limites são da conta inteira, e cada janela se resolve sozinha:
        // uma sessão pode trazer o 5h fresco e o 7d de uma resposta antiga.
        guard let r = p.rateLimits else { return }
        var l = limits
        l.fiveHour = Self.merge(l.fiveHour, r.fiveHour, sentAt: envelope.sentAt)
        l.sevenDay = Self.merge(l.sevenDay, r.sevenDay, sentAt: envelope.sentAt)
        limits = l
    }

    private static func merge(
        _ current: ClaudeLimitWindow?,
        _ reading: ClaudeStatusLinePayload.RateWindow?,
        sentAt: Int64
    ) -> ClaudeLimitWindow? {
        guard let pct = reading?.usedPercentage else { return current }
        let incoming = ClaudeLimitWindow(
            percentage: pct,
            resetsAt: reading?.resetsAt.map { Date(timeIntervalSince1970: $0) },
            sentAt: sentAt
        )
        return current?.merged(with: incoming) ?? incoming
    }

    /// A sessão que já existe, ou uma nova. Um envelope atrasado de um
    /// processo que já morreu não ressuscita a sessão que a varredura tirou.
    private func session(_ id: String, claudePid: Int32?) -> ClaudeSession? {
        if let existing = byID[id] { return existing }
        if let pid = claudePid, ClaudeProcessIdentity(pid: pid) == nil { return nil }
        return ClaudeSession(id: id)
    }

    // MARK: Zumbis

    private func sweepStaleSessions() {
        let now = Date()
        let removeAfter = Double(Defaults[.claudeRemoveAfterMinutes]) * 60
        byID = byID.filter { _, s in
            // Aba fechada mata o Claude sem SessionEnd: o processo é a prova.
            if let process = s.process, !process.isAlive { return false }
            return now.timeIntervalSince(s.lastEventAt) < removeAfter
        }
        // Sempre: além das remoções, o tempo apaga sessões paradas (e esconde
        // as de fundo) sem que chegue evento nenhum.
        publish()
    }

    private func publish() {
        let now = Date()
        let staleAfter = Defaults[.claudeStaleAfterMinutes]
        let visible = byID.values
            .sorted { $0.lastEventAt > $1.lastEventAt }
            .map { s in
                var s = s
                // Sessão muda há tempo demais aparece apagada, como parada.
                if s.isStale(now: now, staleAfterMinutes: staleAfter), s.state != .error {
                    s.state = .idle
                }
                return s
            }
            // Sessão de fundo sobrevive à aba fechada e fica parada por horas.
            // Só aparece trabalhando ou esperando você; segue registrada, e
            // volta sozinha quando fizer algo.
            .filter { !($0.terminal?.background == true && $0.state == .idle) }
        // A varredura chama isto a cada 5 s; sem mudança, nada de redesenhar.
        if visible != sessions { sessions = visible }
    }
}
