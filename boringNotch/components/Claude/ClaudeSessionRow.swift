//
//  ClaudeSessionRow.swift
//  boringNotch
//

import SwiftUI

struct ClaudeSessionRow: View {
    let session: ClaudeSession

    @State private var hovering = false

    private var clickable: Bool { ClaudeTerminalFocuser.canFocus(session) }

    private var detail: String {
        if let tool = session.currentTool { return "using \(tool)" }
        if session.subagentCount > 0 { return "\(session.subagentCount) agents" }
        return session.state.label
    }

    var body: some View {
        Button { ClaudeTerminalFocuser.focus(session) } label: { content }
            // Sem .disabled: ele apagaria a linha inteira das sessões sem terminal.
            .buttonStyle(.plain)
            .onHover { hovering = clickable && $0 }
            .help(clickable ? "Go to the terminal running this session" : "")
    }

    private var content: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.state.color)
                .frame(width: 7, height: 7)
                .opacity(session.state == .working ? 0.4 : 1)
                .scaleEffect(session.state == .working ? 1.35 : 1)
                .animation(
                    session.state == .working
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: session.state
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(session.projectName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                if let ctx = session.contextPercentage {
                    Text("ctx \(Int(ctx))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.gray)
                }
                if let cost = session.costUSD {
                    Text(String(format: "$%.2f", cost))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.gray.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(hovering ? 0.08 : 0))
        )
        // Sem isto só o texto recebe o clique; o espaço entre as colunas não.
        .contentShape(Rectangle())
    }
}
