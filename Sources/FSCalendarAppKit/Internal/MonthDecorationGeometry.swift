#if os(macOS) && !targetEnvironment(macCatalyst)
import Foundation
import CoreGraphics

/// The same boundary supplies the rule and both neighboring fill edges.
/// Coordinates are calculated before mirroring so shared edges remain identical in RTL.
struct MonthBoundaryGeometry {
    let points: [CGPoint]
    let radius: CGFloat

    init(slot: Int, width: CGFloat, rowHeight: CGFloat, scale: CGFloat,
         cornerRadius: CGFloat, internalBoundary: Bool = true) {
        func aligned(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let column = slot % 7
        let offset = internalBoundary ? 0.5 / scale : 0
        let top = aligned(CGFloat(slot / 7) * rowHeight) + offset
        if column == 0 {
            points = [CGPoint(x: 0, y: top), CGPoint(x: width, y: top)]
            radius = 0
        } else {
            let bottom = aligned(CGFloat(slot / 7 + 1) * rowHeight) + offset
            let boundary = min(width, aligned(CGFloat(column) * width / 7) + offset)
            points = [CGPoint(x: 0, y: bottom), CGPoint(x: boundary, y: bottom),
                      CGPoint(x: boundary, y: top), CGPoint(x: width, y: top)]
            let requested = cornerRadius.isFinite ? max(0, cornerRadius) : 8
            radius = internalBoundary ? min(requested, max(0, (bottom - top) / 2), boundary, width - boundary) : 0
        }
    }

    func append(to path: CGMutablePath, reversed: Bool = false, move: Bool = true) {
        let vertices = reversed ? Array(points.reversed()) : points
        if move { path.move(to: vertices[0]) } else { path.addLine(to: vertices[0]) }
        for index in 1..<(vertices.count - 1) {
            if radius > 0 {
                path.addArc(tangent1End: vertices[index], tangent2End: vertices[index + 1], radius: radius)
            } else {
                path.addLine(to: vertices[index])
            }
        }
        path.addLine(to: vertices[vertices.count - 1])
    }
}

struct MonthDecorationGeometry {
    let frame: CGRect
    let path: CGPath

    init(boundary: MonthBoundaryGeometry, width: CGFloat, scale: CGFloat, isRTL: Bool) {
        let outline = CGMutablePath()
        boundary.append(to: outline)
        let bounds = outline.boundingBoxOfPath
        frame = CGRect(x: 0, y: bounds.minY - 0.5 / scale,
                       width: width, height: bounds.height + 1 / scale)
        var transform = CGAffineTransform(a: isRTL ? -1 : 1, b: 0, c: 0, d: 1,
                                          tx: isRTL ? width : 0, ty: -frame.minY)
        path = outline.copy(using: &transform)!
    }

    init(top: MonthBoundaryGeometry, bottom: MonthBoundaryGeometry, width: CGFloat, isRTL: Bool) {
        let outline = CGMutablePath()
        top.append(to: outline)
        bottom.append(to: outline, reversed: true, move: false)
        outline.closeSubpath()
        let bounds = outline.boundingBoxOfPath
        frame = CGRect(x: 0, y: bounds.minY, width: width, height: bounds.height)
        var transform = CGAffineTransform(a: isRTL ? -1 : 1, b: 0, c: 0, d: 1,
                                          tx: isRTL ? width : 0, ty: -frame.minY)
        path = outline.copy(using: &transform)!
    }
}
#endif
