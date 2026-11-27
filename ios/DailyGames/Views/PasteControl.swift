import SwiftUI
import UIKit

/// The system Paste button, sized to fill its space. Pasting through it doesn't bring up iOS's "Allow Paste"
/// prompt, since tapping it is the permission. It dims itself when there's no text to paste.
struct PasteControl: UIViewRepresentable {
    var prominent: Bool
    var onPaste: (String) -> Void

    func makeCoordinator() -> Target { Target() }

    func makeUIView(context: Context) -> UIPasteControl {
        let config = UIPasteControl.Configuration()
        config.displayMode = .iconAndLabel
        config.cornerStyle = .fixed
        config.cornerRadius = 14
        config.baseBackgroundColor = prominent ? UIColor(named: "AccentColor") : UIColor(light: 0xFFFFFF, dark: 0x222128)
        config.baseForegroundColor = prominent ? UIColor(light: 0xFFFFFF, dark: 0x1A1208) : UIColor(light: 0x1D1B20, dark: 0xF2EFF5)
        let control = UIPasteControl(configuration: config)
        control.target = context.coordinator
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateUIView(_ control: UIPasteControl, context: Context) {
        context.coordinator.onPaste = onPaste
    }

    /// Receives what the control pastes.
    final class Target: UIResponder {
        var onPaste: (String) -> Void = { _ in }

        override init() {
            super.init()
            pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
        }

        override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool { true }

        override func paste(itemProviders: [NSItemProvider]) {
            guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
                onPaste("")
                return
            }
            _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
                let text = (object as? NSString).map { $0 as String } ?? ""
                Task { @MainActor in self?.onPaste(text) }
            }
        }
    }
}
