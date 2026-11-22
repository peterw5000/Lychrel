import AppKit
import QuartzCore
import SwiftUI

// Hosts the spiral bitmap in a Core Animation layer inside a magnifying
// NSScrollView. The bitmap is uploaded to the GPU once; zooming changes only
// the scroll view's magnification transform, so nothing is redrawn per frame.
// (Drawing it through SwiftUI's Image re-rasterised the whole bitmap on the
// CPU every animation frame.)
struct SpiralScrollView: NSViewRepresentable {
    let image: CGImage
    let scaleToFit: Bool
    let displayScale: CGFloat

    func makeNSView(context: Context) -> SpiralNSScrollView {
        SpiralNSScrollView()
    }

    func updateNSView(_ view: SpiralNSScrollView, context: Context) {
        view.show(image, displayScale: displayScale)
        view.setScaleToFit(scaleToFit, animated: context.transaction.animation != nil)
    }
}

final class SpiralNSScrollView: NSScrollView {
    private static let zoomDuration: CFTimeInterval = 0.35

    private let spiralView = SpiralLayerView()
    private var image: CGImage?
    private var fitsToWindow = false
    private var needsCentring = false

    private var zoomStart: (magnification: CGFloat, time: CFTimeInterval)?
    private var zoomLink: CADisplayLink?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = CentringClipView()
        documentView = spiralView
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = false
        // Programmatic magnification works regardless; this also enables
        // pinch-to-zoom.
        allowsMagnification = true
        minMagnification = 0.001
        maxMagnification = 64
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ image: CGImage, displayScale: CGFloat) {
        guard image !== self.image else { return }
        self.image = image
        spiralView.image = image
        // At magnification 1, one bitmap pixel maps to one physical pixel.
        spiralView.frame = CGRect(x: 0, y: 0,
                                  width: CGFloat(image.width) / displayScale,
                                  height: CGFloat(image.height) / displayScale)
        stopZoom()
        magnification = fitsToWindow ? fitMagnification : 1
        // The lower bound sits at the centre of the spiral, so start there.
        needsCentring = true
        centreIfPossible()
    }

    func setScaleToFit(_ fit: Bool, animated: Bool) {
        guard fit != fitsToWindow else { return }
        fitsToWindow = fit
        if animated {
            startZoom()
        } else {
            stopZoom()
            magnification = targetMagnification
            centreOnDocument()
        }
    }

    // Largest uniform magnification at which the whole spiral is visible.
    private var fitMagnification: CGFloat {
        let document = spiralView.frame.size
        guard document.width > 0, document.height > 0 else { return 1 }
        return min(contentSize.width / document.width, contentSize.height / document.height)
    }

    private var targetMagnification: CGFloat {
        fitsToWindow ? fitMagnification : 1
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Keep a fitted spiral fitted as the window resizes. Mid-zoom, the
        // animation reads the new target on its next frame instead.
        if fitsToWindow, zoomLink == nil {
            magnification = fitMagnification
        }
        centreIfPossible()
    }

    // MARK: - Zoom animation

    // Steps the magnification once per display refresh. Each step is just a
    // transform change, so this costs next to nothing on the main thread.
    private func startZoom() {
        zoomStart = (magnification, CACurrentMediaTime())
        if zoomLink == nil {
            let link = displayLink(target: self, selector: #selector(stepZoom(_:)))
            link.add(to: .main, forMode: .common)
            zoomLink = link
        }
    }

    private func stopZoom() {
        zoomLink?.invalidate()
        zoomLink = nil
        zoomStart = nil
    }

    @objc private func stepZoom(_ link: CADisplayLink) {
        guard let start = zoomStart else { return stopZoom() }
        let t = min(1, (link.targetTimestamp - start.time) / Self.zoomDuration)
        let eased = t * t * (3 - 2 * t)
        // Interpolate in log space so zooming feels uniform even across a
        // 30× change in scale.
        let from = log(start.magnification)
        let to = log(targetMagnification)
        magnification = exp(from + (to - from) * eased)
        centreOnDocument()
        if t >= 1 { stopZoom() }
    }

    // MARK: - Centring

    private func centreIfPossible() {
        guard needsCentring, contentSize.width > 0, contentSize.height > 0 else { return }
        needsCentring = false
        centreOnDocument()
    }

    private func centreOnDocument() {
        let document = spiralView.frame
        let visible = contentView.bounds.size
        contentView.scroll(to: NSPoint(x: document.midX - visible.width / 2,
                                       y: document.midY - visible.height / 2))
        reflectScrolledClipView(contentView)
    }
}

// Clip view that centres the document when it's smaller than the viewport,
// rather than pinning it to a corner.
private final class CentringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView?.frame else { return rect }
        if rect.width > document.width {
            rect.origin.x = document.midX - rect.width / 2
        }
        if rect.height > document.height {
            rect.origin.y = document.midY - rect.height / 2
        }
        return rect
    }
}

// Layer-backed view whose layer displays the bitmap directly. Core Animation
// uploads it to the GPU once, then scales it there: nearest-neighbour when enlarging keeps cells crisp, and trilinear
// (mipmapped) filtering when shrinking avoids moiré in the gridlines.
private final class SpiralLayerView: NSView {
    var image: CGImage? {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.contents = image
        layer.contentsGravity = .resize
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .trilinear
    }
}
