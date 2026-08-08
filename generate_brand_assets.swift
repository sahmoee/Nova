import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = NSImage(contentsOf: sourceURL) else {
    fatalError("Could not load source image at \(sourceURL.path)")
}

func pngData(_ image: NSImage) -> Data {
    guard let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
          let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG")
    }
    return data
}

func render(size: CGSize, opaque: Bool = false, draw: () -> Void) -> NSImage {
    let bitmapInfo = opaque
        ? CGImageAlphaInfo.noneSkipLast.rawValue
        : CGImageAlphaInfo.premultipliedLast.rawValue
    let bitmap = CGContext(
        data: nil,
        width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo
    )!
    let context = NSGraphicsContext(cgContext: bitmap, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let rep = NSBitmapImageRep(cgImage: bitmap.makeImage()!)
    rep.size = size
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
}

func write(_ image: NSImage, relativePath: String) {
    let url = root.appendingPathComponent(relativePath)
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try! pngData(image).write(to: url, options: .atomic)
    print("Wrote \(relativePath) [\(Int(image.size.width))×\(Int(image.size.height))]")
}

func aspectFit(_ imageSize: CGSize, in bounds: CGRect, scale: CGFloat = 1) -> CGRect {
    let ratio = min(bounds.width / imageSize.width, bounds.height / imageSize.height) * scale
    let size = CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    return CGRect(x: bounds.midX - size.width / 2,
                  y: bounds.midY - size.height / 2,
                  width: size.width, height: size.height)
}

func drawBackdrop(in rect: CGRect) {
    NSColor.black.setFill()
    rect.fill()
    let glow = NSGradient(colorsAndLocations:
        (NSColor(red: 0.72, green: 0.01, blue: 0.035, alpha: 0.34), 0),
        (NSColor(red: 0.18, green: 0.01, blue: 0.015, alpha: 0.16), 0.48),
        (NSColor.clear, 1)
    )!
    glow.draw(fromCenter: CGPoint(x: rect.midX, y: rect.midY), radius: 0,
              toCenter: CGPoint(x: rect.midX, y: rect.midY), radius: max(rect.width, rect.height) * 0.58,
              options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
}

func squareIcon(_ pixels: Int) -> NSImage {
    let size = CGSize(width: pixels, height: pixels)
    return render(size: size, opaque: true) {
        // The generated concept includes generous presentation padding. Crop that
        // slightly so the N remains identifiable in Spotlight and Settings sizes.
        let overscan = CGFloat(pixels) * 0.14
        source.draw(in: CGRect(x: -overscan, y: -overscan,
                               width: size.width + overscan * 2,
                               height: size.height + overscan * 2),
                    from: .zero, operation: .copy, fraction: 1)
    }
}

func televisionBack(width: Int, height: Int) -> NSImage {
    let size = CGSize(width: width, height: height)
    return render(size: size, opaque: true) { drawBackdrop(in: CGRect(origin: .zero, size: size)) }
}

func televisionFront(width: Int, height: Int) -> NSImage {
    let size = CGSize(width: width, height: height)
    let bounds = CGRect(origin: .zero, size: size)
    return render(size: size) {
        let target = aspectFit(source.size, in: bounds.insetBy(dx: size.width * 0.18,
                                                               dy: size.height * 0.035),
                               scale: 1.12)
        source.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.compositingOperation = .destinationIn
        let mask = NSGradient(colorsAndLocations:
            (NSColor.white, 0),
            (NSColor.white, 0.70),
            (NSColor.white.withAlphaComponent(0.72), 0.84),
            (NSColor.clear, 1)
        )!
        mask.draw(fromCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: 0,
                  toCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: size.height * 0.53,
                  options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}

func topShelf(width: Int, height: Int) -> NSImage {
    let size = CGSize(width: width, height: height)
    let bounds = CGRect(origin: .zero, size: size)
    return render(size: size, opaque: true) {
        // Keep the full shelf black so the square source artwork disappears cleanly
        // into the panorama rather than revealing its source-image boundary.
        NSColor.black.setFill()
        bounds.fill()
        let target = aspectFit(source.size, in: bounds.insetBy(dx: size.width * 0.22,
                                                               dy: size.height * 0.045))
        source.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

let iconRoot = "Nova/Resources/Assets-iOS.xcassets/AppIcon.appiconset"
for pixels in [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024] {
    write(squareIcon(pixels), relativePath: "\(iconRoot)/AppIcon-\(pixels).png")
}
write(squareIcon(1024), relativePath: "Nova/Resources/Brand/Nova-AppIcon-Master.png")

let tvRoot = "Nova/Resources/Assets-tvOS.xcassets/App Icon & Top Shelf Image.brandassets"
write(televisionBack(width: 400, height: 240), relativePath: "\(tvRoot)/App Icon.imagestack/Back.imagestacklayer/Content.imageset/tv_back_1x.png")
write(televisionBack(width: 800, height: 480), relativePath: "\(tvRoot)/App Icon.imagestack/Back.imagestacklayer/Content.imageset/tv_back_2x.png")
write(televisionFront(width: 400, height: 240), relativePath: "\(tvRoot)/App Icon.imagestack/Front.imagestacklayer/Content.imageset/tv_front_1x.png")
write(televisionFront(width: 800, height: 480), relativePath: "\(tvRoot)/App Icon.imagestack/Front.imagestacklayer/Content.imageset/tv_front_2x.png")

write(televisionBack(width: 1280, height: 768), relativePath: "\(tvRoot)/App Store.imagestack/Back.imagestacklayer/Content.imageset/appstore_back.png")
write(televisionFront(width: 1280, height: 768), relativePath: "\(tvRoot)/App Store.imagestack/Front.imagestacklayer/Content.imageset/appstore_front.png")

write(topShelf(width: 1920, height: 720), relativePath: "\(tvRoot)/Top Shelf Image.imageset/TopShelf_1x.png")
write(topShelf(width: 3840, height: 1440), relativePath: "\(tvRoot)/Top Shelf Image.imageset/TopShelf_2x.png")
write(topShelf(width: 2320, height: 720), relativePath: "\(tvRoot)/Top Shelf Image Wide.imageset/TopShelfWide_1x.png")
write(topShelf(width: 4640, height: 1440), relativePath: "\(tvRoot)/Top Shelf Image Wide.imageset/TopShelfWide_2x.png")
write(topShelf(width: 2320, height: 720), relativePath: "Nova/Resources/Brand/Nova-TopShelf-Master.png")
