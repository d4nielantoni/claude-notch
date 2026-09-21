//
//  ClaudeLiveActivity.swift
//  boringNotch
//
//  O que aparece no notch fechado: o asterisco do Claude se mexendo enquanto
//  ele trabalha, e um anel fino que enche conforme o limite de 5 horas queima.
//
//  A caixa do notch NÃO pode crescer por causa disto. Tudo aqui se amarra à
//  altura do notch e flui ao redor dele, como as outras atividades ao vivo —
//  num monitor externo, onde o notch é desenhado e não físico, qualquer folga
//  a mais fica evidente.
//

import Defaults
import SwiftUI

/// Laranja da marca do Claude, o mesmo do asterisco no terminal.
private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

/// O asterisco que pisca no Claude Code. Os glifos são os mesmos da CLI, na
/// mesma ordem: ele parece "respirar" em vez de girar.
struct ClaudeAsterisk: View {
    let working: Bool
    let size: CGFloat

    private static let glyphs = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    @State private var phase = 0

    private var glyph: String {
        // Parado, fica no asterisco cheio: presença sem agitação.
        working ? Self.glyphs[phase % Self.glyphs.count] : "✳"
    }

    var body: some View {
        Text(glyph)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(claudeOrange)
            .frame(width: size * 1.2, height: size * 1.2)
            .onReceive(timer) { _ in
                // Só avança quando há trabalho: parado, nada pisca à toa.
                guard working else { return }
                phase &+= 1
            }
    }
}

struct ClaudeLiveActivity: View {
    /// A altura vem de fora de propósito: quem manda no tamanho é o notch,
    /// não esta view. Não existe parâmetro de largura — a view se mantém
    /// estreita e cabe DENTRO da caixa, em vez de esticá-la.
    let notchHeight: CGFloat

    @ObservedObject var claude = ClaudeManager.shared

    private var session: ClaudeSession? { claude.highlighted }
    private var working: Bool { session?.state == .working }

    private var ringValue: Double {
        min(max(claude.limits.fiveHourPercentage ?? 0, 0), 100) / 100
    }

    private var ringTint: Color {
        guard let p = claude.limits.fiveHourPercentage else { return .gray }
        if p >= Defaults[.claudeLimitCriticalThreshold] { return .red }
        if p >= Defaults[.claudeLimitWarningThreshold] { return .orange }
        return .green
    }

    /// Lado do conteúdo: sempre menor que a altura do notch, nunca o contrário.
    private var side: CGFloat { max(0, notchHeight - 12) }

    var body: some View {
        // Compacto de propósito: nada de Spacer largo aqui. Um espaçador do
        // tamanho do notch empurraria a caixa para além dela mesma, que foi
        // exatamente o defeito relatado ("o notch ficou gigante").
        HStack(spacing: 5) {
            ClaudeAsterisk(working: working, size: max(7, side * 0.60))

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: ringValue)
                    .stroke(ringTint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: ringValue)
            }
            .frame(width: side * 0.62, height: side * 0.62)
            .opacity(claude.limits.fiveHourPercentage == nil ? 0.35 : 1)
        }
        .padding(.horizontal, 6)
        .frame(height: notchHeight, alignment: .center)
        // Teto rígido: por maior que fique o conteúdo, a caixa não cresce.
        .fixedSize(horizontal: true, vertical: false)
    }
}
