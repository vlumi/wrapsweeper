import SwiftUI

extension View {
    /// `onChange` that works on the iOS-16 floor without the macOS-14 deprecation
    /// warning. The zero/two-parameter `onChange` is iOS 17 / macOS 14 only, while
    /// the single-parameter form is deprecated on macOS 14 — so neither call site
    /// is clean on both platforms. This wrapper picks the right one per OS; the
    /// closure just needs the new value.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(
        of value: V, perform action: @escaping (V) -> Void
    ) -> some View {
        if #available(iOS 17, macOS 14, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value) { newValue in action(newValue) }
        }
    }
}
