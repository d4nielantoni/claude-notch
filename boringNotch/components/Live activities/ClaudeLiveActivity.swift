//
//  ClaudeLiveActivity.swift
//  boringNotch
//
//  Notch fechado: o caranguejo do Claude andando enquanto ele trabalha, e um
//  anel com o consumo do limite de 5 horas.
//

import SwiftUI

/// Laranja da marca do Claude, o mesmo do asterisco no terminal.
private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

/// O asterisco que pisca no Claude Code, com os glifos da própria CLI.
struct ClaudeAsterisk: View {
    let working: Bool
    let size: CGFloat

    // Sem o "·" da CLI: num notch de ~26pt ele vira sujeira, não estado.
    private static let glyphs = ["✢", "✳", "∗", "✻", "✽"]
    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    @State private var phase = 0

    private var glyph: String {
        working ? Self.glyphs[phase % Self.glyphs.count] : "✳"
    }

    var body: some View {
        Text(glyph)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(claudeOrange)
            .frame(width: size * 1.2, height: size * 1.2)
            .onReceive(timer) { _ in
                guard working else { return }   // parado, nada pisca à toa
                phase &+= 1
            }
    }
}

struct ClaudeLiveActivity: View {
    /// Toda a geometria vem de fora: quem manda no tamanho é o notch.
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    /// Num notch físico o miolo é buraco na tela, e o que for desenhado ali
    /// some. Muda o layout, não só a estética.
    let hasPhysicalNotch: Bool

    @ObservedObject var claude = ClaudeManager.shared

    private var session: ClaudeSession? { claude.highlighted }
    private var working: Bool { session?.state == .working }


    /// Lado do conteúdo: sempre menor que a altura do notch, nunca o contrário.
    private var side: CGFloat { max(12, notchHeight - 10) }

    /// Com relógio próprio: sem ele, o anel ficava no número da janela velha
    /// depois do reset até chegar algum evento.
    private var ring: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ring(percentage: claude.limits.fiveHour?.displayedPercentage(now: context.date))
        }
    }

    private func ring(percentage: Double?) -> some View {
        let ringValue = (percentage ?? 0) / 100
        let ringTint = ClaudeLimitWindow.tint(for: percentage)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2)
            Circle()
                .trim(from: 0, to: ringValue)
                .stroke(ringTint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: ringValue)
        }
        .frame(width: side * 0.78, height: side * 0.78)
        .opacity(percentage == nil ? 0.35 : 1)
    }

    var body: some View {
        HStack(spacing: 0) {
            ClaudeCrab(size: max(11, side * 0.74), walking: working)
                .frame(width: side, height: side)

            // Com notch físico reserva o recorte; sem ele, só empurra os
            // dois para as pontas.
            Spacer(minLength: hasPhysicalNotch ? notchWidth : 0)

            ring
        }
        .padding(.horizontal, 8)
        // Com notch físico a caixa cresce para o conteúdo sobrar dos lados.
        // Sem ele, largura fixa: deixar o conteúdo mandar faria a caixa
        // encolher e voltar a cada evento.
        .frame(
            width: hasPhysicalNotch ? nil : notchWidth,
            height: notchHeight,
            alignment: .center
        )
        .fixedSize(horizontal: hasPhysicalNotch, vertical: false)
    }
}
