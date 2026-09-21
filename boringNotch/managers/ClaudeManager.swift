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
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
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
            applyHook(data)
        case .statusline:
            applyStatusLine(data, sentAt: envelope.sentAt)
        }
        publish()
    }

    private func applyHook(_ data: Data) {
        guard let p = try? ClaudeBridgeContract.decoder()
            .decode(ClaudeHookPayload.self, from: data),
              let id = p.sessionId, let event = p.hookEventName
        else { return }

        if event == "SessionEnd" {
            byID.removeValue(forKey: id)
            return
        }

        var s = byID[id] ?? ClaudeSession(id: id)
        s.lastEventAt = .now
        if let cwd = p.cwd { s.projectPath = cwd }

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

    private func applyStatusLine(_ data: Data, sentAt: Int64) {
        guard let p = try? ClaudeBridgeContract.decoder()
            .decode(ClaudeStatusLinePayload.self, from: data) else { return }

        if let id = p.sessionId {
            var s = byID[id] ?? ClaudeSession(id: id)
            s.lastEventAt = .now
            if let cwd = p.cwd { s.projectPath = cwd }
            s.modelName = p.model?.displayName
            s.contextPercentage = p.contextWindow?.usedPercentage
            s.costUSD = p.cost?.totalCostUsd
            byID[id] = s
        }

        // Limites são da conta inteira. Um envelope atrasado nunca sobrescreve
        // um número mais novo vindo de outra sessão.
        guard sentAt >= limits.sourceSentAt, let r = p.rateLimits else { return }
        var l = limits
        l.sourceSentAt = sentAt
        if let f = r.fiveHour {
            l.fiveHourPercentage = f.usedPercentage
            l.fiveHourResetsAt = f.resetsAt.map { Date(timeIntervalSince1970: $0) }
        }
        if let w = r.sevenDay {
            l.sevenDayPercentage = w.usedPercentage
            l.sevenDayResetsAt = w.resetsAt.map { Date(timeIntervalSince1970: $0) }
        }
        limits = l
    }

    // MARK: Zumbis

    private func sweepStaleSessions() {
        let now = Date()
        let removeAfter = Double(Defaults[.claudeRemoveAfterMinutes]) * 60
        let before = byID.count
        byID = byID.filter { now.timeIntervalSince($0.value.lastEventAt) < removeAfter }
        if byID.count != before { publish() }
    }

    private func publish() {
        let now = Date()
        let staleAfter = Defaults[.claudeStaleAfterMinutes]
        sessions = byID.values
            .sorted { $0.lastEventAt > $1.lastEventAt }
            .map { s in
                var s = s
                // Sessão muda há tempo demais aparece apagada, como parada.
                if s.isStale(now: now, staleAfterMinutes: staleAfter), s.state != .error {
                    s.state = .idle
                }
                return s
            }
    }
}
