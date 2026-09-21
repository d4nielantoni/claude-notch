//
//  ClaudeCrab.swift
//  boringNotch
//
//  O caranguejo do Claude, desenhado em pixel art. Anda enquanto o Claude
//  trabalha e fica parado quando ele para.
//
//  Portado de ClaudeIsland (vibe-notch), de farouqaldori, licenciado sob
//  Apache-2.0: https://github.com/farouqaldori/vibe-notch
//  A Apache-2.0 é compatível com a GPL-3.0 deste projeto nesta direção.
//  A geometria (proporções 66x52, posições das pernas e das antenas) é
//  daquele projeto; o crédito fica aqui e em THIRD_PARTY_LICENSES.
//

import SwiftUI

struct ClaudeCrab: View {
    var size: CGFloat = 16
    var color: Color = Color(red: 0.85, green: 0.47, blue: 0.34)
    var walking: Bool = false

    // Quatro fases: alterna quais pernas estão esticadas, passando por uma
    // posição neutra entre elas. É o que faz parecer passo em vez de tremor.
    private static let legPhases: [[CGFloat]] = [
        [3, -3, 3, -3],
        [0, 0, 0, 0],
        [-3, 3, -3, 3],
        [0, 0, 0, 0],
    ]
    private static let legX: [CGFloat] = [6, 18, 42, 54]
    private static let baseLegHeight: CGFloat = 13

    /// Proporção do desenho original, em unidades de viewBox.
    private static let artWidth: CGFloat = 66
    private static let artHeight: CGFloat = 52

    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
    @State private var phase = 0

    var body: some View {
        Canvas { context, canvasSize in
            let scale = size / Self.artHeight
            let xOffset = (canvasSize.width - Self.artWidth * scale) / 2

            func preencher(_ rect: CGRect, _ cor: Color) {
                let p = Path(rect).applying(
                    CGAffineTransform(scaleX: scale, y: scale)
                        .translatedBy(x: xOffset / scale, y: 0)
                )
                context.fill(p, with: .color(cor))
            }

            // Antenas
            preencher(CGRect(x: 0, y: 13, width: 6, height: 13), color)
            preencher(CGRect(x: 60, y: 13, width: 6, height: 13), color)

            // Pernas: presas ao corpo em y=39, só a altura muda
            let offsets = walking
                ? Self.legPhases[phase % Self.legPhases.count]
                : [CGFloat](repeating: 0, count: Self.legX.count)
            for (i, x) in Self.legX.enumerated() {
                preencher(
                    CGRect(x: x, y: 39, width: 6, height: Self.baseLegHeight + offsets[i]),
                    color
                )
            }

            // Corpo e olhos
            preencher(CGRect(x: 6, y: 0, width: 54, height: 39), color)
            preencher(CGRect(x: 12, y: 13, width: 6, height: 6.5), .black)
            preencher(CGRect(x: 48, y: 13, width: 6, height: 6.5), .black)
        }
        .frame(width: size * (Self.artWidth / Self.artHeight), height: size)
        .onReceive(timer) { _ in
            guard walking else { return }   // parado, nada se mexe
            phase = (phase + 1) % Self.legPhases.count
        }
    }
}
