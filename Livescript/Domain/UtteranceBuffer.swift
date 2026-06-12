import Foundation

enum UtteranceEvent: Equatable {
    case draftHop(audio: [Float])
    case utteranceComplete(audio: [Float])
}

/// Accumulates speech per speaker and emits draft hops plus utterance boundaries.
struct UtteranceBuffer {
    let sampleRate: Int
    let draftHopSamples: Int
    let pauseSamples: Int
    let maxUtteranceSamples: Int
    let minimumEnergy: Float

    private(set) var samples: [Float] = []
    private var silenceSampleCount = 0
    private var isInSpeech = false
    private var samplesSinceDraftHop = 0

    init(
        sampleRate: Int = 16_000,
        draftHopSeconds: Double = 1.5,
        pauseSeconds: Double = 0.4,
        maxUtteranceSeconds: Double = 10,
        minimumEnergy: Float = 0.0035
    ) {
        self.sampleRate = sampleRate
        self.draftHopSamples = Int(draftHopSeconds * Double(sampleRate))
        self.pauseSamples = Int(pauseSeconds * Double(sampleRate))
        self.maxUtteranceSamples = Int(maxUtteranceSeconds * Double(sampleRate))
        self.minimumEnergy = minimumEnergy
    }

    mutating func reset() {
        samples = []
        silenceSampleCount = 0
        isInSpeech = false
        samplesSinceDraftHop = 0
    }

    mutating func append(_ chunk: [Float], hasSpeech: Bool? = nil) -> [UtteranceEvent] {
        guard !chunk.isEmpty else { return [] }

        var events: [UtteranceEvent] = []
        let energy = TranscriptionPipelineSupport.rms(chunk)
        let chunkHasSpeech = hasSpeech ?? (energy >= minimumEnergy)

        if chunkHasSpeech {
            isInSpeech = true
            silenceSampleCount = 0
        } else if isInSpeech {
            silenceSampleCount += chunk.count
        }

        samples.append(contentsOf: chunk)
        if samples.count > maxUtteranceSamples {
            trimToMaxUtterance()
        }

        if isInSpeech {
            samplesSinceDraftHop += chunk.count
            if samplesSinceDraftHop >= draftHopSamples {
                let hopLength = min(samplesSinceDraftHop, samples.count)
                events.append(.draftHop(audio: Array(samples.suffix(hopLength))))
                samplesSinceDraftHop = 0
            }
        }

        if isInSpeech, silenceSampleCount >= pauseSamples {
            events.append(.utteranceComplete(audio: Array(samples)))
            reset()
            return events
        }

        if samples.count >= maxUtteranceSamples, isInSpeech {
            events.append(.utteranceComplete(audio: Array(samples)))
            reset()
        }

        return events
    }

    mutating func flushPendingUtterance() -> [Float]? {
        guard isInSpeech, !samples.isEmpty else {
            reset()
            return nil
        }
        let audio = samples
        reset()
        return audio
    }

    private mutating func trimToMaxUtterance() {
        let overflow = samples.count - maxUtteranceSamples
        guard overflow > 0 else { return }
        samples.removeFirst(overflow)
        samplesSinceDraftHop = max(0, samplesSinceDraftHop - overflow)
    }
}
