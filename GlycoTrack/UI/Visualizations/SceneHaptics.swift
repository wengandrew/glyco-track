import SpriteKit
import UIKit

/// Per-scene haptic feedback for SpriteKit physics scenes.
///
/// Wired into `SKPhysicsContactDelegate.didBegin` so a light impact fires the
/// first time each item node touches anything (a wall, the floor, another
/// item). Subsequent contacts from the same node — settling, rolling, resting
/// against a wall — are suppressed so a single drop produces one tick rather
/// than a vibrating buzz.
///
/// Why per-scene rather than a singleton: the firing set is keyed by
/// `ObjectIdentifier`, which becomes stale once SwiftUI tears the scene host
/// down and rebuilds it (see "Date-scoped physics scenes" in CLAUDE.md). Each
/// scene gets its own helper that's discarded with the scene.
@MainActor
final class SceneHaptics {
    private let generator = UIImpactFeedbackGenerator(style: .light)
    private var firedNodes: Set<ObjectIdentifier> = []

    init() {
        // Pre-warm the engine so the first impact isn't delayed while the
        // taptic engine spins up. Cheap; ARC-safe to leave alive for the
        // scene's lifetime.
        generator.prepare()
    }

    /// Fires an impact for the first contact involving each item node. The
    /// scene must tag item containers with `node.name == "item"` or `"bubble"`
    /// (see PhysicsBucketView / BalanceScaleView / WaterlineView).
    func handleContact(_ contact: SKPhysicsContact) {
        // Walk both bodies — a single contact may involve two items (item-on-item
        // settle), but we only want one tick per *event*. Returning after the
        // first new-id insertion enforces that.
        for body in [contact.bodyA, contact.bodyB] {
            guard let node = body.node else { continue }
            guard node.name == "item" || node.name == "bubble" else { continue }
            if firedNodes.insert(ObjectIdentifier(node)).inserted {
                generator.impactOccurred()
                return
            }
        }
    }
}
