import SwiftUI
import SpriteKit
import UIKit

/// Prototype A (v2): Physics-based Daily GL Bucket.
/// Bubbles drop from the top and settle into a bucket under gravity.
/// Bubbles that exceed the bucket capacity overflow the rim and fall outside.
/// Tap any bubble to see food details.
struct PhysicsBucketView: View {
    let entries: [FoodLogEntry]
    let budget: Double = dailyGLBudgetUI

    @State private var selectedEntry: FoodLogEntry?
    @State private var sceneID = UUID()

    private var totalGL: Double { entries.reduce(0) { $0 + $1.computedGL } }
    private var fillFraction: Double { min(totalGL / budget, 1.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's GL Bucket")
                        .font(.headline)
                    Text("Tap a bubble to see what's inside")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                GLStatusLabel(total: totalGL, budget: budget)
            }

            GeometryReader { geo in
                ZStack {
                    SpriteView(
                        scene: makeScene(size: geo.size),
                        options: [.allowsTransparency],
                        debugOptions: []
                    )
                    .id(sceneID)
                    .background(Color.clear)

                    if entries.isEmpty {
                        emptyStateOverlay
                    }
                }
            }
            .aspectRatio(0.72, contentMode: .fit)

            // Fill bar
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
                        sceneID = UUID() // replay the drop
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

// MARK: - SpriteKit Scene

final class BucketScene: SKScene {
    private let entries: [FoodLogEntry]
    private let budget: Double
    var onBubbleTapped: ((FoodLogEntry) -> Void)?

    // Bucket geometry (fractions of scene size)
    private let bucketWidthFrac: CGFloat = 0.78
    private let bucketHeightFrac: CGFloat = 0.68
    private let bucketBottomFrac: CGFloat = 0.08   // bottom of bucket above scene floor
    private let wallThickness: CGFloat = 3

    // Lookup: node → entry
    private var nodeToEntry: [ObjectIdentifier: FoodLogEntry] = [:]

    init(size: CGSize, entries: [FoodLogEntry], budget: Double) {
        self.entries = entries.sorted { $0.computedGL > $1.computedGL } // heaviest first (so small ones pack later)
        self.budget = budget
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

    // Bucket shape: open top, two side walls, floor. A wider floor outside catches overflow.
    private func buildBucket() {
        let w = size.width
        let h = size.height

        let bucketW = w * bucketWidthFrac
        let bucketH = h * bucketHeightFrac
        let bucketBottomY = h * bucketBottomFrac
        let bucketLeft = (w - bucketW) / 2
        let bucketRight = bucketLeft + bucketW
        let bucketTop = bucketBottomY + bucketH

        // Visual container
        let container = SKShapeNode(rect: CGRect(x: bucketLeft, y: bucketBottomY, width: bucketW, height: bucketH), cornerRadius: 12)
        container.strokeColor = SKColor(white: 0.75, alpha: 1.0)
        container.lineWidth = 2
        container.fillColor = SKColor(white: 0.96, alpha: 1.0)
        container.zPosition = -1
        addChild(container)

        // Container label
        let topHint = SKLabelNode(text: "100 GL")
        topHint.fontName = "SFProRounded-Semibold"
        topHint.fontSize = 10
        topHint.fontColor = SKColor(white: 0.55, alpha: 1.0)
        topHint.position = CGPoint(x: bucketRight - 20, y: bucketTop - 14)
        topHint.horizontalAlignmentMode = .right
        addChild(topHint)

        // Physics walls: left, right, bottom (floor INSIDE bucket), and scene floor (for overflow)
        let leftWall = makeWall(from: CGPoint(x: bucketLeft, y: bucketBottomY),
                                to: CGPoint(x: bucketLeft, y: bucketTop))
        let rightWall = makeWall(from: CGPoint(x: bucketRight, y: bucketBottomY),
                                 to: CGPoint(x: bucketRight, y: bucketTop))
        let floor = makeWall(from: CGPoint(x: bucketLeft, y: bucketBottomY),
                             to: CGPoint(x: bucketRight, y: bucketBottomY))

        // Scene floor — catches overflow bubbles after they spill over the rim
        let sceneFloor = makeWall(from: CGPoint(x: -20, y: 2),
                                  to: CGPoint(x: w + 20, y: 2))

        addChild(leftWall)
        addChild(rightWall)
        addChild(floor)
        addChild(sceneFloor)
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
        // Drop bubbles one at a time, ~0.12s apart, in heaviest-first order.
        // This gives a visible "pour" animation.
        for (i, entry) in entries.enumerated() {
            let delay = 0.08 + Double(i) * 0.11
            run(.wait(forDuration: delay)) { [weak self] in
                self?.dropBubble(for: entry)
            }
        }
    }

    private func dropBubble(for entry: FoodLogEntry) {
        let radius = CGFloat(max(14, sqrt(max(entry.computedGL, 0.1)) * 5.0))
        let clamped = min(radius, size.width * 0.18)

        let group = FoodGroup.from(string: entry.foodGroup)
        let bubble = SKShapeNode(circleOfRadius: clamped)
        bubble.fillColor = SKColor(group.color).withAlphaComponent(0.88)
        bubble.strokeColor = SKColor(group.color).withAlphaComponent(1.0)
        bubble.lineWidth = 1.5
        bubble.zPosition = 1

        // Spawn near top of scene, slightly random x
        let bucketLeft = (size.width - size.width * bucketWidthFrac) / 2
        let bucketRight = bucketLeft + size.width * bucketWidthFrac
        let minX = bucketLeft + clamped + 4
        let maxX = bucketRight - clamped - 4
        let x = CGFloat.random(in: minX...max(minX + 1, maxX))
        let y = size.height - clamped - 8

        bubble.position = CGPoint(x: x, y: y)

        let body = SKPhysicsBody(circleOfRadius: clamped)
        body.restitution = 0.15
        body.friction = 0.35
        body.linearDamping = 0.35
        body.angularDamping = 0.4
        body.mass = max(0.1, CGFloat(entry.computedGL) * 0.05)
        body.allowsRotation = true
        bubble.physicsBody = body

        // Label on large bubbles
        if clamped > 22 {
            let label = SKLabelNode(text: String(entry.foodDescription.prefix(14)))
            label.fontName = "HelveticaNeue-Bold"
            label.fontSize = min(12, clamped * 0.35)
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.zPosition = 2
            bubble.addChild(label)
        }

        nodeToEntry[ObjectIdentifier(bubble)] = entry
        bubble.name = "bubble"
        addChild(bubble)

        // Tiny pop-in scale
        bubble.setScale(0.4)
        bubble.run(.scale(to: 1.0, duration: 0.18))
    }

    // MARK: Tap handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let hits = nodes(at: point)
        // Topmost bubble wins
        for node in hits.reversed() {
            if node.name == "bubble", let entry = nodeToEntry[ObjectIdentifier(node)] {
                // Small feedback bounce
                node.run(.sequence([
                    .scale(to: 1.15, duration: 0.08),
                    .scale(to: 1.0, duration: 0.1)
                ]))
                onBubbleTapped?(entry)
                return
            }
        }
    }
}
