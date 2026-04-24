import SwiftUI
import SpriteKit
import UIKit

/// Waterline (CL Visualization).
/// A tank with a mid-line "waterline". Harmful items (+CL) sink below; beneficial
/// items (−CL) float above. The water-fill tint and level convey net CL: red-rising
/// when net-harmful, green-settling when net-beneficial.
/// Each item is rendered as a food emoji; area is proportional to |CL|.
struct WaterlineView: View {
    let entries: [FoodLogEntry]

    @State private var selectedEntry: FoodLogEntry?
    @State private var sceneID = UUID()
    @State private var scene: WaterlineScene?

    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }
    private var entryIDs: [UUID] { entries.compactMap { $0.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Waterline")
                    .font(.headline)
                Spacer()
                CLNetLabel(netCL: netCL)
            }

            GeometryReader { geo in
                ZStack {
                    if let scene {
                        SpriteView(
                            scene: scene,
                            options: [.allowsTransparency]
                        )
                        .background(Color.clear)
                        .id(sceneID)
                    } else {
                        Color.clear
                    }
                    if entries.isEmpty { emptyOverlay }
                }
                .task(id: SceneKeyCL(id: sceneID, width: geo.size.width, height: geo.size.height)) {
                    scene = makeScene(size: geo.size)
                }
            }
            .aspectRatio(0.85, contentMode: .fit)
            .onChange(of: entryIDs) { _ in sceneID = UUID() }
            .onAppear { sceneID = UUID() }

            HStack {
                Label("Harmful ↓", systemImage: "arrow.down.circle.fill")
                    .font(.caption2).foregroundColor(.red.opacity(0.8))
                Spacer()
                Button {
                    sceneID = UUID()
                } label: {
                    Label("Replay", systemImage: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
                Spacer()
                Label("Beneficial ↑", systemImage: "arrow.up.circle.fill")
                    .font(.caption2).foregroundColor(.green.opacity(0.8))
            }
        }
        .padding()
        .sheet(item: $selectedEntry) { entry in
            FoodEntryDetailSheet(entry: entry)
        }
    }

    private var emptyOverlay: some View {
        VStack(spacing: 6) {
            Image(systemName: "drop")
                .font(.system(size: 30))
                .foregroundColor(.secondary)
            Text("No CL logged yet")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func makeScene(size: CGSize) -> WaterlineScene {
        let scene = WaterlineScene(size: size, entries: entries)
        scene.scaleMode = .resizeFill
        scene.onItemTapped = { entry in selectedEntry = entry }
        return scene
    }
}

struct SceneKeyCL: Hashable {
    let id: UUID
    let width: CGFloat
    let height: CGFloat
}

// MARK: - Scene

final class WaterlineScene: SKScene {
    private let entries: [FoodLogEntry]
    var onItemTapped: ((FoodLogEntry) -> Void)?

    private let containerInset: CGFloat = 8
    /// Scale factor converting |CL| units to points² of emoji area.
    /// Tuned so that a typical "big" harmful/beneficial day looks substantial
    /// but individual items don't blow past a quarter of the tank.
    private let areaPerCLUnit: CGFloat = 400
    private let minRadius: CGFloat = 14
    /// Scale reference for water level movement: |netCL| of this size reaches full swing.
    private let fullSwingCL: CGFloat = 20

    private var nodeToEntry: [ObjectIdentifier: FoodLogEntry] = [:]
    private var waterFill: SKShapeNode?
    private let netCL: CGFloat
    // Per-frame buoyancy is applied via a separate bitmask so items that should
    // float (harmful) are distinguished from items that should sink (beneficial).
    // Default SKPhysicsBody.categoryBitMask is 0xFFFFFFFF, so we explicitly set
    // both categories — relying on the default breaks the category check.
    private let floatCategory: UInt32 = 1 << 0
    private let sinkCategory: UInt32 = 1 << 1
    private var waterTopY: CGFloat = 0

    init(size: CGSize, entries: [FoodLogEntry]) {
        self.entries = entries
        self.netCL = CGFloat(entries.reduce(0.0) { $0 + $1.computedCL })
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true

        physicsWorld.gravity = CGVector(dx: 0, dy: -6.0)

        buildContainer()
        drawWater()
        drawZeroLine()
        scheduleItemDrops()
    }

    private var containerRect: CGRect {
        CGRect(x: containerInset, y: containerInset,
               width: size.width - containerInset * 2,
               height: size.height - containerInset * 2)
    }

    private func buildContainer() {
        let rect = containerRect
        let container = SKShapeNode(rect: rect, cornerRadius: 14)
        container.strokeColor = SKColor(white: 0.72, alpha: 1.0)
        container.lineWidth = 1.5
        container.fillColor = SKColor(white: 0.98, alpha: 1.0)
        container.zPosition = -2
        addChild(container)

        // Walls: left, right, top, bottom as edge bodies.
        addChild(wall(from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.minX, y: rect.maxY)))
        addChild(wall(from: CGPoint(x: rect.maxX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY)))
        addChild(wall(from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.minY)))
        addChild(wall(from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.maxY)))
    }

    private func wall(from a: CGPoint, to b: CGPoint) -> SKNode {
        let n = SKNode()
        let body = SKPhysicsBody(edgeFrom: a, to: b)
        body.friction = 0.2
        body.restitution = 0.15
        body.isDynamic = false
        n.physicsBody = body
        return n
    }

    /// Water fill: a subtle tinted rectangle whose top edge moves with net CL.
    /// netCL > 0 (harmful) → water rises toward top and tints red.
    /// netCL < 0 (beneficial) → water recedes toward bottom and tints green.
    private func drawWater() {
        let rect = containerRect
        let mid = rect.midY
        let clamped = max(-fullSwingCL, min(netCL, fullSwingCL)) / fullSwingCL
        // Offset above/below the centerline.
        let halfHeight = rect.height / 2
        let waterTop = mid + clamped * halfHeight * 0.9
        self.waterTopY = waterTop
        let waterRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(4, waterTop - rect.minY))
        let tint: SKColor = netCL > 0.5 ? SKColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 0.14) :
                            netCL < -0.5 ? SKColor(red: 0.25, green: 0.7, blue: 0.4, alpha: 0.14) :
                                           SKColor(white: 0.6, alpha: 0.10)
        let fill = SKShapeNode(rect: waterRect, cornerRadius: 10)
        fill.fillColor = tint
        fill.strokeColor = .clear
        fill.zPosition = -1
        addChild(fill)
        waterFill = fill

        // Waterline indicator at the current water top
        let line = SKShapeNode(rect: CGRect(x: rect.minX + 4, y: waterTop - 0.5, width: rect.width - 8, height: 1))
        line.fillColor = SKColor(white: 0.55, alpha: 0.5)
        line.strokeColor = .clear
        line.zPosition = -1
        addChild(line)
    }

    /// Dashed zero-reference line at vertical midpoint for orientation.
    private func drawZeroLine() {
        let rect = containerRect
        let y = rect.midY
        let dashCount = 18
        let dashW = (rect.width - 8) / CGFloat(dashCount * 2)
        for i in 0..<dashCount {
            let x = rect.minX + 4 + CGFloat(i * 2) * dashW
            let dash = SKShapeNode(rect: CGRect(x: x, y: y, width: dashW, height: 0.8))
            dash.fillColor = SKColor(white: 0.4, alpha: 0.4)
            dash.strokeColor = .clear
            dash.zPosition = -1
            addChild(dash)
        }
        let label = SKLabelNode(text: "0")
        label.fontName = "SFProRounded-Semibold"
        label.fontSize = 9
        label.fontColor = SKColor(white: 0.45, alpha: 1.0)
        label.position = CGPoint(x: rect.minX + 8, y: y + 3)
        label.horizontalAlignmentMode = .left
        addChild(label)
    }

    private func scheduleItemDrops() {
        let sorted = entries.sorted { abs($0.computedCL) > abs($1.computedCL) }
        for (i, entry) in sorted.enumerated() {
            run(.wait(forDuration: 0.06 + Double(i) * 0.1)) { [weak self] in
                self?.addItem(for: entry)
            }
        }
    }

    private func addItem(for entry: FoodLogEntry) {
        let cl = CGFloat(entry.computedCL)
        let magnitude = abs(cl)
        guard magnitude > 0.01 else { return }
        let area = magnitude * areaPerCLUnit
        let rawRadius = sqrt(area / .pi)
        let radius = max(minRadius, min(rawRadius, size.width * 0.22))

        let emoji = FoodEmoji.resolve(entry: entry)
        let rect = containerRect

        let node = SKNode()
        node.name = "item"

        let disc = SKShapeNode(circleOfRadius: radius)
        disc.fillColor = SKColor(white: 1.0, alpha: 0.9)
        disc.strokeColor = cl > 0 ? SKColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 0.7) :
                                    SKColor(red: 0.25, green: 0.7, blue: 0.4, alpha: 0.7)
        disc.lineWidth = 1.2
        disc.zPosition = 0
        node.addChild(disc)

        let label = SKLabelNode(text: emoji)
        label.fontSize = radius * 1.5
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        node.addChild(label)

        // Spawn position: harmful items sink from the top, beneficial items rise
        // from the bottom — each spawns in the half it's leaving so the motion reads.
        let marginX: CGFloat = radius + 4
        let x = CGFloat.random(in: (rect.minX + marginX)...(rect.maxX - marginX))
        let y: CGFloat
        if cl > 0 {
            y = CGFloat.random(in: (rect.midY + radius + 4)...(rect.maxY - radius - 4))
        } else {
            y = CGFloat.random(in: (rect.minY + radius + 4)...(rect.midY - radius - 4))
        }
        node.position = CGPoint(x: x, y: y)

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.restitution = 0.25
        body.friction = 0.25
        body.linearDamping = 0.9 // water-like resistance
        body.angularDamping = 0.9
        body.mass = max(0.1, magnitude * 0.04)
        body.allowsRotation = true
        // Beneficial floats (cl < 0 → floatCategory); harmful sinks (cl > 0 → sinkCategory).
        // BOTH branches must set the mask explicitly — the default (0xFFFFFFFF) matches
        // every category, which leaks buoyancy onto items that should sink.
        body.categoryBitMask = (cl < 0) ? floatCategory : sinkCategory
        node.physicsBody = body

        nodeToEntry[ObjectIdentifier(node)] = entry
        addChild(node)

        node.setScale(0.4)
        node.run(.scale(to: 1.0, duration: 0.18))
    }

    override func update(_ currentTime: TimeInterval) {
        // Density-based buoyancy: beneficial items are modelled as low density (they
        // rise when submerged); harmful items as high density (they sink under their
        // own weight). Archimedes: force proportional to submerged volume —
        // approximated here by how far below the waterline the item is.
        let gravityMag = abs(physicsWorld.gravity.dy)
        for child in children {
            guard child.name == "item", let body = child.physicsBody else { continue }
            let y = child.position.y
            let submergedDepth = max(0, waterTopY - y)
            // Scale depth to a 0...1 "submerged fraction". Beyond ~60pt submerged
            // buoyancy saturates — prevents runaway force on fully-submerged items.
            let submergedFrac = min(1.0, submergedDepth / 60.0)

            switch body.categoryBitMask {
            case floatCategory:
                // Beneficial = low density → net upward force when below the surface,
                // plus a small constant nudge so items that land exactly on the
                // surface don't stall. Lift must overcome gravity to actually rise.
                let liftAccel = gravityMag * 2.4 * submergedFrac + 0.6
                body.applyForce(CGVector(dx: 0, dy: body.mass * liftAccel))
            case sinkCategory:
                // Harmful = high density → gravity alone already sinks it, so we
                // just add mild extra downward pull while submerged so items settle
                // quickly instead of hovering mid-water.
                let sinkAccel = gravityMag * 0.4 * submergedFrac
                body.applyForce(CGVector(dx: 0, dy: -body.mass * sinkAccel))
            default:
                break
            }
        }
    }

    // MARK: Tap

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        for node in nodes(at: point) {
            var candidate: SKNode? = node
            while let n = candidate, n.name != "item" { candidate = n.parent }
            if let hit = candidate, let entry = nodeToEntry[ObjectIdentifier(hit)] {
                hit.run(.sequence([.scale(to: 1.15, duration: 0.08), .scale(to: 1.0, duration: 0.1)]))
                onItemTapped?(entry)
                return
            }
        }
    }
}

// MARK: - Shared CL labels

struct CLNetLabel: View {
    let netCL: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: netCL > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(netCL > 0 ? .red : .green)
            Text(String(format: "CL %.1f", netCL))
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(netCL > 0 ? .red : .green)
        }
    }
}
