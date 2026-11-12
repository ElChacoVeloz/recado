import AppKit
import SwiftUI
import Carbon.HIToolbox

/// NSPanel que sí se queda con el teclado aunque la app sea accesoria
/// (sin ícono en el Dock). Sin esto el campo de texto no escribe.
final class PanelFlotante: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var itemEstado: NSStatusItem?
    private var panel: PanelFlotante?
    private var atajo: AtajoGlobal?
    private var estadoAtajo: OSStatus = -1
    private var fuentesSenal: [DispatchSourceSignal] = []
    private let modelo = Modelo()
    private var bandeja: Timer?

    func applicationDidFinishLaunching(_ notificacion: Notification) {
        construirMenuPrincipal()
        construirItemDeBarra()
        construirPanel()
        registrarAtajo()
        observarSenales()
        modelo.alCerrar = { [weak self] in self?.ocultarPanel() }
        prepararBandeja()
        Diario.escribir("arrancó; atajo ⌃⌥⇧R estado=\(estadoAtajo), recordatorios=\(Recordatorios.estadoTexto)")
        primeraVez()
    }

    // MARK: - Menú

    private func construirMenuPrincipal() {
        let principal = NSMenu()
        let itemApp = NSMenuItem()
        principal.addItem(itemApp)

        let menuApp = NSMenu()
        menuApp.addItem(withTitle: "Acerca de Recado",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        menuApp.addItem(.separator())
        menuApp.addItem(withTitle: "Salir de Recado",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        itemApp.submenu = menuApp
        NSApp.mainMenu = principal
    }

    private func construirItemDeBarra() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let boton = item.button {
            let imagen = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Recado")
            imagen?.isTemplate = true
            boton.image = imagen
            boton.toolTip = "Recado — recordatorio rápido (⌃⌥⇧R)"
            boton.target = self
            boton.action = #selector(clicEnBarra)
            boton.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        itemEstado = item
    }

    @objc private func clicEnBarra(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            mostrarMenuDeBarra()
        } else {
            alternarPanel()
        }
    }

    private func mostrarMenuDeBarra() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Nuevo recordatorio…", action: #selector(mostrarPanelDesdeMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Abrir Recordatorios", action: #selector(abrirRecordatorios), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de Recado", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for elemento in menu.items { elemento.target = self }

        itemEstado?.menu = menu
        itemEstado?.button?.performClick(nil)
        itemEstado?.menu = nil
    }

    @objc private func mostrarPanelDesdeMenu() { mostrarPanel() }

    @objc private func abrirRecordatorios() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Panel

    private func construirPanel() {
        let vista = VistaRecado(modelo: modelo, cerrar: { [weak self] in self?.ocultarPanel() })
        let anfitrion = NSHostingView(rootView: vista)

        let panel = PanelFlotante(contentRect: NSRect(x: 0, y: 0, width: 580, height: 260),
                                  styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                                  backing: .buffered,
                                  defer: false)
        panel.contentView = anfitrion
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        // Nunca .canJoinAllSpaces + .moveToActiveSpace juntos: AppKit lanza una
        // excepción silenciosa y el panel jamás aparece.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        self.panel = panel
    }

    private func alternarPanel() {
        if panel?.isVisible == true { ocultarPanel() } else { mostrarPanel() }
    }

    @objc private func mostrarPanel() {
        guard let panel else { return }
        modelo.preparar()
        centrar(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        Diario.escribir("panel mostrado")
    }

    private func ocultarPanel() {
        panel?.orderOut(nil)
    }

    private func centrar(_ panel: NSPanel) {
        guard let pantalla = NSScreen.main else { return }
        let visible = pantalla.visibleFrame
        let tam = panel.frame.size
        let origen = NSPoint(x: visible.midX - tam.width / 2,
                             y: visible.maxY - tam.height - visible.height * 0.22)
        panel.setFrameOrigin(origen)
    }

    func windowDidResignKey(_ notificacion: Notification) {
        // Con un diálogo de permiso encima el panel pierde el foco y se cerraba
        // justo cuando había que leerlo: en ese caso se queda abierto.
        if panel?.isVisible == true, !NSApp.isActive, !modelo.esperandoPermiso { ocultarPanel() }
    }

    private func primeraVez() {
        let marca = ("~/Library/Application Support/Recado/ya-aviso" as NSString).expandingTildeInPath
        guard !FileManager.default.fileExists(atPath: marca) else { return }
        try? FileManager.default.createDirectory(atPath: (marca as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marca, contents: Data())
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.mostrarPanel()
        }
    }

    // MARK: - Atajo

    /// La bandeja se revisa cada 2 s: es la vía para empujar recordatorios y
    /// eventos desde otra máquina (el CLI por SSH no tiene permiso de TCC).
    private func prepararBandeja() {
        let ruta = Modelo.rutaBandeja
        try? FileManager.default.createDirectory(atPath: (ruta as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        let temporizador = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.modelo.procesarBandeja() }
        }
        RunLoop.main.add(temporizador, forMode: .common)
        bandeja = temporizador
    }

    private func registrarAtajo() {
        let atajo = AtajoGlobal { [weak self] in
            MainActor.assumeIsolated { self?.mostrarPanel() }
        }
        estadoAtajo = atajo.registrar()
        self.atajo = atajo
        if estadoAtajo != noErr {
            NSSound.beep()
            Diario.escribir("¡ojo! el atajo no se registró (OSStatus \(estadoAtajo))")
        }
    }

    // MARK: - Señales (para probar sin tocar el teclado)

    private func observarSenales() {
        let pares: [(Int32, Selector)] = [
            (SIGUSR1, #selector(mostrarPanel)),
            (SIGUSR2, #selector(guardarPorSenal)),
            (SIGWINCH, #selector(abrirEnModoEvento)),
            (SIGHUP, #selector(volcarPorSenal)),
        ]
        for (senal, accion) in pares {
            signal(senal, SIG_IGN)
            let fuente = DispatchSource.makeSignalSource(signal: senal, queue: .main)
            fuente.setEventHandler { [weak self] in
                MainActor.assumeIsolated { _ = self?.perform(accion) }
            }
            fuente.resume()
            fuentesSenal.append(fuente)
        }
    }

    @objc private func guardarPorSenal() { modelo.guardar() }

    /// SIGWINCH: abre el panel en modo Evento (así se dispara el permiso de
    /// Calendarios en la sesión gráfica sin teclado).
    @objc private func abrirEnModoEvento() {
        modelo.cambiarModo(.evento)
        mostrarPanel()
    }

    @objc private func volcarPorSenal() {
        guard let panel, let vista = panel.contentView else { return }
        let ruta = ("~/Library/Logs/Recado-vista.png" as NSString).expandingTildeInPath
        if let rep = vista.bitmapImageRepForCachingDisplay(in: vista.bounds) {
            vista.cacheDisplay(in: vista.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: ruta))
            }
        }
        Diario.escribir("volcado: visible=\(panel.isVisible) frame=\(NSStringFromRect(panel.frame))")
    }

    func applicationWillTerminate(_ notificacion: Notification) {
        Diario.escribir("salió")
    }
}
