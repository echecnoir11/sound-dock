import Foundation
import Combine

struct AudioPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let speed: Float
    let bass: Float
    let volume: Float

    init(id: UUID = UUID(), name: String, settings: EffectSettings) {
        self.id = id; self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        speed = settings.speed; bass = settings.bass; volume = settings.volume
    }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 48 &&
        speed.isFinite && bass.isFinite && volume.isFinite &&
        (0.5...2).contains(speed) && (0...12).contains(bass) && (0...1).contains(volume)
    }
    func applying(to settings: EffectSettings) -> EffectSettings {
        var result = settings
        result.speed = speed; result.bass = bass; result.volume = volume
        return result
    }
    func matches(_ settings: EffectSettings) -> Bool {
        abs(speed - settings.speed) < 0.0001 && abs(bass - settings.bass) < 0.0001 && abs(volume - settings.volume) < 0.0001
    }
}

final class PresetStore: ObservableObject {
    @Published private(set) var presets: [AudioPreset] = []
    @Published private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "audioPresets.v1") {
        self.defaults = defaults; self.key = key
        guard let data = defaults.data(forKey: key) else { return }
        do {
            let decoded = try JSONDecoder().decode([AudioPreset].self, from: data)
            var ids = Set<UUID>()
            presets = decoded.filter { $0.isValid && ids.insert($0.id).inserted }
            if presets.count != decoded.count { errorMessage = "Certains presets invalides ont été ignorés." }
        } catch { errorMessage = "Impossible de lire les presets enregistrés." }
    }
    @discardableResult func save(name: String, settings: EffectSettings) throws -> AudioPreset {
        let preset = AudioPreset(name: name, settings: settings)
        try validate(preset)
        try persist(presets + [preset])
        return preset
    }
    func rename(id: UUID, name: String) throws {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        var next = presets
        next[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try validate(next[index], excluding: id)
        try persist(next)
    }
    func delete(id: UUID) throws { try persist(presets.filter { $0.id != id }) }
    private func validate(_ preset: AudioPreset, excluding id: UUID? = nil) throws {
        guard preset.isValid else { throw AudioFailure(message: "Nom requis (48 caractères maximum) et réglages valides.") }
        guard !presets.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }) else {
            throw AudioFailure(message: "Un preset porte déjà ce nom.")
        }
    }
    private func persist(_ next: [AudioPreset]) throws {
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: key)
        presets = next; errorMessage = nil
    }
}
