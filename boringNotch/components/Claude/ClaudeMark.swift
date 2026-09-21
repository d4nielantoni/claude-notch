//
//  ClaudeMark.swift
//  boringNotch
//
//  O ícone do Claude: sunburst branco sobre o quadrado laranja arredondado.
//
//  As pontas são finas e longas de propósito. Pontas grossas fecham o miolo
//  e o desenho vira um borrão laranja em tamanho de ícone de aba.
//

import SwiftUI

struct ClaudeMark: View {
    var size: CGFloat = 14
    /// `false` desenha só o sunburst, sem o quadrado — útil sobre fundo escuro.
    var tile: Bool = true

    private let laranja = Color(red: 0.91, green: 0.36, blue: 0.22)

    /// Comprimento de cada ponta, como fração do raio útil. Os valores variam
    /// para o desenho não ficar com cara de asterisco de teclado.
    private static let comprimentos: [Double] = [
        1.00, 0.78, 0.95, 0.72, 1.00, 0.80,
        0.96, 0.74, 1.00, 0.79, 0.93, 0.76,
    ]

    var body: some View {
        ZStack {
            if tile {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(laranja)
            }

            Canvas { context, canvasSize in
                let centro = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let lado = min(canvasSize.width, canvasSize.height)
                let espessura = lado * 0.072
                let util = lado * 0.40
                let cor: Color = tile ? .white : laranja
                let passo = 360.0 / Double(Self.comprimentos.count)

                for (i, fator) in Self.comprimentos.enumerated() {
                    // Meio passo de deslocamento: nenhuma ponta fica na vertical
                    // exata, que é o que dá o aspecto desenhado à mão.
                    let rad = (Double(i) * passo - 82) * .pi / 180
                    var caminho = Path()
                    caminho.move(to: centro)
                    caminho.addLine(to: CGPoint(
                        x: centro.x + cos(rad) * util * fator,
                        y: centro.y + sin(rad) * util * fator
                    ))
                    context.stroke(
                        caminho,
                        with: .color(cor),
                        style: StrokeStyle(lineWidth: espessura, lineCap: .round)
                    )
                }
            }
        }
        .frame(width: size, height: size)
    }
}
