import Foundation
import CoreMotion
import CoreGraphics

/// Shared accelerometer-driven gravity source for SpriteKit scenes.
///
/// `CMMotionManager` is single-instance per app: spinning up multiple
/// concurrent device-motion streams duplicates work and the OS warns. This
/// controller owns the only manager and lets multiple scenes (currently
/// `BucketScene`) reads the latest gravity vector each
/// frame via `currentGravity`. Updates start on the first subscriber and
/// stop on the last, so we don't leave the IMU spinning when the user is on
/// a non-physics tab.
///
/// Gravity is reported in device coordinates (units of g):
///   - portrait, top up:        (0, -1, 0)
///   - portrait, tilted left:   (-, -, 0)   x goes negative
///   - flat face-up on table:   (0, 0, -1)
///
/// Our SpriteKit scenes are 2D and use the screen's natural axes (y up,
/// x right). Mapping `(x, y)` of the device gravity vector directly is the
/// right thing in portrait — the same orientation the app is locked to.
final class MotionGravityController {
    static let shared = MotionGravityController()

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private var subscriberCount: Int = 0
    private var latest: CGVector = CGVector(dx: 0, dy: -1)
    private let lock = NSLock()

    private init() {
        queue.name = "com.glycotrack.motion"
        queue.qualityOfService = .userInteractive
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
    }

    /// Latest device-gravity vector, normalized to magnitude ≈ 1 g, mapped
    /// onto the 2D screen plane. Read this each frame from
    /// `SKScene.update(_:)` and multiply by your scene's gravity magnitude.
    /// Falls back to (0, -1) — phone held upright — until the first sample.
    var currentGravity: CGVector {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    /// Begin streaming device motion. Pair every call with `release()` when
    /// the subscriber is done (typically `willMove(from:)` on an SKScene).
    func retain() {
        lock.lock()
        subscriberCount += 1
        let shouldStart = subscriberCount == 1
        lock.unlock()

        guard shouldStart, manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // Device-motion gravity: x is right-positive on screen, y is
            // up-positive on screen in portrait. So `(x, y)` maps straight
            // to a 2D top-up scene. We don't use z — tilt forward/back is
            // not visible in the 2D viz.
            let g = motion.gravity
            self.lock.lock()
            self.latest = CGVector(dx: CGFloat(g.x), dy: CGFloat(g.y))
            self.lock.unlock()
        }
    }

    /// Decrement the subscriber count; stops updates when it reaches zero.
    func release() {
        lock.lock()
        subscriberCount = max(0, subscriberCount - 1)
        let shouldStop = subscriberCount == 0
        lock.unlock()

        if shouldStop, manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
    }
}
