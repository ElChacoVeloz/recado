import AppKit

// Dibuja el ícono 1024×1024 sin herramientas externas: degradado + lista.
let lado: CGFloat = 1024
let imagen = NSImage(size: NSSize(width: lado, height: lado))
imagen.lockFocus()

let marco = NSRect(x: 0, y: 0, width: lado, height: lado)
let radio: CGFloat = lado * 0.22
let silueta = NSBezierPath(roundedRect: marco, xRadius: radio, yRadius: radio)

let degradado = NSGradient(colors: [
    NSColor(calibratedRed: 0.32, green: 0.40, blue: 0.96, alpha: 1),
    NSColor(calibratedRed: 0.13, green: 0.22, blue: 0.72, alpha: 1),
])!
degradado.draw(in: silueta, angle: -90)

// Tres renglones de "lista"
NSColor.white.withAlphaComponent(0.92).setFill()
let ancho: CGFloat = lado * 0.40
let alto: CGFloat = lado * 0.055
for i in 0..<3 {
    let y = lado * 0.62 - CGFloat(i) * lado * 0.17
    let rect = NSRect(x: lado * 0.40, y: y, width: ancho - CGFloat(i) * lado * 0.06, height: alto)
    NSBezierPath(roundedRect: rect, xRadius: alto / 2, yRadius: alto / 2).fill()
}

// Palomitas a la izquierda
NSColor.white.setStroke()
for i in 0..<3 {
    let y = lado * 0.62 + alto / 2 - CGFloat(i) * lado * 0.17
    let p = NSBezierPath()
    p.lineWidth = lado * 0.038
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    let x0 = lado * 0.14, y0 = y
    p.move(to: NSPoint(x: x0, y: y0))
    p.line(to: NSPoint(x: x0 + lado * 0.045, y: y0 - lado * 0.045))
    p.line(to: NSPoint(x: x0 + lado * 0.13, y: y0 + lado * 0.075))
    p.stroke()
}

imagen.unlockFocus()

guard CommandLine.arguments.count > 1 else { exit(1) }
guard let tiff = imagen.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
