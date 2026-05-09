import SwiftUI
import SpriteKit
import UIKit

/// Physics-based Daily GL Bucket.
/// Food emojis drop from the top and settle into a bucket under gravity. Each emoji's
/// **area** is proportional to its GL. The bucket's interior area is sized so that a
/// full daily GL budget (100) exactly fills it — anything over spills over the rim.
/// Tap any emoji to see food details.
struct PhysicsBucketView: View {
    let entries: [FoodLogEntry]
    /// Date this view represents. Changing this value forces a scene rebuild
    /// even if the entry IDs happen to overlap between days.
    let dateKey: Date?

    /// Reactive binding to the user's GL budget. Reading this in `body` makes
    /// the view re-evaluate when Settings writes to UserDefaults; including
    /// `budget` in `SceneKey` (below) then forces a host re-init so the bucket
    /// geometry — `areaPerUnit` and the "78% fill at full budget" rule —
    /// re-derives to match.
    @AppStorage(AppSettings.dailyGLBudgetKey) private var budget: Double = AppSettings.defaultDailyGLBudget

    @State private var selectedEntry: FoodLogEntry?
    /// Bumped to force a rebuild without an input change (Replay button, tab
    /// re-appearance). Day/entries changes force a rebuild automatically via
    /// `SceneKey` — this nonce only covers the "same inputs, replay anyway" cases.
    @State private var replayNonce = UUID()

    init(entries: [FoodLogEntry], dateKey: Date? = nil) {
        self.entries = entries
        self.dateKey = dateKey
    }

    private var totalGL: Double { entries.reduce(0) { $0 + $1.computedGL } }
    private var entryIDs: [UUID] { entries.compactMap { $0.id } }
    /// Day-bucket of `dateKey` (or distantPast if unset). Intra-day time changes
    /// don't force extra rebuilds, but day-to-day navigation does.
    private var dayKey: Date {
        guard let dateKey else { return .distantPast }
        return Calendar.current.startOfDay(for: dateKey)
    }

    var body: some View {
        GeometryReader { geo in
            // The scene key is a pure function of the reactive inputs.
            //
            // Why we use `.id(key)` on a child view + `@State` scene built at init,
            // instead of `.task(id: key)` writing to the parent's `@State scene`:
            //
            //   `.task(id:)` cancels-and-restarts when id changes, but with a
            //   synchronous body (no awaits / cancellation checks), BOTH the stale
            //   and fresh tasks run to completion. Their finish order is undefined,
            //   so the stale one can land last and overwrite the fresh scene. The
            //   user-visible bug was "always one day behind on swipe".
            //
            //   `.id(key)` on a child view forces SwiftUI to tear down and re-init
            //   that child whenever the key changes. The child's `@State` is reset,
            //   its `init` is what creates the SKScene from `entries`, and the scene
            //   construction happens synchronously on the main thread inside body
            //   evaluation. No cross-task ordering, no race.
            let key = SceneKey(
                replay: replayNonce,
                dayKey: dayKey,
                entryIDs: entryIDs,
                width: geo.size.width,
                height: geo.size.height,
                budget: budget
            )
            ZStack {
                BucketSceneHost(
                    entries: entries,
                    size: geo.size,
                    budget: budget,
                    onTap: { selectedEntry = $0 }
                )
                .id(key)

                if entries.isEmpty {
                    emptyStateOverlay
                }
            }
        }
        .aspectRatio(0.78, contentMode: .fit)
        // Replay when the view reappears (e.g. user switches back to Today).
        // Day/entries changes trigger replay automatically via the key above.
        .onAppear { replayNonce = UUID() }
        .padding()
        .sheet(item: $selectedEntry) { entry in
            FoodEntryDetailSheet(entry: entry)
        }
    }

    private var emptyStateOverlay: some View {
        VStack(spacing: 6) {
            Image(systemName: "mic.circle")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text("No food logged today")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Wraps a `SpriteView` whose `BucketScene` is constructed synchronously at init.
/// The parent uses `.id(SceneKey)` on this view, so SwiftUI tears it down and
/// re-inits whenever any reactive input changes — guaranteeing the scene is
/// always built from the latest `entries`. See `PhysicsBucketView` for rationale.
private struct BucketSceneHost: View {
    @State private var scene: BucketScene
    let entries: [FoodLogEntry]
    let budget: Double

    init(entries: [FoodLogEntry], size: CGSize, budget: Double, onTap: @escaping (FoodLogEntry) -> Void) {
        let s = BucketScene(size: size, entries: entries, budget: budget)
        s.scaleMode = .resizeFill
        s.onBubbleTapped = onTap
        _scene = State(initialValue: s)
        self.entries = entries
        self.budget = budget
    }

    private var totalGL: Double { entries.reduce(0) { $0 + $1.computedGL } }

    private var summaryLabel: String {
        if entries.isEmpty { return "GL bucket. No foods logged." }
        let count = entries.count
        let pluralFood = count == 1 ? "food" : "foods"
        return "GL bucket. \(count) \(pluralFood), total \(Int(totalGL.rounded())) out of \(Int(budget)) GL."
    }

    var body: some View {
        SpriteView(
            scene: scene,
            options: [.allowsTransparency],
            debugOptions: []
        )
        .background(Color.clear)
        // Make the SpriteView an accessibility container that summarizes the
        // bucket's contents and exposes each item as a navigable child.
        // SpriteKit nodes don't surface to VoiceOver on their own — without
        // this wrapper the visualization is opaque to assistive tech.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryLabel)
        .accessibilityChildren {
            ForEach(entries, id: \.objectID) { entry in
                Text(BucketSceneHost.itemAccessibilityLabel(for: entry))
                    .accessibilityLabel(BucketSceneHost.itemAccessibilityLabel(for: entry))
            }
        }
    }

    /// Formats a single food row for VoiceOver. Excludes precise grams (the
    /// user can open the detail sheet for that); foregrounds the numbers
    /// most relevant to a daily-budget mental model.
    static func itemAccessibilityLabel(for entry: FoodLogEntry) -> String {
        // referenceFood is the matched canonical food (e.g. "white rice");
        // foodDescription is the raw transcript snippet (e.g. "rice with
        // chicken"). Prefer the former when matched, fall back to the
        // latter so unrecognized entries are still readable.
        let name = entry.referenceFood ?? entry.foodDescription
        let gl = entry.computedGL
        return "\(name), GL \(String(format: "%.1f", gl))"
    }
}

private struct SceneKey: Hashable {
    let replay: UUID
    let dayKey: Date
    let entryIDs: [UUID]
    let width: CGFloat
    let height: CGFloat
    let budget: Double
}

struct GLStatusLabel: View {
    @Environment(\.appTheme) private var theme
    let total: Double
    let budget: Double

    var body: some View {
        let safeBudget = max(budget, 1)
        let over = total > safeBudget
        let primary: Color = over ? theme.harmfulColor : theme.glAccent
        return HStack(spacing: 0) {
            Text("\(Int(total))")
                .font(.system(.title3, design: theme.metricFontDesign, weight: .heavy))
                .foregroundColor(primary)
            Text(" / \(Int(safeBudget))")
                .font(.system(.subheadline, design: theme.metricFontDesign, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .monospacedDigit()
    }
}

// MARK: - SpriteKit Scene

final class BucketScene: SKScene, SKPhysicsContactDelegate {
    private let entries: [FoodLogEntry]
    private let budget: Double
    var onBubbleTapped: ((FoodLogEntry) -> Void)?

    private let haptics = SceneHaptics()
    /// Magnitude of the gravity vector applied to the world (points / s²
    /// in SpriteKit's odd unit system). The accelerometer-driven direction
    /// is multiplied by this each frame so the bucket items roll toward
    /// real-world gravity as the user tilts the device.
    private let gravityMagnitude: CGFloat = 9.0
    private var motionRetained: Bool = false

    // Bucket geometry as fractions of scene size.
    private let bucketWidthFrac: CGFloat = 0.82
    private let bucketHeightFrac: CGFloat = 0.72
    private let bucketBottomFrac: CGFloat = 0.06

    /// Fraction of bucket interior that a full budget actually fills.
    /// Random-pack settled circles occupy ~70–74% of their container; we target
    /// ~78% so a full budget visibly reaches the rim and anything above overflows.
    private let packingFactor: CGFloat = 0.78

    /// Points² per unit of GL — derived from bucket geometry at init.
    private let areaPerUnit: CGFloat
    /// Minimum rendered radius so tiny items remain visible/tappable.
    private let minRadius: CGFloat = 11

    private var nodeToEntry: [ObjectIdentifier: FoodLogEntry] = [:]

    init(size: CGSize, entries: [FoodLogEntry], budget: Double) {
        self.entries = entries.sorted { $0.computedGL > $1.computedGL } // heavy first → small ones pack on top
        self.budget = budget

        let bucketArea = size.width * bucketWidthFrac * size.height * bucketHeightFrac
        self.areaPerUnit = (bucketArea * packingFactor) / CGFloat(max(budget, 1))

        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true

        physicsWorld.gravity = CGVector(dx: 0, dy: -gravityMagnitude)
        physicsWorld.speed = 1.0
        physicsWorld.contactDelegate = self

        MotionGravityController.shared.retain()
        motionRetained = true

        buildBucket()
        scheduleBubbleDrops()
    }

    override func willMove(from view: SKView) {
        if motionRetained {
            MotionGravityController.shared.release()
            motionRetained = false
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        haptics.handleContact(contact)
    }

    override func update(_ currentTime: TimeInterval) {
        // Match world gravity to real-world gravity each frame so items
        // roll inside the bucket as the user tilts the phone.
        let g = MotionGravityController.shared.currentGravity
        physicsWorld.gravity = CGVector(dx: g.dx * gravityMagnitude,
                                        dy: g.dy * gravityMagnitude)
    }

    private func buildBucket() {
        let w = size.width
        let h = size.height

        let bucketW = w * bucketWidthFrac
        let bucketH = h * bucketHeightFrac
        let bucketBottomY = h * bucketBottomFrac
        let bucketLeft = (w - bucketW) / 2
        let bucketRight = bucketLeft + bucketW
        let bucketTop = bucketBottomY + bucketH

        let container = SKShapeNode(
            rect: CGRect(x: bucketLeft, y: bucketBottomY, width: bucketW, height: bucketH),
            cornerRadius: 14
        )
        container.strokeColor = SKColor(white: 0.72, alpha: 1.0)
        container.lineWidth = 2
        container.fillColor = SKColor(white: 0.96, alpha: 1.0)
        container.zPosition = -1
        addChild(container)

        // Bucket walls + floor
        addChild(makeWall(from: CGPoint(x: bucketLeft, y: bucketBottomY),
                          to: CGPoint(x: bucketLeft, y: bucketTop)))
        addChild(makeWall(from: CGPoint(x: bucketRight, y: bucketBottomY),
                          to: CGPoint(x: bucketRight, y: bucketTop)))
        addChild(makeWall(from: CGPoint(x: bucketLeft, y: bucketBottomY),
                          to: CGPoint(x: bucketRight, y: bucketBottomY)))

        // Scene floor — catches overflow after it spills over the rim.
        addChild(makeWall(from: CGPoint(x: -40, y: 2),
                          to: CGPoint(x: w + 40, y: 2)))
    }

    private func makeWall(from a: CGPoint, to b: CGPoint) -> SKNode {
        let node = SKNode()
        let body = SKPhysicsBody(edgeFrom: a, to: b)
        body.friction = 0.3
        body.restitution = 0.1
        body.isDynamic = false
        node.physicsBody = body
        return node
    }

    private func scheduleBubbleDrops() {
        for (i, entry) in entries.enumerated() {
            let delay = 0.08 + Double(i) * 0.12
            run(.wait(forDuration: delay)) { [weak self] in
                self?.dropBubble(for: entry)
            }
        }
    }

    private func dropBubble(for entry: FoodLogEntry) {
        // Area is proportional to GL (with a floor for visibility).
        let area = CGFloat(max(entry.computedGL, 0.2)) * areaPerUnit
        let rawRadius = sqrt(area / .pi)
        let radius = max(minRadius, min(rawRadius, size.width * 0.22))

        let emoji = FoodEmoji.resolve(entry: entry)

        // Container node — carries the physics body and tap target.
        let node = SKNode()
        node.name = "bubble"

        // Faint backing disc so the emoji reads against the bucket fill.
        let disc = SKShapeNode(circleOfRadius: radius)
        disc.fillColor = SKColor(white: 1.0, alpha: 0.85)
        disc.strokeColor = SKColor(white: 0.75, alpha: 0.6)
        disc.lineWidth = 0.8
        disc.zPosition = 0
        node.addChild(disc)

        // Emoji label centered in the disc.
        let label = SKLabelNode(text: emoji)
        label.fontSize = radius * 1.5
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        node.addChild(label)

        // Spawn position: near the top, randomized x inside bucket walls.
        let bucketW = size.width * bucketWidthFrac
        let bucketLeft = (size.width - bucketW) / 2
        let minX = bucketLeft + radius + 4
        let maxX = bucketLeft + bucketW - radius - 4
        let x = CGFloat.random(in: minX...max(minX + 1, maxX))
        let y = size.height - radius - 8
        node.position = CGPoint(x: x, y: y)

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.restitution = 0.15
        body.friction = 0.4
        body.linearDamping = 0.4
        body.angularDamping = 0.5
        body.mass = max(0.1, CGFloat(entry.computedGL) * 0.04)
        body.allowsRotation = true
        // Enable contact callbacks (default mask is 0). 0xFFFFFFFF matches
        // every category — we don't need granularity here, just "this body
        // touched something".
        body.contactTestBitMask = 0xFFFFFFFF
        node.physicsBody = body

        nodeToEntry[ObjectIdentifier(node)] = entry
        addChild(node)

        // Pop-in
        node.setScale(0.4)
        node.run(.scale(to: 1.0, duration: 0.18))
    }

    // MARK: Tap handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let hits = nodes(at: point)
        for node in hits {
            // Walk up to the bubble container (the label/disc are children).
            var candidate: SKNode? = node
            while let n = candidate, n.name != "bubble" {
                candidate = n.parent
            }
            guard let bubble = candidate, let entry = nodeToEntry[ObjectIdentifier(bubble)] else { continue }
            bubble.run(.sequence([
                .scale(to: 1.15, duration: 0.08),
                .scale(to: 1.0, duration: 0.1)
            ]))
            onBubbleTapped?(entry)
            return
        }
    }
}
