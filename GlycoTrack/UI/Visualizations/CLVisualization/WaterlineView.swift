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
    /// Date this view represents. Same role as in PhysicsBucketView/BalanceScaleView —
    /// changing the day forces the scene to rebuild even if entry IDs happen to overlap.
    let dateKey: Date?

    @State private var selectedEntry: FoodLogEntry?
    @State private var replayNonce = UUID()

    init(entries: [FoodLogEntry], dateKey: Date? = nil) {
        self.entries = entries
        self.dateKey = dateKey
    }

    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }
    private var entryIDs: [UUID] { entries.compactMap { $0.id } }
    private var dayKey: Date {
        guard let dateKey else { return .distantPast }
        return Calendar.current.startOfDay(for: dateKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Waterline")
                    .font(.headline)
                Spacer()
                CLNetLabel(netCL: netCL)
            }

            GeometryReader { geo in
                // See PhysicsBucketView for the rationale on `.id(key)` + child-view-with-
                // @State (rather than `.task(id:)`).
                let key = SceneKeyCL(
                    replay: replayNonce,
                    dayKey: dayKey,
                    entryIDs: entryIDs,
                    width: geo.size.width,
                    height: geo.size.height
                )
                ZStack {
                    WaterlineSceneHost(
                        entries: entries,
                        size: geo.size,
                        onTap: { selectedEntry = $0 }
                    )
                    .id(key)

                    if entries.isEmpty { emptyOverlay }
                }
            }
            .aspectRatio(0.85, contentMode: .fit)
            .onAppear { replayNonce = UUID() }

            HStack {
                Label("Harmful ↓", systemImage: "arrow.down.circle.fill")
                    .font(.caption2).foregroundColor(.red.opacity(0.8))
                Spacer()
                Button {
                    replayNonce = UUID()
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
}

/// Wraps a `SpriteView` whose `WaterlineScene` is constructed synchronously at init.
/// The parent uses `.id(SceneKeyCL)` on this view — see `PhysicsBucketView` for rationale.
private struct WaterlineSceneHost: View {
    @State private var scene: WaterlineScene
    let entries: [FoodLogEntry]

    init(entries: [FoodLogEntry], size: CGSize, onTap: @escaping (FoodLogEntry) -> Void) {
        let s = WaterlineScene(size: size, entries: entries)
        s.scaleMode = .resizeFill
        s.onItemTapped = onTap
        _scene = State(initialValue: s)
        self.entries = entries
    }

    private var netCL: Double { entries.reduce(0) { $0 + $1.computedCL } }

    private var summaryLabel: String {
        if entries.isEmpty { return "Waterline tank. No foods logged." }
        let direction: String
        if abs(netCL) < 0.05 { direction = "near zero" }
        else if netCL < 0 { direction = "net beneficial" }
        else { direction = "net harmful" }
        return "Waterline tank. Net CL \(String(format: "%+.1f", netCL)), \(direction)."
    }

    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .background(Color.clear)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summaryLabel)
            .accessibilityChildren {
                ForEach(entries, id: \.objectID) { entry in
                    Text(itemLabel(for: entry))
                        .accessibilityLabel(itemLabel(for: entry))
                }
            }
    }

    /// Beneficial CL items rise to the surface, harmful ones sink — the
    /// readout calls out which so a VoiceOver swipe through the tank
    /// preserves the same semantic encoding the visual gives sighted users.
    private func itemLabel(for entry: FoodLogEntry) -> String {
        let name = entry.referenceFood ?? entry.foodDescription
        let cl = entry.computedCL
        let role = cl > 0.05 ? "sinks, harmful" : (cl < -0.05 ? "floats, beneficial" : "neutral")
        return "\(name), CL \(String(format: "%+.1f", cl)), \(role)"
    }
}

/// Pure-function scene key shared by WaterlineView and BalanceScaleView.
/// Including dayKey + entryIDs in the key (rather than a UUID bumped via `.onChange`)
/// avoids the SwiftUI race where the id could be bumped during a render that still
/// captured stale entries — the scene built in that render would then never be replaced
/// even after entries finally updated.
struct SceneKeyCL: Hashable {
    let replay: UUID
    let dayKey: Date
    let entryIDs: [UUID]
    let width: CGFloat
    let height: CGFloat
}

// MARK: - Scene

final class WaterlineScene: SKScene, SKPhysicsContactDelegate {
    private let entries: [FoodLogEntry]
    var onItemTapped: ((FoodLogEntry) -> Void)?

    private let haptics = SceneHaptics()

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
        physicsWorld.contactDelegate = self

        buildContainer()
        drawWater()
        drawZeroLine()
        scheduleItemDrops()
    }

    func didBegin(_ contact: SKPhysicsContact) {
        haptics.handleContact(contact)
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
        let tint: SKColor = netCL > 0.5 ? SKColor.clHarmful.withAlphaComponent(0.14) :
                            netCL < -0.5 ? SKColor.clBeneficial.withAlphaComponent(0.14) :
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
        disc.strokeColor = (cl > 0 ? SKColor.clHarmful : SKColor.clBeneficial)
            .withAlphaComponent(0.7)
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
        body.angularDamping = 0.9
        body.mass = max(0.1, magnitude * 0.04)
        body.allowsRotation = true
        // Beneficial floats (cl < 0 → floatCategory); harmful sinks (cl > 0 → sinkCategory).
        // BOTH branches must set the mask explicitly — the default (0xFFFFFFFF) matches
        // every category, which leaks buoyancy onto items that should sink.
        body.categoryBitMask = (cl < 0) ? floatCategory : sinkCategory
        // Enable contact callbacks so SceneHaptics fires on first wall touch.
        // contactTestBitMask is independent of categoryBitMask (which the
        // buoyancy logic above keys off), so this doesn't disturb sink/float.
        body.contactTestBitMask = 0xFFFFFFFF
        // Floaters: gravity OFF so a small spring force can actually move them up
        // toward the waterline. Previous attempts with gravity-on + Archimedean lift
        // failed because the depth-scaled lift could not reliably overcome gravity
        // through linearDamping = 0.9 for low-mass items. Lower damping too so the
        // spring can do its work; harmful items keep the original water-like damping.
        if cl < 0 {
            body.affectedByGravity = false
            body.linearDamping = 0.6
        } else {
            body.linearDamping = 0.9 // water-like resistance for sinkers
        }
        node.physicsBody = body

        nodeToEntry[ObjectIdentifier(node)] = entry
        addChild(node)

        node.setScale(0.4)
        node.run(.scale(to: 1.0, duration: 0.18))
    }

    override func update(_ currentTime: TimeInterval) {
        // Floaters: spring toward the waterline (gravity disabled on the body).
        // Sinkers: gravity does the work; we just add a mild downward nudge while
        // submerged so they settle quickly instead of hovering mid-water.
        //
        // Why a spring (not depth-scaled Archimedean lift)? Previous attempts that
        // kept gravity on and applied an upward lift force never won net of
        // linearDamping = 0.9 for low-mass items — the floaters never rose. With
        // gravity disabled and a Hooke's-law restoring force, even a tiny mass
        // accelerates back to the waterline; reduced damping (0.6) lets it actually
        // travel before the medium drains kinetic energy.
        let gravityMag = abs(physicsWorld.gravity.dy)
        let springConstant: CGFloat = 6.0
        for child in children {
            guard child.name == "item", let body = child.physicsBody else { continue }
            let y = child.position.y

            switch body.categoryBitMask {
            case floatCategory:
                // displacement > 0 → above water → pull down; displacement < 0 → below → pull up.
                let displacement = y - waterTopY
                let restoreAccel = -displacement * springConstant
                body.applyForce(CGVector(dx: 0, dy: body.mass * restoreAccel))
            case sinkCategory:
                let submergedDepth = max(0, waterTopY - y)
                let submergedFrac = min(1.0, submergedDepth / 60.0)
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
