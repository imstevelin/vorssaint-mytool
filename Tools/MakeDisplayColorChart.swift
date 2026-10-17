// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
let width = 1440, height = 1000
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width*4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ rgb: [CGFloat]) {
    ctx.setFillColor(CGColor(colorSpace: space, components: rgb + [1])!)
    ctx.fill(CGRect(x: x, y: height-y-h, width: w, height: h))
}
func text(_ value: String, _ x: Int, _ y: Int, _ size: CGFloat = 20) {
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1)]))
    ctx.textPosition = CGPoint(x: CGFloat(x), y: CGFloat(height-y)-size)
    CTLineDraw(line, ctx)
}
box(0,0,width,height,[0.94,0.94,0.94])
text("DISPLAY COLOR PATH / VISUAL CHECK",40,26,30)
text("Tagged sRGB  |  Compare at the same brightness  |  Visual aid, not instrument calibration",40,72,18)
text("01  Neutral gray ramp - smooth progression, no color tint",40,122)
for i in 0..<256 { let v = CGFloat(i)/255; box(40+i*5,160,5,85,[v,v,v]) }
text("02  Near-black (0-15) and near-white (240-255) - adjacent steps should remain distinguishable",40,275,18)
for i in 0..<16 {
 let v = CGFloat(i)/255, w = CGFloat(240+i)/255
 box(40+i*40,310,40,70,[v,v,v]); box(720+i*40,310,40,70,[w,w,w])
}
text("03  RGB and complementary colors - compare saturation with HiDPI off / on",40,410)
let colors: [[CGFloat]] = [[1,0,0],[0,1,0],[0,0,1],[0,1,1],[1,0,1],[1,1,0]]
for (index,c) in colors.enumerated() {
 for step in 0..<8 {
  let f=CGFloat(step)/7
  let rgb=c.map { 0.5 + ($0-0.5)*f }
  box(40+index*220,450+step*30,210,30,rgb)
 }
}
text("04  Channel gradients - look for banding, unstable tiles or flickering regions",40,725)
for channel in 0..<3 { for i in 0..<256 {
 var c: [CGFloat]=[0,0,0]; c[channel]=CGFloat(i)/255
 box(40+i*5,765+channel*45,5,40,c)
} }
text("Do not infer Delta E, white-point accuracy or physical gamut from this image alone.",40,930,18)
let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest,image,nil)
precondition(CGImageDestinationFinalize(dest))
print(url.path)
