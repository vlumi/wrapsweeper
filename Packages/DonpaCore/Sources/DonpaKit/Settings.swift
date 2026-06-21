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
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
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

    /// The concrete scheme to render with. For `.system` this resolves the live
    /// OS appearance directly (on macOS the ambient `@Environment(\.colorScheme)`
    /// is unreliable under a sibling `.preferredColorScheme`), so the SwiftUI
    /// chrome and the imperatively-colored SpriteKit scene always agree.
    public func resolvedScheme(systemFallback: ColorScheme) -> ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system:
            // macOS: the ambient `@Environment(\.colorScheme)` is unreliable
            // under a sibling `.preferredColorScheme`, so read AppKit directly.
            // iOS: the ambient value is authoritative once the forced scheme is
            // cleared, so use the fallback (the view updates when it settles).
            #if canImport(AppKit)
            let match = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? .dark : .light
            #else
            return systemFallback
            #endif
        }
    }
}

/// Which board-config flavour the picker offers.
public enum GameMode: String, CaseIterable, Identifiable, Sendable {
    case classic
    case modern

    public var id: String { rawValue }
    public var label: String { self == .classic ? "Classic" : "Modern" }
}

/// Persisted user settings (appearance + last board selection), backed by
/// `UserDefaults`. Remembering the mode and the Modern size/density lets the
/// picker restore the player's last choice across launches.
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

    private let defaults: UserDefaults
    private let appearanceKey = "donpa.appearance"
    private let modeKey = "donpa.mode"
    private let sizeKey = "donpa.modernSize"
    private let densityKey = "donpa.modernDensity"
    private let presetKey = "donpa.classicPreset"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance =
            defaults.string(forKey: appearanceKey).flatMap(AppearancePreference.init(rawValue:))
            ?? .system
        mode = defaults.string(forKey: modeKey).flatMap(GameMode.init(rawValue:)) ?? .classic
        modernSize = defaults.string(forKey: sizeKey).flatMap(BoardSize.init(rawValue:)) ?? .medium
        modernDensity =
            defaults.string(forKey: densityKey).flatMap(Density.init(rawValue:)) ?? .normal
        classicPreset =
            defaults.string(forKey: presetKey).flatMap(ClassicPreset.init(rawValue:)) ?? .beginner
    }

    /// The `GameConfig` implied by the current mode + selections.
    public var currentConfig: GameConfig {
        switch mode {
        case .classic: return .classic(classicPreset)
        case .modern: return .modern(modernSize, modernDensity)
        }
    }
}
