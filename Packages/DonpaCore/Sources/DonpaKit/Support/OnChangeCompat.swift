import SwiftUI

extension View {
    /// `onChange` for the iOS-16 floor without the macOS-14 deprecation warning:
    /// neither overload is clean on both platforms, so pick per OS.
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
