import AVFoundation
import Foundation
import Observation

/// 推箱子这一局的声音。人在这一局时循环背景音，回到首页或其他游戏就停。
/// 旋律和时长按设计文档的音频一节在这里合成，不读外部曲目。
@MainActor
@Observable
final class SokobanAudio {
    private(set) var phase = "stopped"
    private(set) var feeding = false
    private(set) var stepCount = 0
    private(set) var winCount = 0

    /// 模拟器检查读这一串。静音时步数和过关次数都不加。
    var token: String {
        "bgm:\(phase);engine:\(feeding ? 1 : 0);steps:\(stepCount);wins:\(winCount)"
    }

    @ObservationIgnored private var inGame = false
    @ObservationIgnored private var graphReady = false
    @ObservationIgnored private var loopQueued = false
    @ObservationIgnored private var clearTask: Task<Void, Never>?
    @ObservationIgnored private var volumeObservation: NSKeyValueObservation?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let loopNode = AVAudioPlayerNode()
    @ObservationIgnored private let stepNode = AVAudioPlayerNode()
    @ObservationIgnored private let stingerNode = AVAudioPlayerNode()
    @ObservationIgnored private var loopBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var stepBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var clearBuffer: AVAudioPCMBuffer?

    /// 进入推箱子。已经在这一局时不把循环掐掉重来。
    func enter() {
        guard !inGame else { return }
        inGame = true
        installVolumeWatch()
        updateTransport()
    }

    /// 离开推箱子。背景音、还没响的过关短乐都停。
    func leave() {
        let wasInGame = inGame
        inGame = false
        clearTask?.cancel()
        clearTask = nil
        volumeObservation?.invalidate()
        volumeObservation = nil
        stopFeeding()
        // 只关掉自己开过的会话。从首页进其他游戏时不要动系统音频。
        if wasInGame {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        phase = "stopped"
    }

    /// 成功走出一格。顶墙、推动和静音都不进这里。
    func playFootstep() {
        guard inGame, !Self.hearingIsSilent else { return }
        guard play(buffer: footstepBuffer(), on: stepNode) else { return }
        stepCount += 1
    }

    /// 重开、选关或下一关打断还没播完的过渡时，过关短乐不响。已经在响的这一声不停。
    func cancelPendingClear() {
        clearTask?.cancel()
        clearTask = nil
    }

    /// 过关短乐。`delayMilliseconds` 是造成过关的那一格过渡，走是 140，推是 180。
    func playClear(afterMilliseconds delayMilliseconds: Int) {
        guard inGame else { return }
        clearTask?.cancel()
        clearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delayMilliseconds) * 1_000_000)
            guard !Task.isCancelled, inGame, !Self.hearingIsSilent else { return }
            guard play(buffer: winBuffer(), on: stingerNode) else { return }
            winCount += 1
        }
    }

    /// 音量变化时立刻停或从这一圈开头再开始。检查参数固定静音时音量不动结果。
    private func installVolumeWatch() {
        volumeObservation?.invalidate()
        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.updateTransport()
            }
        }
    }

    /// 在这一局才送声。静音或音量为零时引擎停着。
    private func updateTransport() {
        guard inGame else {
            stopFeeding()
            phase = "stopped"
            return
        }
        do {
            try activateSession()
        } catch {
            NSLog("sokoban audio session: \(error.localizedDescription)")
            stopFeeding()
            phase = "stopped"
            return
        }
        if Self.hearingIsSilent {
            stopFeeding()
            phase = "silent"
            return
        }
        if startLoop() {
            phase = "playing"
        } else {
            stopFeeding()
            phase = "stopped"
        }
    }

    /// 检查可传 `-sokoban-hearing audible` 或 `silent`。正式游玩看媒体音量；响铃开关由 ambient 会话交给系统。
    private static var hearingIsSilent: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-sokoban-hearing"), arguments.indices.contains(index + 1) {
            let value = arguments[index + 1]
            if value == "silent" { return true }
            if value == "audible" { return false }
        }
        return AVAudioSession.sharedInstance().outputVolume <= 0.001
    }

    /// 跟随侧面响铃开关。开关静音时，系统不把这段送出来。
    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, mode: .default)
        try session.setPreferredSampleRate(SokobanTones.sampleRate)
        try session.setActive(true)
    }

    /// 背景循环。已经在播就不重新排队，避免把这一圈掐断。
    private func startLoop() -> Bool {
        do {
            try installGraph()
        } catch {
            NSLog("sokoban audio engine: \(error.localizedDescription)")
            return false
        }
        if loopBuffer == nil {
            loopBuffer = SokobanTones.loopBuffer()
        }
        guard let loopBuffer else { return false }
        if !loopQueued {
            loopNode.scheduleBuffer(loopBuffer, at: nil, options: .loops)
            loopQueued = true
        }
        if !loopNode.isPlaying {
            loopNode.play()
        }
        let started = engine.isRunning && loopNode.isPlaying
        feeding = started
        if !started {
            NSLog("sokoban audio: background loop did not start")
        }
        return started
    }

    /// 把三个播放节点接到混音器。离开后节点还在，下次直接启动。
    private func installGraph() throws {
        if !graphReady {
            let format = SokobanTones.format
            engine.attach(loopNode)
            engine.attach(stepNode)
            engine.attach(stingerNode)
            engine.connect(loopNode, to: engine.mainMixerNode, format: format)
            engine.connect(stepNode, to: engine.mainMixerNode, format: format)
            engine.connect(stingerNode, to: engine.mainMixerNode, format: format)
            graphReady = true
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    /// 停掉循环和效果。还没建过引擎时什么都不碰，避免其他游戏误开会话。
    private func stopFeeding() {
        guard graphReady else {
            feeding = false
            return
        }
        loopNode.stop()
        stepNode.stop()
        stingerNode.stop()
        loopQueued = false
        if engine.isRunning {
            engine.stop()
        }
        feeding = false
    }

    /// 排队一声短效果。引擎没在跑就不算发出去。
    private func play(buffer: AVAudioPCMBuffer, on node: AVAudioPlayerNode) -> Bool {
        guard engine.isRunning else { return false }
        node.scheduleBuffer(buffer, at: nil, options: [])
        if !node.isPlaying {
            node.play()
        }
        return true
    }

    private func footstepBuffer() -> AVAudioPCMBuffer {
        if let stepBuffer { return stepBuffer }
        let buffer = SokobanTones.footstepBuffer()
        stepBuffer = buffer
        return buffer
    }

    private func winBuffer() -> AVAudioPCMBuffer {
        if let clearBuffer { return clearBuffer }
        let buffer = SokobanTones.clearBuffer()
        clearBuffer = buffer
        return buffer
    }
}

/// 按设计里的音高和时长合成三段声音。没有采样文件。
enum SokobanTones {
    static let sampleRate: Double = 44100
    static let format: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    private static let pitches: [String: Double] = [
        "C2": 65.41, "E2": 82.41, "F2": 87.31, "A2": 110.00, "Bb2": 116.54,
        "F4": 349.23, "G4": 392.00, "A4": 440.00, "Bb4": 466.16,
        "C5": 523.25, "D5": 587.33, "E5": 659.25, "F5": 698.46, "G5": 783.99
    ]

    /// 四小节主旋律。`nil` 是休止。
    private static let melody: [String?] = [
        "F4", "A4", "C5", nil, "A4", "C5", "D5", "C5",
        "Bb4", "D5", "F5", nil, "D5", "C5", "A4", "G4",
        "A4", "C5", "E5", nil, "C5", "A4", "G4", "F4",
        "G4", "A4", "Bb4", "C5", "A4", "G4", "F4", nil
    ]

    /// 每拍前 250 毫秒的低音。
    private static let bass: [String] = [
        "F2", "C2", "F2", "C2",
        "Bb2", "F2", "Bb2", "F2",
        "A2", "E2", "A2", "E2",
        "C2", "F2", "C2", "F2"
    ]

    /// 8000 毫秒背景循环。方波主旋律峰值 0.18，三角波低音峰值 0.10。
    static func loopBuffer() -> AVAudioPCMBuffer {
        precondition(melody.count == 32)
        precondition(bass.count == 16)
        let frames = Int(sampleRate * 8)
        var samples = [Float](repeating: 0, count: frames)
        for (index, name) in melody.enumerated() {
            guard let name else { continue }
            addNote(
                into: &samples,
                start: Double(index) * 0.25,
                duration: 0.25,
                frequency: pitch(name),
                gain: 0.18,
                shape: square
            )
        }
        for (index, name) in bass.enumerated() {
            addNote(
                into: &samples,
                start: Double(index) * 0.5,
                duration: 0.25,
                frequency: pitch(name),
                gain: 0.10,
                shape: triangle
            )
        }
        fadeEnds(&samples)
        return buffer(samples)
    }

    /// 80 毫秒脚步：140 Hz、90 Hz 和一段噪声，峰值 0.35。
    static func footstepBuffer() -> AVAudioPCMBuffer {
        let frames = Int(sampleRate * 0.08)
        var samples = [Float](repeating: 0, count: frames)
        var state: UInt64 = 0xA5A5_1234_F00D
        for index in 0..<frames {
            let time = Double(index) / sampleRate
            let envelope = exp(-time * 36) * (1 - exp(-time / 0.003))
            state = state &* 6364136223846793005 &+ 1
            let noise = Float((state >> 40) & 0xFFFF) / 65535 * 2 - 1
            let body = sin(2 * .pi * 140 * time) * 0.65 + sin(2 * .pi * 90 * time) * 0.35
            samples[index] = Float(envelope) * (Float(body) * 0.55 + noise * 0.45)
        }
        normalize(&samples, peak: 0.35)
        return buffer(samples)
    }

    /// 500 毫秒过关短乐。do5、mi5、sol5，每音 140 毫秒，中间空 40 毫秒，峰值 0.28。
    static func clearBuffer() -> AVAudioPCMBuffer {
        let notes: [Double] = [523.25, 659.25, 783.99]
        let frames = Int(sampleRate * 0.5)
        var samples = [Float](repeating: 0, count: frames)
        for (index, frequency) in notes.enumerated() {
            let start = Double(index) * 0.18
            let startFrame = Int((start * sampleRate).rounded())
            let endFrame = min(frames, Int(((start + 0.14) * sampleRate).rounded()))
            for frame in startFrame..<endFrame {
                let time = Double(frame - startFrame) / sampleRate
                let envelope = exp(-time * 12) * (1 - exp(-time / 0.002))
                let phase = 2 * .pi * frequency * time
                let tone = sin(phase) + 0.22 * sin(phase * 2) + 0.08 * sin(phase * 3)
                samples[frame] += Float(envelope * tone)
            }
        }
        normalize(&samples, peak: 0.28)
        return buffer(samples)
    }

    /// 一个音写进缓冲。起止各 4 毫秒淡化，音长仍是 `duration`。
    private static func addNote(
        into samples: inout [Float],
        start: Double,
        duration: Double,
        frequency: Double,
        gain: Float,
        shape: (Double) -> Float
    ) {
        let startFrame = Int((start * sampleRate).rounded())
        let endFrame = min(samples.count, Int(((start + duration) * sampleRate).rounded()))
        let fadeFrames = max(1, Int((0.004 * sampleRate).rounded()))
        guard startFrame < endFrame else { return }
        for frame in startFrame..<endFrame {
            let local = frame - startFrame
            let remain = endFrame - frame
            var envelope = 1.0
            if local < fadeFrames {
                envelope *= sin(Double(local) / Double(fadeFrames) * .pi / 2)
            }
            if remain < fadeFrames {
                envelope *= sin(Double(remain) / Double(fadeFrames) * .pi / 2)
            }
            let time = Double(frame) / sampleRate - start
            samples[frame] += shape(2 * .pi * frequency * time) * gain * Float(envelope)
        }
    }

    /// 整圈首尾各 2 毫秒淡到 0，循环接上时不会爆音。
    private static func fadeEnds(_ samples: inout [Float]) {
        let fadeFrames = max(1, Int((0.002 * sampleRate).rounded()))
        guard samples.count > fadeFrames * 2 else { return }
        for index in 0..<fadeFrames {
            let rise = Float(sin(Double(index) / Double(fadeFrames) * .pi / 2))
            samples[index] *= rise
            samples[samples.count - 1 - index] *= rise
        }
    }

    /// 方波用前三次奇数泛音，相位 0 时幅度是 0。
    private static func square(_ phase: Double) -> Float {
        let raw = sin(phase) + sin(phase * 3) / 3 + sin(phase * 5) / 5
        return Float(raw / (1 + 1.0 / 3 + 1.0 / 5))
    }

    /// 三角波。相位 0 时从 0 开始，避免低音起音爆一下。
    private static func triangle(_ phase: Double) -> Float {
        Float((2 / .pi) * asin(sin(phase)))
    }

    private static func pitch(_ name: String) -> Double {
        guard let frequency = pitches[name] else {
            preconditionFailure("缺少音高 \(name)")
        }
        return frequency
    }

    /// 合成声的峰值按设计收束，避免某一声特别冲。
    private static func normalize(_ samples: inout [Float], peak: Float) {
        let loudest = samples.map { abs($0) }.max() ?? 0
        guard loudest > 0 else { return }
        let scale = peak / loudest
        for index in samples.indices {
            samples[index] *= scale
        }
    }

    private static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            for index in samples.indices {
                channel[index] = samples[index]
            }
        }
        return buffer
    }
}
