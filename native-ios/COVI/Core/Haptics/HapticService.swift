import UIKit
import CoreHaptics

enum HapticService {
    private static var engine: CHHapticEngine?
    static func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do { engine = try CHHapticEngine(); try engine?.start() } catch { engine = nil }
    }
    static func keyPress() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { tap(); return }
        do {
            if engine == nil { prepare() }
            let parameters = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ]
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: 0)
            try engine?.makePlayer(with: CHHapticPattern(events: [event], parameters: [])).start(atTime: 0)
        } catch { }
    }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func confirm() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
