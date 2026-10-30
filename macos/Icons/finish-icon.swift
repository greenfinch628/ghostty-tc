import AppKit
import CoreGraphics
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let src = CGImageSourceCreateWithURL(source as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let c = CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
c.scaleBy(x:1024.0/1254.0,y:1024.0/1254.0)
c.setFillColor(CGColor(gray:0.87,alpha:1))
c.addPath(CGPath(roundedRect:CGRect(x:96,y:110,width:1063,height:1034),cornerWidth:220,cornerHeight:220,transform:nil)); c.fillPath()
c.addPath(CGPath(roundedRect:CGRect(x:119,y:134,width:1016,height:986),cornerWidth:197,cornerHeight:197,transform:nil)); c.clip()
c.interpolationQuality = .high
c.draw(img,in:CGRect(x:0,y:0,width:1254,height:1254))
let dest=CGImageDestinationCreateWithURL(output as CFURL,"public.png" as CFString,1,nil)!
CGImageDestinationAddImage(dest,c.makeImage()!,nil); assert(CGImageDestinationFinalize(dest))
