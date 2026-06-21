import DonpaCore
import SpriteKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// End-of-game board animations, on `effectsLayer` (never wiped by `rebuild()`).
/// Tasteful and quick (<~1s), non-blocking — the board stays interactive for a
/// restart — and respects Reduce Motion.
extension BoardScene {

    static var prefersReducedMotion: Bool {
        #if os(iOS)
        return UIAccessibility.isReduceMotionEnabled
        #elseif os(macOS)
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        return false
        #endif
    }

    private var mineCoords: [Coord] {
        viewModel.game.board.allCoords.filter { viewModel.game.board[$0].isMine }
    }

    func playLoss(trigger: Coord?, reduceMotion: Bool) {
        let cell = layout.cellSize
        let origin = trigger.map { layout.center(of: $0) }

        if let origin {
            effectsLayer.addChild(detonation(at: origin, size: cell))
        }
        if reduceMotion {
            if let origin { effectsLayer.addChild(flash(at: origin, size: cell)) }
            return
        }
        // Other mines pulse, staggered outward from the trigger.
        let speed = cell * 18  // points/sec the shock wave travels
        for c in mineCoords where c != trigger {
            let p = layout.center(of: c)
            let delay = origin.map { hypot(p.x - $0.x, p.y - $0.y) / speed } ?? 0
            let pulse = minePulse(at: p, size: cell)
            pulse.node.run(.sequence([.wait(forDuration: delay), pulse.pulseAction]))
            effectsLayer.addChild(pulse.node)
        }
        shakeBoard()
    }

    func playWin(reduceMotion: Bool) {
        let cell = layout.cellSize
        let board = layout.boardSize(width: viewModel.boardWidth, height: viewModel.boardHeight)
        let centre = CGPoint(x: board.width / 2, y: board.height / 2)

        if reduceMotion {
            let overlay = SKShapeNode(rectOf: CGSize(width: board.width, height: board.height))
            overlay.position = centre
            overlay.fillColor = SKColor.green.withAlphaComponent(0.18)
            overlay.lineWidth = 0
            overlay.blendMode = .add
            overlay.alpha = 0
            overlay.run(
                .sequence([
                    .fadeAlpha(to: 0.5, duration: 0.12), .fadeOut(withDuration: 0.35),
                    .removeFromParent(),
                ]))
            effectsLayer.addChild(overlay)
            return
        }
        // Ripple wave: each revealed cell flashes, delayed by distance from centre.
        let speed = cell * 22
        for c in viewModel.game.board.allCoords
        where viewModel.game.board[c].state == .revealed {
            let p = layout.center(of: c)
            let delay = hypot(p.x - centre.x, p.y - centre.y) / speed
            effectsLayer.addChild(winRipple(at: p, size: cell, delay: delay))
        }
    }

    // MARK: Effect node builders

    /// A bright additive burst that scales up then collapses.
    private func detonation(at p: CGPoint, size: CGFloat) -> SKNode {
        let burst = SKShapeNode(circleOfRadius: size * 0.5)
        burst.position = p
        burst.fillColor = SKColor(red: 1, green: 0.5, blue: 0.2, alpha: 1)
        burst.lineWidth = 0
        burst.blendMode = .add
        burst.run(
            .sequence([
                .group([
                    .sequence([.scale(to: 1.9, duration: 0.12), .scale(to: 0.0, duration: 0.20)]),
                    .fadeOut(withDuration: 0.32),
                ]),
                .removeFromParent(),
            ]))
        return burst
    }

    private func flash(at p: CGPoint, size: CGFloat) -> SKNode {
        let rect = SKShapeNode(rectOf: CGSize(width: size, height: size), cornerRadius: 3)
        rect.position = p
        rect.fillColor = .white
        rect.lineWidth = 0
        rect.blendMode = .add
        rect.alpha = 0
        rect.run(
            .sequence([
                .fadeAlpha(to: 0.8, duration: 0.05), .fadeOut(withDuration: 0.18),
                .removeFromParent(),
            ]))
        return rect
    }

    private func minePulse(at p: CGPoint, size: CGFloat) -> (node: SKNode, pulseAction: SKAction) {
        let node = SKShapeNode(circleOfRadius: size * 0.4)
        node.position = p
        node.fillColor = SKColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)
        node.lineWidth = 0
        node.blendMode = .add
        node.alpha = 0
        let pulse = SKAction.sequence([
            .group([
                .sequence([.scale(to: 1.4, duration: 0.10), .scale(to: 1.0, duration: 0.12)]),
                .sequence([.fadeAlpha(to: 0.85, duration: 0.06), .fadeOut(withDuration: 0.22)]),
            ]),
            .removeFromParent(),
        ])
        return (node, pulse)
    }

    private func winRipple(at p: CGPoint, size: CGFloat, delay: TimeInterval) -> SKNode {
        let tile = SKShapeNode(
            rectOf: CGSize(width: size * 0.9, height: size * 0.9), cornerRadius: 3)
        tile.position = p
        tile.fillColor = SKColor.green.withAlphaComponent(0.6)
        tile.lineWidth = 0
        tile.blendMode = .add
        tile.alpha = 0
        tile.run(
            .sequence([
                .wait(forDuration: delay),
                .group([
                    .sequence([.fadeAlpha(to: 0.7, duration: 0.10), .fadeOut(withDuration: 0.22)]),
                    .sequence([.scale(to: 1.15, duration: 0.10), .scale(to: 1.0, duration: 0.12)]),
                ]),
                .removeFromParent(),
            ]))
        return tile
    }

    /// Decaying jitter of the board, snapped back to origin so drift can't
    /// accumulate.
    private func shakeBoard() {
        let origin = boardLayer.position
        let amps: [CGFloat] = [7, -6, 5, -4, 3, -2]
        var steps: [SKAction] = amps.enumerated().map { i, a in
            .moveBy(x: a, y: i.isMultiple(of: 2) ? -a * 0.5 : a * 0.5, duration: 0.035)
        }
        steps.append(.move(to: origin, duration: 0.03))
        boardLayer.run(.sequence(steps))
    }
}
