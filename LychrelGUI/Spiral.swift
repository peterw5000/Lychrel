import CoreGraphics
import Foundation

// Cell geometry for the spiral visualiser, in physical pixels.
struct SpiralStyle: Sendable {
    var cellSize = 4
    var padding = 2

    var pitch: Int { cellSize + padding }
}

// Walks a clockwise square spiral outward from the origin, yielding one grid
// position per number: right 1, down 1, left 2, up 2, right 3, down 3, …
// Uses screen coordinates, so +y is down. The sequence is infinite; use
// prefix(_:) to take as many positions as there are numbers.
struct SpiralWalk: Sequence, IteratorProtocol {
    private static let directions = [(1, 0), (0, 1), (-1, 0), (0, -1)]

    private var x = 0
    private var y = 0
    private var direction = 0
    private var runLength = 1
    private var stepsLeftInRun = 1
    private var runsAtThisLength = 0
    private var started = false

    mutating func next() -> (x: Int, y: Int)? {
        guard started else {
            started = true
            return (0, 0)
        }
        let (dx, dy) = Self.directions[direction]
        x += dx
        y += dy
        stepsLeftInRun -= 1
        if stepsLeftInRun == 0 {
            // Turn clockwise; every second turn the runs get one step longer.
            direction = (direction + 1) % 4
            runsAtThisLength += 1
            if runsAtThisLength == 2 {
                runsAtThisLength = 0
                runLength += 1
            }
            stepsLeftInRun = runLength
        }
        return (x, y)
    }
}

enum SpiralRenderError: Error, LocalizedError {
    case tooLarge(side: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .tooLarge(let side, let limit):
            "The spiral would be \(side) px across, over the \(limit) px limit. Try a smaller range."
        }
    }
}

enum SpiralRenderer {
    // Largest image edge we'll allocate: roughly 7.4 million numbers at the
    // default style. At four bytes per pixel a spiral this size is 1 GB.
    static let maxDimension = 16_384

    // Packs an sRGB colour into a 32-bit pixel in the GPU's native layout
    // (little-endian XRGB, which is B, G, R, X in memory), expressed in
    // `space`. Matching the display's layout and colour space lets Core
    // Animation upload the bitmap as-is instead of converting every pixel on
    // the main thread.
    private static func pixel(red: CGFloat, green: CGFloat, blue: CGFloat, in space: CGColorSpace) -> UInt32 {
        let srgb = CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        let c = srgb.converted(to: space, intent: .defaultIntent, options: nil)?.components ?? [red, green, blue]
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return 0xFF00_0000 | byte(c[0]) << 16 | byte(c[1]) << 8 | byte(c[2])
    }

    // Renders one square per entry in `flags`, in spiral order, coloured red
    // where the flag is set and white otherwise. Index 0 sits at the centre.
    // Pass the display's colour space so the bitmap needs no conversion to be
    // shown; it defaults to sRGB.
    static func render(lychrel flags: [Bool], style: SpiralStyle = SpiralStyle(), colorSpace: CGColorSpace? = nil) throws -> CGImage? {
        guard !flags.isEmpty,
              let space = colorSpace.flatMap({ $0.model == .rgb ? $0 : nil }) ?? CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        var minX = 0, maxX = 0, minY = 0, maxY = 0
        for p in SpiralWalk().prefix(flags.count) {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }

        // Padding goes between cells and around the outer edge.
        let width = (maxX - minX + 1) * style.pitch + style.padding
        let height = (maxY - minY + 1) * style.pitch + style.padding
        let side = max(width, height)
        guard side <= maxDimension else {
            throw SpiralRenderError.tooLarge(side: side, limit: maxDimension)
        }

        // Render straight into the Data the image will wrap, to avoid copying
        // a bitmap that can run to hundreds of megabytes.
        let background = pixel(red: 0.5, green: 0.5, blue: 0.5, in: space)
        let plain = pixel(red: 1, green: 1, blue: 1, in: space)
        let lychrel = pixel(red: 1, green: 0x3B / 255, blue: 0x30 / 255, in: space)

        var pixels = Data(count: width * height * MemoryLayout<UInt32>.stride)
        pixels.withUnsafeMutableBytes { raw in
            let buffer = raw.bindMemory(to: UInt32.self)
            buffer.update(repeating: background)
            for (flag, p) in zip(flags, SpiralWalk()) {
                let value = flag ? lychrel : plain
                let originX = (p.x - minX) * style.pitch + style.padding
                let originY = (p.y - minY) * style.pitch + style.padding
                for row in originY..<(originY + style.cellSize) {
                    let start = row * width + originX
                    buffer[start..<(start + style.cellSize)].update(repeating: value)
                }
            }
        }

        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * MemoryLayout<UInt32>.stride,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
