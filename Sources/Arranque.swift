import AppKit
import Foundation

@main
struct Arranque {
    // NSApplication no retiene a su delegado; si vive como variable local, ARC
    // lo suelta y la app se queda muda.
    nonisolated(unsafe) static var delegado: AppDelegate?

    static func main() {
        let args = CommandLine.arguments
        // Cualquier argumento = modo consola. El LaunchAgent arranca sin
        // argumentos, así que la ventana nunca se confunde con el CLI. Antes se
        // listaban las banderas una por una y una nueva (--calendarios) abría
        // la app en vez de imprimir: mejor "hay argumentos → consola".
        if args.count > 1 { CLI.correr(args) }

        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegado = AppDelegate()
            Arranque.delegado = delegado
            app.delegate = delegado
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
