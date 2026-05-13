import SpriteKit
import UIKit
import CoreHaptics

/// Per-scene haptic feedback for SpriteKit physics scenes.
///
/// Wired into `SKPhysicsContactDelegate.didBegin` so a haptic fires the
/// first time each item node touches anything (a wall, the floor, another
/// item). Subsequent contacts from the same node — settling, rolling, resting
/// against a wall — are suppressed so a single drop produces one tick rather
/// than a vibrating buzz.
///
/// Uses CoreHaptics when available (iOS 13+, supported hardware) for
/// configurable intensity and duration. Falls back to
/// `UIImpactFeedbackGenerator` on devices without a Taptic Engine.
///
/// Why per-scene rather than a singleton: the firing set is keyed by
/// `ObjectIdentifier`, which becomes stale once SwiftUI tears the scene host
/// down and rebuilds it (see "Date-scoped physics scenes" in CLAUDE.md). Each
/// scene gets its own helper that's discarded with the scene.
@MainActor
final class SceneHaptics {
    private let intensity: CGFloat
    private let duration: TimeInterval

    // CoreHaptics path
    private var engine: CHHapticEngine?
    // Fallback path
    private let generator = UIImpactFeedbackGenerator(style: .light)

    private var firedNodes: Set<ObjectIdentifier> = []

    init(intensity: Double = 1.0, duration: Double = AppSettings.defaultPhysicsHapticDuration) {
        self.intensity = CGFloat(max(0, min(1, intensity)))
        self.duration = max(0.02, min(0.5, duration))

        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            engine = try? CHHapticEngine()
            try? engine?.start()
        } else {
            generator.prepare()
        }
    }

    /// Fires an impact for the first contact involving each item node. The
    /// scene must tag item containers with `node.name == "item"` or `"bubble"`
    /// (see PhysicsBucketView / BalanceScaleView).
    func handleContact(_ contact: SKPhysicsContact) {
        // Walk both bodies — a single contact may involve two items (item-on-item
        // settle), but we only want one tick per *event*. Returning after the
        // first new-id insertion enforces that.
        for body in [contact.bodyA, contact.bodyB] {
            guard let node = body.node else { continue }
            guard node.name == "item" || node.name == "bubble" else { continue }
            if firedNodes.insert(ObjectIdentifier(node)).inserted {
                if intensity > 0 {
                    fire()
                }
                return
            }
        }
    }

    private func fire() {
        if let engine {
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity))
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensityParam, sharpnessParam],
                relativeTime: 0,
                duration: duration
            )
            if let pattern = try? CHHapticPattern(events: [event], parameters: []),
               let player = try? engine.makePlayer(with: pattern) {
                try? player.start(atTime: CHHapticTimeImmediate)
            }
        } else {
            generator.impactOccurred(intensity: intensity)
        }
    }
}
