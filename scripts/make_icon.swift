//
// make_icon.swift
// Renders the QLTextView app icon at a requested pixel size.
//
// Usage:
//   swift scripts/make_icon.swift <out.png> [<size>]
//   defaults: out=icon-preview/icon-1024.png, size=1024
//
// Design is authored in a 1024-unit virtual canvas (bottom-left origin),
// scaled to the requested output size. Concept: blue squircle, tilted
// document with text lines, brass magnifying glass over upper-right of
// the page enlarging the text underneath.

import AppKit
import CoreGraphics

// ---- arg parsing --------------------------------------------------------

let outPath: String = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon-preview/icon-1024.png"
let size: Int = CommandLine.arguments.count > 2
    ? (Int(CommandLine.arguments[2]) ?? 1024)
    : 1024

// ---- helpers ------------------------------------------------------------

let rgb = CGColorSpaceCreateDeviceRGB()

func gradient(_ stops: [(CGFloat, NSColor)]) -> CGGradient {
    let colors = stops.map { $0.1.cgColor } as CFArray
    let locs   = stops.map { $0.0 }
    return CGGradient(colorsSpace: rgb, colors: colors, locations: locs)!
}

extension CGContext {
    func withSaved(_ body: (CGContext) -> Void) {
        saveGState(); body(self); restoreGState()
    }
}

// ---- the drawing --------------------------------------------------------

func drawIcon(_ cg: CGContext) {

    // --- background squircle -----------------------------------------
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185,
                          transform: nil)

    // shadow under the squircle
    cg.withSaved { c in
        c.setShadow(offset: CGSize(width: 0, height: -28),
                    blur: 40,
                    color: NSColor.black.withAlphaComponent(0.30).cgColor)
        c.setFillColor(NSColor.white.cgColor)
        c.addPath(bodyPath); c.fillPath()
    }

    // gradient fill clipped to squircle
    cg.withSaved { c in
        c.addPath(bodyPath); c.clip()
        let bgGrad = gradient([
            (0.0, NSColor(red: 0.37, green: 0.66, blue: 0.94, alpha: 1)),
            (1.0, NSColor(red: 0.13, green: 0.38, blue: 0.74, alpha: 1)),
        ])
        c.drawLinearGradient(bgGrad,
                             start: CGPoint(x: 512, y: 924),
                             end:   CGPoint(x: 512, y: 100),
                             options: [])

        // soft top sheen
        let sheen = gradient([
            (0.0, NSColor.white.withAlphaComponent(0.28)),
            (1.0, NSColor.white.withAlphaComponent(0.00)),
        ])
        c.drawLinearGradient(sheen,
                             start: CGPoint(x: 512, y: 924),
                             end:   CGPoint(x: 512, y: 560),
                             options: [])
    }

    // --- document / page ---------------------------------------------
    // Tilt the page slightly CCW around its center.
    let pageRect = CGRect(x: 260, y: 192, width: 540, height: 700)
    let pageCenter = CGPoint(x: pageRect.midX, y: pageRect.midY)

    cg.withSaved { c in
        c.translateBy(x: pageCenter.x, y: pageCenter.y)
        c.rotate(by: -6.5 * .pi / 180)
        c.translateBy(x: -pageCenter.x, y: -pageCenter.y)

        // page shadow + fill (with dog-eared top-right corner)
        let fold: CGFloat = 90
        let pagePath = CGMutablePath()
        pagePath.move(to: CGPoint(x: pageRect.minX, y: pageRect.minY))
        pagePath.addLine(to: CGPoint(x: pageRect.maxX, y: pageRect.minY))
        pagePath.addLine(to: CGPoint(x: pageRect.maxX, y: pageRect.maxY - fold))
        pagePath.addLine(to: CGPoint(x: pageRect.maxX - fold, y: pageRect.maxY))
        pagePath.addLine(to: CGPoint(x: pageRect.minX, y: pageRect.maxY))
        pagePath.closeSubpath()

        c.withSaved { c2 in
            c2.setShadow(offset: CGSize(width: 0, height: -10),
                         blur: 26,
                         color: NSColor.black.withAlphaComponent(0.30).cgColor)
            c2.setFillColor(NSColor(white: 0.985, alpha: 1).cgColor)
            c2.addPath(pagePath); c2.fillPath()
        }

        // fold triangle (visually the underside of the corner)
        let foldPath = CGMutablePath()
        foldPath.move(to: CGPoint(x: pageRect.maxX, y: pageRect.maxY - fold))
        foldPath.addLine(to: CGPoint(x: pageRect.maxX - fold, y: pageRect.maxY - fold))
        foldPath.addLine(to: CGPoint(x: pageRect.maxX - fold, y: pageRect.maxY))
        foldPath.closeSubpath()
        c.setFillColor(NSColor(white: 0.88, alpha: 1).cgColor)
        c.addPath(foldPath); c.fillPath()

        // text lines (gray bars of varied length)
        let lineColor = NSColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1)
        c.setFillColor(lineColor.cgColor)
        let lineHeight: CGFloat = 30
        let lineGap:    CGFloat = 60
        let leftPad:    CGFloat = 48
        let rightPad:   CGFloat = 48
        let usableWidth = pageRect.width - leftPad - rightPad
        let lineWidths: [CGFloat] = [0.88, 0.70, 0.96, 0.55, 0.82, 0.92, 0.48, 0.75]
        var y = pageRect.maxY - 110
        for w in lineWidths {
            let r = CGRect(x: pageRect.minX + leftPad,
                           y: y, width: usableWidth * w, height: lineHeight)
            let lp = CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)
            c.addPath(lp); c.fillPath()
            y -= lineGap
        }
    }

    // --- magnifying glass --------------------------------------------
    let lensCenter = CGPoint(x: 650, y: 600)
    let lensOuterR: CGFloat = 200       // outer ring
    let ringWidth:  CGFloat = 44
    let lensGlassR: CGFloat = lensOuterR - ringWidth

    // soft shadow disk for the whole instrument
    cg.withSaved { c in
        c.setShadow(offset: CGSize(width: 0, height: -16),
                    blur: 32,
                    color: NSColor.black.withAlphaComponent(0.38).cgColor)
        c.setFillColor(NSColor.black.cgColor)
        let s = CGRect(x: lensCenter.x - lensOuterR,
                       y: lensCenter.y - lensOuterR,
                       width: lensOuterR*2, height: lensOuterR*2)
        c.fillEllipse(in: s)
    }

    // handle (brass), drawn before glass so glass overlaps it cleanly
    let handleAngle: CGFloat = -42 * .pi / 180   // toward lower-right
    let handleStart = CGPoint(x: lensCenter.x + cos(handleAngle) * (lensOuterR - 6),
                              y: lensCenter.y + sin(handleAngle) * (lensOuterR - 6))
    let handleLen:  CGFloat = 240
    let handleEnd = CGPoint(x: handleStart.x + cos(handleAngle) * handleLen,
                            y: handleStart.y + sin(handleAngle) * handleLen)
    cg.withSaved { c in
        // outer dark brass
        c.setLineCap(.round)
        c.setLineWidth(64)
        c.setStrokeColor(NSColor(red: 0.42, green: 0.26, blue: 0.10, alpha: 1).cgColor)
        c.move(to: handleStart); c.addLine(to: handleEnd); c.strokePath()
        // brass body
        c.setLineWidth(48)
        c.setStrokeColor(NSColor(red: 0.78, green: 0.55, blue: 0.22, alpha: 1).cgColor)
        c.move(to: handleStart); c.addLine(to: handleEnd); c.strokePath()
        // highlight stripe
        c.setLineWidth(14)
        c.setStrokeColor(NSColor(red: 1.00, green: 0.86, blue: 0.55, alpha: 1).cgColor)
        let dx = cos(handleAngle + .pi / 2) * 10
        let dy = sin(handleAngle + .pi / 2) * 10
        c.move(to: CGPoint(x: handleStart.x + dx, y: handleStart.y + dy))
        c.addLine(to: CGPoint(x: handleEnd.x + dx, y: handleEnd.y + dy))
        c.strokePath()
    }

    // glass interior — pale and clipped
    cg.withSaved { c in
        let inner = CGRect(x: lensCenter.x - lensGlassR,
                           y: lensCenter.y - lensGlassR,
                           width: lensGlassR*2, height: lensGlassR*2)
        c.addEllipse(in: inner); c.clip()

        // background of glass: pale paper tone (slight tint)
        c.setFillColor(NSColor(red: 0.97, green: 0.99, blue: 1.00, alpha: 1).cgColor)
        c.fill(inner)

        // magnified text lines (chunkier bars, rounded)
        c.setFillColor(NSColor(red: 0.40, green: 0.46, blue: 0.55, alpha: 1).cgColor)
        let mh: CGFloat = 46
        let mg: CGFloat = 86
        let mWidths: [CGFloat] = [0.92, 0.68, 0.84]
        var my = lensCenter.y + mg
        for w in mWidths {
            let usable = lensGlassR * 2 - 50
            let r = CGRect(x: lensCenter.x - usable / 2,
                           y: my - mh / 2,
                           width: usable * w, height: mh)
            let p = CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil)
            c.addPath(p); c.fillPath()
            my -= mg
        }

        // glassy highlight: upper-left crescent
        let highlight = gradient([
            (0.00, NSColor.white.withAlphaComponent(0.65)),
            (0.55, NSColor.white.withAlphaComponent(0.10)),
            (1.00, NSColor.white.withAlphaComponent(0.00)),
        ])
        c.drawRadialGradient(
            highlight,
            startCenter: CGPoint(x: lensCenter.x - lensGlassR * 0.45,
                                 y: lensCenter.y + lensGlassR * 0.45),
            startRadius: 0,
            endCenter:   CGPoint(x: lensCenter.x - lensGlassR * 0.45,
                                 y: lensCenter.y + lensGlassR * 0.45),
            endRadius:   lensGlassR * 0.85,
            options: [])
    }

    // brass ring with shading
    cg.withSaved { c in
        // outer dark edge
        c.setLineWidth(ringWidth + 8)
        c.setStrokeColor(NSColor(red: 0.32, green: 0.18, blue: 0.06, alpha: 1).cgColor)
        c.strokeEllipse(in: CGRect(x: lensCenter.x - lensOuterR + ringWidth/2,
                                   y: lensCenter.y - lensOuterR + ringWidth/2,
                                   width: (lensOuterR - ringWidth/2) * 2,
                                   height: (lensOuterR - ringWidth/2) * 2))
        // main brass
        c.setLineWidth(ringWidth)
        c.setStrokeColor(NSColor(red: 0.78, green: 0.55, blue: 0.22, alpha: 1).cgColor)
        c.strokeEllipse(in: CGRect(x: lensCenter.x - lensOuterR + ringWidth/2,
                                   y: lensCenter.y - lensOuterR + ringWidth/2,
                                   width: (lensOuterR - ringWidth/2) * 2,
                                   height: (lensOuterR - ringWidth/2) * 2))
    }

    // top sheen on the ring
    cg.withSaved { c in
        let outer = CGRect(x: lensCenter.x - lensOuterR,
                           y: lensCenter.y - lensOuterR,
                           width: lensOuterR*2, height: lensOuterR*2)
        let inner = CGRect(x: lensCenter.x - lensGlassR,
                           y: lensCenter.y - lensGlassR,
                           width: lensGlassR*2, height: lensGlassR*2)
        let ring = CGMutablePath()
        ring.addEllipse(in: outer)
        ring.addEllipse(in: inner)
        c.addPath(ring); c.clip(using: .evenOdd)

        let sheenGrad = gradient([
            (0.0, NSColor.white.withAlphaComponent(0.70)),
            (1.0, NSColor.white.withAlphaComponent(0.00)),
        ])
        c.drawLinearGradient(sheenGrad,
                             start: CGPoint(x: lensCenter.x, y: lensCenter.y + lensOuterR),
                             end:   CGPoint(x: lensCenter.x, y: lensCenter.y + lensGlassR - 20),
                             options: [])
    }
}

// ---- run ----------------------------------------------------------------

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 32
) else { fatalError("could not allocate bitmap rep") }

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("could not create graphics context")
}
NSGraphicsContext.current = ctx
let cg = ctx.cgContext
let scale = CGFloat(size) / 1024
cg.scaleBy(x: scale, y: scale)
drawIcon(cg)
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
let url = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
try data.write(to: url)
print("wrote \(outPath) at \(size)x\(size) (\(data.count) bytes)")
