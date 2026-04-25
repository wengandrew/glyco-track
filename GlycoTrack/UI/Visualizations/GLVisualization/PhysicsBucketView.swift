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
    /// even if the entry IDs happen to overlap between days — fixes the
    /// swipe-back-to-today stale-items bug where an `.onChange(of: entryIDs)`
    /// trigger alone wasn't enough because the stale SwiftUI body snapshot
    /// could still feed the old entries into the newly-rebuilt scene.
    let dateKey: Date?
    let budget: Double = dailyGLBudgetUI

    @State private var selectedEntry: FoodLogEntry?
    /// Bumped to force an animation replay without an input change (Replay button,
    /// tab re-appearance). Day/entry changes force replay automatically via
    /// `SceneKey` below — this nonce only covers the "same inputs, replay anyway" cases.
    @State private var replayNonce = UUID()
    @State private var scene: BucketScene?

    init(entries: [FoodLogEntry], dateKey: Date? = nil) {
        self.entries = entries
        self.dateKey = dateKey
    }

    private var totalGL: Double { entries.reduce(0) { $0 + $1.computedGL } }
    private var fillFraction: Double { min(totalGL / budget, 1.0) }
    /// Stable signal for replay-on-new-log.
    private var entryIDs: [UUID] { entries.compactMap { $0.id } }
    /// Day-bucket of `dateKey` (or distantPast if unset) — used so that
    /// intra-day time changes (e.g. a new log at 2:05 pm when we previously
    /// rendered at 2:00 pm) do NOT force extra rebuilds, but day-to-day
    /// navigation does.
    private var dayKey: Date {
        guard let dateKey else { return .distantPast }
        return Calendar.current.startOfDay(for: dateKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                // Key is a pure function of the reactive inputs. Whenever day, entries,
                // size, or replay-nonce changes, both the SpriteView's `.id` and the
                // `.task(id:)` change together — guaranteeing the task re-runs with a
                // fresh `self.entries` capture and the view rebuilds around the new scene.
                // This avoids the SwiftUI race where a UUID-based sceneID could be bumped
                // during a render that still holds stale entries, producing a scene built
                // from yesterday's items that then sticks because the id never changes again.
                let key = SceneKey(
                    replay: replayNonce,
                    dayKey: dayKey,
                    entryIDs: entryIDs,
                    width: geo.size.width,
                    height: geo.size.height
                )
                ZStack {
                    if let scene = scene {
                        SpriteView(
                            scene: scene,
                            options: [.allowsTransparency],
                            debugOptions: []
                        )
                        .background(Color.clear)
                        .id(key)
                    } else {
                        Color.clear
                    }

                    if entries.isEmpty {
                        emptyStateOverlay
                    }
                }
                .task(id: key) {
                    scene = makeScene(size: geo.size)
                }
            }
            .aspectRatio(0.78, contentMode: .fit)
            // Replay when the view reappears (e.g. user switches back to Today).
            // Day/entries changes trigger replay automatically via the key above.
            .onAppear { replayNonce = UUID() }

            // Fill bar + replay
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(height: 8)
                        Capsule()
                            .fill(glGradientColor(fraction: fillFraction))
                            .frame(width: geo.size.width * fillFraction, height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("0").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Button {
                        replayNonce = UUID()
                    } label: {
                        Label("Replay", systemImage: "arrow.clockwise")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                    Spacer()
                    Text("\(Int(budget)) GL budget")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
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

    private func makeScene(size: CGSize) -> BucketScene {
        let scene = BucketScene(size: size, entries: entries, budget: budget)
        scene.scaleMode = .resizeFill
        scene.onBubbleTapped = { entry in
            selectedEntry = entry
        }
        return scene
    }
}

private struct SceneKey: Hashable {
    let replay: UUID
    let dayKey: Date
    let entryIDs: [UUID]
    let width: CGFloat
    let height: CGFloat
}

struct GLStatusLabel: View {
    let total: Double
    let budget: Double

    var body: some View {
        Text("\(Int(total)) / \(Int(budget)) GL")
            .font(.subheadline).fontWeight(.semibold)
            .foregroundColor(total > budget ? .red : .primary)
    }
}

// MARK: - SpriteKit Scene

final class BucketScene: SKScene {
    private let entries: [FoodLogEntry]
    private let budget: Double
    var onBubbleTapped: ((FoodLogEntry) -> Void)?

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

        physicsWorld.gravity = CGVector(dx: 0, dy: -9.0)
        physicsWorld.speed = 1.0

        buildBucket()
        scheduleBubbleDrops()
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

        // Budget label in the top-right corner of the bucket.
        let topHint = SKLabelNode(text: "\(Int(budget)) GL")
        topHint.fontName = "SFProRounded-Semibold"
        topHint.fontSize = 10
        topHint.fontColor = SKColor(white: 0.5, alpha: 1.0)
        topHint.position = CGPoint(x: bucketRight - 20, y: bucketTop - 14)
        topHint.horizontalAlignmentMode = .right
        addChild(topHint)

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
