import SwiftUI
import SpriteKit
import UIKit

/// Balance Scale (CL Visualization).
/// A pinned beam with two hanging plates. Food items drop onto the appropriate plate —
/// beneficial (−CL) on the left, harmful (+CL) on the right. Beam rotates naturally
/// from accumulated torque. Item mass is proportional to |CL|.
struct BalanceScaleView: View {
    let entries: [FoodLogEntry]
    /// Date this view represents. Changing the day forces a scene rebuild —
    /// mirrors the fix in PhysicsBucketView for the swipe-back-to-today stale
    /// bubbles bug.
    let dateKey: Date?

    @State private var selectedEntry: FoodLogEntry?
    /// Bumped to force replay without an input change (Replay button, tab re-appearance).
    /// Day/entry changes force replay automatically via the scene key — this nonce only
    /// covers the "same inputs, replay anyway" cases.
    @State private var replayNonce = UUID()
    @State private var scene: BalanceScene?

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
                Text("Balance")
                    .font(.headline)
                Spacer()
                CLNetLabel(netCL: netCL)
            }

            GeometryReader { geo in
                // Pure-function scene key — see PhysicsBucketView for the rationale.
                // Including dayKey + entryIDs in both the SpriteView `.id` and the
                // `.task(id:)` guarantees the scene rebuilds with fresh entries when
                // the user navigates between days, avoiding the stale-capture race
                // where a UUID-based id could be bumped during a render that still
                // held yesterday's entries.
                let key = SceneKeyCL(
                    replay: replayNonce,
                    dayKey: dayKey,
                    entryIDs: entryIDs,
                    width: geo.size.width,
                    height: geo.size.height
                )
                ZStack {
                    if let scene {
                        SpriteView(scene: scene, options: [.allowsTransparency])
                            .background(Color.clear)
                            .id(key)
                    } else {
                        Color.clear
                    }
                    if entries.isEmpty { emptyOverlay }
                }
                .task(id: key) {
                    scene = makeScene(size: geo.size)
                }
            }
            .aspectRatio(1.3, contentMode: .fit)
            .onAppear { replayNonce = UUID() }

            HStack {
                Label("Beneficial", systemImage: "leaf.fill")
                    .font(.caption2).foregroundColor(.green.opacity(0.8))
                Spacer()
                Button {
                    replayNonce = UUID()
                } label: {
                    Label("Replay", systemImage: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
                Spacer()
                Label("Harmful", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundColor(.red.opacity(0.8))
            }

            Text(netCL < -0.5 ? "Your choices are net beneficial for heart health." :
                 netCL > 0.5 ? "Your choices are net harmful for heart health." :
                 "Your cholesterol impact is roughly neutral.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .sheet(item: $selectedEntry) { entry in
            FoodEntryDetailSheet(entry: entry)
        }
    }

    private var emptyOverlay: some View {
        VStack(spacing: 6) {
            Image(systemName: "scalemass")
                .font(.system(size: 30))
                .foregroundColor(.secondary)
            Text("No CL logged yet")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func makeScene(size: CGSize) -> BalanceScene {
        let scene = BalanceScene(size: size, entries: entries)
        scene.scaleMode = .resizeFill
        scene.onItemTapped = { entry in selectedEntry = entry }
        return scene
    }
}

// MARK: - Scene

final class BalanceScene: SKScene {
    private let entries: [FoodLogEntry]
    var onItemTapped: ((FoodLogEntry) -> Void)?

    private var beamNode: SKNode?
    private var nodeToEntry: [ObjectIdentifier: FoodLogEntry] = [:]

    // Tuning
    private let areaPerCLUnit: CGFloat = 350
    private let minRadius: CGFloat = 13
    private let itemMassPerCL: CGFloat = 0.6

    init(size: CGSize, entries: [FoodLogEntry]) {
        self.entries = entries
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true

        physicsWorld.gravity = CGVector(dx: 0, dy: -8.0)
        physicsWorld.speed = 1.0

        buildStand()
        buildBeamAndPlates()
        scheduleItemDrops()
    }

    // Positions (derived from scene size)
    private var pivotPos: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.32) }
    private var beamLength: CGFloat { size.width * 0.75 }
    private var beamThickness: CGFloat { 6 }
    private var plateWidth: CGFloat { size.width * 0.28 }
    private var plateThickness: CGFloat { 4 }
    /// Vertical distance from beam center up to each plate's slab. Plates sit
    /// ABOVE the beam so items falling from the top land in the cup formed by
    /// the slab + lips, instead of bouncing off the beam.
    private var plateLift: CGFloat { size.height * 0.08 }
    private var lipHeight: CGFloat { size.height * 0.12 }
    private var lipThickness: CGFloat { 2 }

    /// Build the static stand (post + base + pivot).
    private func buildStand() {
        let standColor = SKColor(white: 0.55, alpha: 1.0)

        // Vertical post
        let post = SKShapeNode(rect: CGRect(x: pivotPos.x - 3, y: 20, width: 6, height: pivotPos.y - 20), cornerRadius: 2)
        post.fillColor = standColor
        post.strokeColor = .clear
        post.zPosition = -1
        addChild(post)

        // Base
        let base = SKShapeNode(rect: CGRect(x: pivotPos.x - 40, y: 12, width: 80, height: 10), cornerRadius: 3)
        base.fillColor = standColor
        base.strokeColor = .clear
        base.zPosition = -1
        addChild(base)

        // Pivot cap
        let cap = SKShapeNode(circleOfRadius: 6)
        cap.position = pivotPos
        cap.fillColor = SKColor(white: 0.35, alpha: 1.0)
        cap.strokeColor = .clear
        cap.zPosition = 5
        addChild(cap)

        // Ground floor — catches any runaway items
        addChild(wall(from: CGPoint(x: -40, y: 2), to: CGPoint(x: size.width + 40, y: 2)))
    }

    /// Build the rotating beam + plates as one compound body pinned at the pivot.
    private func buildBeamAndPlates() {
        let beam = SKNode()
        beam.position = pivotPos
        beam.zPosition = 2

        // Visual: beam rectangle
        let beamRect = CGRect(x: -beamLength / 2, y: -beamThickness / 2, width: beamLength, height: beamThickness)
        let beamShape = SKShapeNode(rect: beamRect, cornerRadius: 2)
        beamShape.fillColor = SKColor(white: 0.35, alpha: 1.0)
        beamShape.strokeColor = .clear
        beam.addChild(beamShape)

        // Plate positions relative to beam origin. Plates sit ABOVE the beam
        // so items falling from the top land in the cup.
        let leftCenter = CGPoint(x: -beamLength / 2 + plateWidth / 2, y: plateLift)
        let rightCenter = CGPoint(x: beamLength / 2 - plateWidth / 2, y: plateLift)

        // Visual plates (slabs + lips)
        drawPlateVisual(on: beam, center: leftCenter, color: .green)
        drawPlateVisual(on: beam, center: rightCenter, color: .red)

        // Compound physics body: beam rectangle + each plate (slab + 2 lips).
        let beamBody = SKPhysicsBody(rectangleOf: CGSize(width: beamLength, height: beamThickness))

        let leftSlab = SKPhysicsBody(rectangleOf: CGSize(width: plateWidth, height: plateThickness),
                                     center: leftCenter)
        let leftLipL = SKPhysicsBody(rectangleOf: CGSize(width: lipThickness, height: lipHeight),
                                     center: CGPoint(x: leftCenter.x - plateWidth / 2 + lipThickness / 2,
                                                     y: leftCenter.y + lipHeight / 2))
        let leftLipR = SKPhysicsBody(rectangleOf: CGSize(width: lipThickness, height: lipHeight),
                                     center: CGPoint(x: leftCenter.x + plateWidth / 2 - lipThickness / 2,
                                                     y: leftCenter.y + lipHeight / 2))

        let rightSlab = SKPhysicsBody(rectangleOf: CGSize(width: plateWidth, height: plateThickness),
                                      center: rightCenter)
        let rightLipL = SKPhysicsBody(rectangleOf: CGSize(width: lipThickness, height: lipHeight),
                                      center: CGPoint(x: rightCenter.x - plateWidth / 2 + lipThickness / 2,
                                                      y: rightCenter.y + lipHeight / 2))
        let rightLipR = SKPhysicsBody(rectangleOf: CGSize(width: lipThickness, height: lipHeight),
                                      center: CGPoint(x: rightCenter.x + plateWidth / 2 - lipThickness / 2,
                                                      y: rightCenter.y + lipHeight / 2))

        let compound = SKPhysicsBody(bodies: [beamBody, leftSlab, leftLipL, leftLipR,
                                              rightSlab, rightLipL, rightLipR])
        compound.mass = 2.0                // heavy enough to resist small items but not immovable
        compound.allowsRotation = true
        compound.angularDamping = 2.5      // keep oscillation under control
        compound.linearDamping = 4.0
        compound.friction = 0.7
        beam.physicsBody = compound
        addChild(beam)
        beamNode = beam

        // Static pivot anchor
        let pivot = SKNode()
        pivot.position = pivotPos
        let pivotBody = SKPhysicsBody(circleOfRadius: 1)
        pivotBody.isDynamic = false
        pivot.physicsBody = pivotBody
        addChild(pivot)

        // Pin joint at the pivot — beam rotates freely around it.
        if let bodyA = pivot.physicsBody, let bodyB = beam.physicsBody {
            let joint = SKPhysicsJointPin.joint(withBodyA: bodyA, bodyB: bodyB, anchor: pivotPos)
            joint.shouldEnableLimits = true
            joint.lowerAngleLimit = -CGFloat.pi / 6   // ±30° tilt
            joint.upperAngleLimit = CGFloat.pi / 6
            joint.frictionTorque = 0.2
            physicsWorld.add(joint)
        }
    }

    private func drawPlateVisual(on parent: SKNode, center: CGPoint, color: SKColor) {
        let slab = SKShapeNode(rect: CGRect(x: center.x - plateWidth / 2, y: center.y - plateThickness / 2,
                                            width: plateWidth, height: plateThickness), cornerRadius: 1.5)
        slab.fillColor = color.withAlphaComponent(0.25)
        slab.strokeColor = color.withAlphaComponent(0.7)
        slab.lineWidth = 1
        parent.addChild(slab)

        // Lips
        for dx in [-plateWidth / 2 + lipThickness / 2, plateWidth / 2 - lipThickness / 2] {
            let lip = SKShapeNode(rect: CGRect(x: center.x + dx - lipThickness / 2, y: center.y,
                                               width: lipThickness, height: lipHeight),
                                  cornerRadius: 1)
            lip.fillColor = color.withAlphaComponent(0.5)
            lip.strokeColor = .clear
            parent.addChild(lip)
        }
    }

    private func wall(from a: CGPoint, to b: CGPoint) -> SKNode {
        let n = SKNode()
        let body = SKPhysicsBody(edgeFrom: a, to: b)
        body.isDynamic = false
        body.friction = 0.3
        n.physicsBody = body
        return n
    }

    // MARK: - Drops

    private func scheduleItemDrops() {
        // Alternate heavier-first across both sides so the beam doesn't swing wildly
        // before the other side loads up.
        let sorted = entries.sorted { abs($0.computedCL) > abs($1.computedCL) }
        for (i, entry) in sorted.enumerated() {
            run(.wait(forDuration: 0.3 + Double(i) * 0.22)) { [weak self] in
                self?.dropItem(for: entry)
            }
        }
    }

    private func dropItem(for entry: FoodLogEntry) {
        let cl = CGFloat(entry.computedCL)
        let magnitude = abs(cl)
        guard magnitude > 0.01 else { return }

        let area = magnitude * areaPerCLUnit
        let rawRadius = sqrt(area / .pi)
        let radius = max(minRadius, min(rawRadius, plateWidth / 2 - 4))

        let emoji = FoodEmoji.resolve(entry: entry)

        let node = SKNode()
        node.name = "item"

        let disc = SKShapeNode(circleOfRadius: radius)
        disc.fillColor = SKColor(white: 1.0, alpha: 0.95)
        disc.strokeColor = cl > 0 ? SKColor(red: 0.85, green: 0.3, blue: 0.3, alpha: 0.7) :
                                    SKColor(red: 0.25, green: 0.65, blue: 0.4, alpha: 0.7)
        disc.lineWidth = 1.2
        node.addChild(disc)

        let label = SKLabelNode(text: emoji)
        label.fontSize = radius * 1.5
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        node.addChild(label)

        // Spawn above the target plate.
        let side: CGFloat = cl > 0 ? 1 : -1
        let plateCenterX = pivotPos.x + side * (beamLength / 2 - plateWidth / 2)
        let jitter = CGFloat.random(in: -plateWidth / 3 ... plateWidth / 3)
        node.position = CGPoint(x: plateCenterX + jitter, y: size.height - radius - 4)

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.restitution = 0.05
        body.friction = 0.85
        body.linearDamping = 0.3
        body.angularDamping = 0.5
        body.mass = max(0.15, magnitude * itemMassPerCL)
        body.allowsRotation = true
        node.physicsBody = body

        nodeToEntry[ObjectIdentifier(node)] = entry
        addChild(node)

        node.setScale(0.5)
        node.run(.scale(to: 1.0, duration: 0.2))
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
