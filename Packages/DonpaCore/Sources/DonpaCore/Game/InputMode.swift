/// What a plain tap/click on a *hidden* cell does. A revealed number always
/// chords and a long-press always does the opposite action, regardless of mode.
public enum InputMode: String, Codable, Sendable {
    case reveal
    case flag

    public mutating func toggle() { self = flipped }
    public var flipped: InputMode { self == .reveal ? .flag : .reveal }
}
