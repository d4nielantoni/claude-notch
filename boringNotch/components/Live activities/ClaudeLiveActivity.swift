//
//  ClaudeLiveActivity.swift
//  boringNotch
//
//  Notch fechado: asterisco do Claude enquanto ele trabalha, e um anel com o
//  consumo do limite de 5 horas.
//

import Defaults
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
    private var side: CGFloat { max(12, notchHeight - 10) }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2)
            Circle()
                .trim(from: 0, to: ringValue)
                .stroke(ringTint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: ringValue)
        }
        .frame(width: side * 0.78, height: side * 0.78)
        .opacity(claude.limits.fiveHourPercentage == nil ? 0.35 : 1)
    }

    var body: some View {
        HStack(spacing: 0) {
            ClaudeAsterisk(working: working, size: max(11, side * 0.80))
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
