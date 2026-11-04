import SwiftUI
import AVFoundation
import AudioGuard

/// Owns a tiny atomic mailbox written by the existing processed-output tap.
/// Only tick/start/stop and the published bars are used on the main thread.
final class VisualizerModel: ObservableObject {
    @Published private(set) var bars = [Float](repeating: 0, count: 16)
    private let meter = SDVisualizerCreate()
    private var timer: Timer?
    private var lastGeneration: UInt64 = 0
    deinit { timer?.invalidate(); if let meter { SDVisualizerDestroy(meter) } }

    func capture(_ buffer: AVAudioPCMBuffer) {
        if let meter { SDVisualizerProcess(meter, buffer.frameLength, buffer.audioBufferList) }
    }
    func start() {
        stop()
        guard meter != nil else { return }
        timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.005
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let meter { SDVisualizerReset(meter) }
        lastGeneration = 0
        if bars.contains(where: { $0 != 0 }) { bars = [Float](repeating: 0, count: 16) }
    }
    private func tick() {
        guard let meter else { return }
        var samples = [Float](repeating: 0, count: 16)
        let generation = samples.withUnsafeMutableBufferPointer { SDVisualizerCopy(meter, $0.baseAddress!, 16) }
        let fresh = generation != lastGeneration
        lastGeneration = generation
        var next = bars
        for i in next.indices {
            let target = fresh ? sqrt(min(1, max(0, samples[i]))) : 0
            let amount: Float = target > bars[i] ? 0.65 : 0.22
            next[i] = bars[i] + (target - bars[i]) * amount
            if next[i] < 0.003 { next[i] = 0 }
        }
        // No changing view state once the signal is silent; timer stops on engine stop.
        if zip(next, bars).contains(where: { abs($0 - $1) > 0.001 || ($0 == 0 && $1 != 0) }) { bars = next }
    }
}

enum VisualizerScale {
    static func litSegments(_ level: Float, rows: Int = 10) -> Int {
        guard level.isFinite, level > 0, rows > 0 else { return 0 }
        return min(rows, Int(ceil(min(1, level) * Float(rows))))
    }
}

struct MiniVisualizer: View {
    @ObservedObject var model: VisualizerModel
    let color: Color
    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 4, rowGap: CGFloat = 1.5
            let width = max(1, (size.width - gap * 15) / 16)
            let height = max(1, (size.height - rowGap * 9) / 10)
            for index in 0..<16 {
                let lit = VisualizerScale.litSegments(model.bars[index])
                for row in 0..<10 {
                    let rect = CGRect(x: CGFloat(index) * (width + gap), y: size.height - CGFloat(row + 1) * (height + rowGap) + rowGap, width: width, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(row < lit ? 0.65 + Double(row) * 0.03 : 0.08)))
                }
            }
        }
        .frame(height: 40).accessibilityLabel("Niveau audio traité")
        .accessibilityValue(model.bars.contains(where: { $0 > 0 }) ? "Signal actif" : "Silencieux")
        .help("Plus le son est fort, plus les segments s’allument du bas vers le haut. Niveau d’amplitude, pas de fréquences.")
    }
}
