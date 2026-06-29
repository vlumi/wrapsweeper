import DonpaCore
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// User-chosen appearance. `.system` follows the device setting.
public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return String(localized: "System", bundle: .module)
        case .light: return String(localized: "Light", bundle: .module)
        case .dark: return String(localized: "Dark", bundle: .module)
        }
    }

    /// The scheme to force on the SwiftUI hierarchy, or nil to follow the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The concrete scheme to render with, so the SwiftUI chrome and the
    /// imperatively-coloured SpriteKit scene agree. For `.system` this resolves the
    /// live OS appearance directly.
    public func resolvedScheme(systemFallback: ColorScheme) -> ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system:
            // macOS: the ambient `@Environment(\.colorScheme)` is unreliable under
            // a sibling `.preferredColorScheme`, so read AppKit directly. iOS: the
            // ambient value is authoritative once the forced scheme clears.
            #if canImport(AppKit)
            let match = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? .dark : .light
            #else
            return systemFallback
            #endif
        }
    }
}

/// Which bottom corner the floating reveal/flag toggle sits in. Default `.left`:
/// a right-handed player taps with the right hand and reaches the toggle with the
/// left. Switchable in Settings.
public enum Handedness: String, CaseIterable, Identifiable, Sendable {
    case right
    case left

    public var id: String { rawValue }
    public var label: String {
        self == .right
            ? String(localized: "Right", bundle: .module)
            : String(localized: "Left", bundle: .module)
    }
    /// SwiftUI alignment for the floating toggle's corner.
    public var alignment: Alignment { self == .right ? .bottomTrailing : .bottomLeading }
}

/// Which board-config flavour the picker offers.
public enum GameMode: String, CaseIterable, Identifiable, Sendable {
    case classic
    case modern

    public var id: String { rawValue }
    public var label: String {
        self == .classic
            ? String(localized: "Classic", bundle: .module)
            : String(localized: "Modern", bundle: .module)
    }
}

/// App language override. Applied by writing `AppleLanguages`, which the system
/// reads at launch — so a change takes effect next launch.
public enum LanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case japanese
    case finnish

    public var id: String { rawValue }

    /// The `AppleLanguages` code this forces, or nil to follow the device.
    public var languageCode: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .japanese: return "ja"
        case .finnish: return "fi"
        }
    }

    /// Each language in its own name (plus localized "System").
    public var label: String {
        switch self {
        case .system: return String(localized: "System", bundle: .module)
        case .english: return "English"
        case .japanese: return "日本語"
        case .finnish: return "Suomi"
        }
    }
}

/// Persisted user settings (appearance + last board selection), backed by
/// `UserDefaults`, so the picker restores the player's last choice across launches.
@MainActor
public final class Settings: ObservableObject {
    @Published public var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: appearanceKey) }
    }
    @Published public var mode: GameMode {
        didSet { defaults.set(mode.rawValue, forKey: modeKey) }
    }
    @Published public var modernSize: BoardSize {
        didSet { defaults.set(modernSize.rawValue, forKey: sizeKey) }
    }
    @Published public var modernDensity: Density {
        didSet { defaults.set(modernDensity.rawValue, forKey: densityKey) }
    }
    @Published public var classicPreset: ClassicPreset {
        didSet { defaults.set(classicPreset.rawValue, forKey: presetKey) }
    }
    @Published public var handedness: Handedness {
        didSet { defaults.set(handedness.rawValue, forKey: handednessKey) }
    }
    /// Show the big-board minimap overview (only appears when the board also
    /// exceeds the viewport).
    @Published public var showMinimap: Bool {
        didSet { defaults.set(showMinimap, forKey: showMinimapKey) }
    }
    /// Minimap size multiplier over its base size, persisted so a resize survives
    /// new game / restart / save-restore. The scene clamps it to a sane range.
    @Published public var minimapScale: Double {
        didSet { defaults.set(minimapScale, forKey: minimapScaleKey) }
    }
    /// Sync the scoreboard across devices via iCloud. Opt-in, off by default — our
    /// own toggle, not a system grant (KVS rides on the system sign-in).
    @Published public var syncScores: Bool {
        didSet { defaults.set(syncScores, forKey: syncScoresKey) }
    }
    /// Language override. Persisted as our preference and written to
    /// `AppleLanguages` for the system to pick up next launch.
    @Published public var language: LanguagePreference {
        didSet {
            defaults.set(language.rawValue, forKey: languageKey)
            if let code = language.languageCode {
                defaults.set([code], forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
        }
    }

    private let defaults: UserDefaults
    private let appearanceKey = "donpa.appearance"
    private let modeKey = "donpa.mode"
    private let sizeKey = "donpa.modernSize"
    private let densityKey = "donpa.modernDensity"
    private let presetKey = "donpa.classicPreset"
    private let handednessKey = "donpa.handedness"
    private let languageKey = "donpa.language"
    private let showMinimapKey = "donpa.showMinimap"
    private let minimapScaleKey = "donpa.minimapScale"
    private let syncScoresKey = "donpa.syncScores"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance =
            defaults.string(forKey: appearanceKey).flatMap(AppearancePreference.init(rawValue:))
            ?? .system
        mode = defaults.string(forKey: modeKey).flatMap(GameMode.init(rawValue:)) ?? .classic
        // Old size raw names (small/medium/…) no longer decode; fall back to `.s`
        // (the long-time default). Self-healing — the next pick persists the new name.
        modernSize = defaults.string(forKey: sizeKey).flatMap(BoardSize.init(rawValue:)) ?? .s
        modernDensity =
            defaults.string(forKey: densityKey).flatMap(Density.init(rawValue:)) ?? .normal
        classicPreset =
            defaults.string(forKey: presetKey).flatMap(ClassicPreset.init(rawValue:)) ?? .beginner
        handedness =
            defaults.string(forKey: handednessKey).flatMap(Handedness.init(rawValue:)) ?? .left
        // Default ON: check presence explicitly, since `bool(forKey:)` is false when
        // the key is missing.
        showMinimap = defaults.object(forKey: showMinimapKey) as? Bool ?? true
        // Default 1.0 (base size); a stored value restores the player's last size.
        minimapScale = defaults.object(forKey: minimapScaleKey) as? Double ?? 1.0
        syncScores = defaults.object(forKey: syncScoresKey) as? Bool ?? false
        language =
            defaults.string(forKey: languageKey).flatMap(LanguagePreference.init(rawValue:))
            ?? .system
    }

    /// The `GameConfig` implied by the current mode + selections.
    public var currentConfig: GameConfig {
        switch mode {
        case .classic: return .classic(classicPreset)
        case .modern: return .modern(modernSize, modernDensity)
        }
    }
}
