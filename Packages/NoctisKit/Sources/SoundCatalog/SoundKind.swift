import Foundation

/// The sleep sounds NOCTIS makes. Every one is synthesized in code (APP_RULES.md R31): no audio
/// file is shipped. Forest and Night are not here: they need real recordings (ROADMAP.md).
public enum SoundKind: String, CaseIterable, Sendable, Codable, Hashable {
    case brown
    case rain
    case ocean
    case wind
    case fireplace
    case ambient

    public var title: String {
        switch self {
        case .brown: "Brown noise"
        case .rain: "Rain"
        case .ocean: "Ocean"
        case .wind: "Wind"
        case .fireplace: "Fireplace"
        case .ambient: "Ambient"
        }
    }

    /// The position in the mixer's tables: 0...5.
    public var index: Int {
        switch self {
        case .brown: 0
        case .rain: 1
        case .ocean: 2
        case .wind: 3
        case .fireplace: 4
        case .ambient: 5
        }
    }

    /// Where its random source starts. A fixed number, so the same sound is the same sound in a
    /// test; the left and right channels start from different numbers made from it.
    public var defaultSeed: UInt64 {
        switch self {
        case .brown: 0xB20A_1111_0001
        case .rain: 0xA117_2222_0002
        case .ocean: 0x0CE4_3333_0003
        case .wind: 0x71D0_4444_0004
        case .fireplace: 0xF1E5_5555_0005
        case .ambient: 0xA3B1_6666_0006
        }
    }

    public static let count = 6
}
