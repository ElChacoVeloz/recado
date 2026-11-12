import AppKit
import SwiftUI

@MainActor
final class Modelo: ObservableObject {
    enum Modo: String, CaseIterable, Identifiable {
        case recordatorio = "Recordatorio"
        case evento = "Evento"
        var id: String { rawValue }
    }

    enum Fase {
        case inicial
        case listo(String)
        case fallo(String)
    }

    @Published var texto: String = ""
    @Published var cuando: String = ""
    @Published var listas: [String] = []
    @Published var lista: String = ""
    @Published var fase: Fase = .inicial
    @Published var permiso: String = Recordatorios.estadoTexto
    @Published var modo: Modo = .recordatorio
    @Published var calendarios: [String] = []
    @Published var calendario: String = ""
    /// Verdadero mientras hay un diálogo de permiso del sistema encima.
    @Published var esperandoPermiso = false
    /// Sube cada vez que hay que devolverle el cursor al campo de la tarea.
    @Published var foco = 0

    var alCerrar: (@MainActor () -> Void)?

    func preparar() {
        fase = .inicial
        texto = ""
        cuando = ""
        refrescarListas()
        refrescarCalendarios()
        foco &+= 1
    }

    func refrescarCalendarios() {
        calendarios = Calendario.nombres
        let porDefecto = Calendario.porDefecto
        calendario = calendarios.contains(porDefecto) ? porDefecto : (calendarios.first ?? porDefecto)
        permiso = "Recordatorios: \(Recordatorios.estadoTexto) · Calendarios: \(Calendario.estadoTexto)"
    }

    /// Al cambiar a modo Evento se pide el permiso de Calendarios si falta.
    func cambiarModo(_ nuevo: Modo) {
        modo = nuevo
        if nuevo == .evento {
            if Calendario.estadoTexto == "sin decidir" { pedirPermisoCalendarios() }
            else { refrescarCalendarios() }
        }
        foco &+= 1
    }

    func pedirPermisoCalendarios() {
        esperandoPermiso = true
        Calendario.pedirPermiso { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.esperandoPermiso = false
                self.calendarios = Calendario.nombres
                self.calendario = Calendario.porDefecto
                self.permiso = "Recordatorios: \(Recordatorios.estadoTexto) · Calendarios: \(Calendario.estadoTexto)"
                self.foco &+= 1
            }
        }
    }

    /// Botón explícito del pie: macOS sólo pregunta una vez, así que conviene
    /// poder dispararlo a mano sin cerrar la ventana.
    func pedirPermiso() {
        esperandoPermiso = true
        Recordatorios.pedirPermiso { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.esperandoPermiso = false
                self.permiso = Recordatorios.estadoTexto
                self.listas = Recordatorios.listas
                self.lista = Recordatorios.listaPorDefecto
                self.foco &+= 1
            }
        }
    }

    func refrescarListas() {
        listas = Recordatorios.listas
        permiso = Recordatorios.estadoTexto
        // Siempre arranca en la lista por defecto del sistema (la de arriba
        // en Recordatorios), tal como lo pidió el Capitán.
        let porDefecto = Recordatorios.listaPorDefecto
        lista = listas.contains(porDefecto) ? porDefecto : (listas.first ?? porDefecto)
        if !Recordatorios.autorizado, Recordatorios.estadoTexto == "sin decidir" {
            Recordatorios.pedirPermiso { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.listas = Recordatorios.listas
                    guard let self else { return }
                    if !self.listas.contains(self.lista) { self.lista = Recordatorios.listaPorDefecto }
                }
            }
        }
    }

    func guardar() {
        let tareaCruda = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tareaCruda.isEmpty else { return }

        if modo == .evento { guardarEvento(tareaCruda); return }

        var titulo = tareaCruda
        var destino = lista

        // "@Casa" al final manda sobre el selector.
        if let rango = titulo.range(of: #"\s@\S+$"#, options: .regularExpression) {
            let token = String(titulo[rango]).trimmingCharacters(in: .whitespaces).dropFirst()
            if let encontrada = listas.first(where: { $0.caseInsensitiveCompare(String(token)) == .orderedSame })
                ?? listas.first(where: { $0.lowercased().hasPrefix(String(token).lowercased()) }) {
                destino = encontrada
                titulo = String(titulo[..<rango.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }

        let cuandoLimpio = cuando.trimmingCharacters(in: .whitespacesAndNewlines)
        let interpretacion = Fechas.interpretar(cuandoLimpio)

        do {
            try Recordatorios.crear(titulo: titulo, lista: destino, componentes: interpretacion.componentes)
            var confirmacion = "Guardado en \(destino)"
            if interpretacion.componentes != nil { confirmacion += " · \(interpretacion.descripcion)" }
            fase = .listo(confirmacion)
            avisar("Recordatorio guardado en \(destino)")
            let cerrar = alCerrar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                MainActor.assumeIsolated { cerrar?() }
            }
        } catch {
            fase = .fallo(error.localizedDescription)
            NSSound.beep()
        }
    }

    /// En modo Evento el "Cuándo" puede ir vacío si el horario viene dentro del
    /// título ("Comida con Ana 1-3pm"): se detecta, se recorta y se usa.
    private func guardarEvento(_ crudo: String) {
        var titulo = crudo
        var destino = calendario

        if let rango = titulo.range(of: #"\s@\S+$"#, options: .regularExpression) {
            let token = String(titulo[rango]).trimmingCharacters(in: .whitespaces).dropFirst()
            if let encontrado = calendarios.first(where: { $0.caseInsensitiveCompare(String(token)) == .orderedSame })
                ?? calendarios.first(where: { $0.lowercased().hasPrefix(String(token).lowercased()) }) {
                destino = encontrado
                titulo = String(titulo[..<rango.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }

        var cuandoLimpio = cuando.trimmingCharacters(in: .whitespacesAndNewlines)
        if cuandoLimpio.isEmpty {
            if let extraido = Fechas.recortarHorario(de: titulo) {
                cuandoLimpio = extraido.horario
                titulo = extraido.titulo
            }
        }

        let rango = Fechas.interpretarRango(cuandoLimpio)
        do {
            try Calendario.crear(titulo: titulo,
                                 inicio: rango.inicio,
                                 fin: rango.fin,
                                 calendario: destino,
                                 todoElDia: rango.todoElDia)
            fase = .listo("Evento en \(destino) · \(rango.descripcion)")
            avisar("Evento guardado en \(destino): \(rango.descripcion)")
            let cerrar = alCerrar
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                MainActor.assumeIsolated { cerrar?() }
            }
        } catch {
            fase = .fallo(error.localizedDescription)
            NSSound.beep()
        }
    }

    // MARK: - Bandeja (para empujar cosas desde fuera)

    /// El CLI no puede escribir en Calendarios: el permiso TCC lo tiene la app
    /// de la sesión gráfica, no el proceso que llega por SSH. Así que la app
    /// vigila un archivo y ejecuta lo que le dejen ahí, con sus permisos.
    static let rutaBandeja = ("~/Library/Application Support/Recado/bandeja.jsonl" as NSString).expandingTildeInPath

    func procesarBandeja() {
        let ruta = Modelo.rutaBandeja
        guard let datos = try? String(contentsOfFile: ruta, encoding: .utf8),
              !datos.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? FileManager.default.removeItem(atPath: ruta)
        Diario.escribir("bandeja: \(datos.split(separator: "\n").count) línea(s)")
        for linea in datos.split(separator: "\n") {
            guard let crudo = try? JSONSerialization.jsonObject(with: Data(linea.utf8)) as? [String: String],
                  let texto = crudo["texto"], !texto.isEmpty else { continue }
            let tipo = (crudo["tipo"] ?? "recordatorio").lowercased()
            let cuando = crudo["cuando"] ?? ""
            do {
                if tipo.hasPrefix("e") {
                    let rango = Fechas.interpretarRango(cuando)
                    try Calendario.crear(titulo: texto,
                                         inicio: rango.inicio,
                                         fin: rango.fin,
                                         calendario: crudo["destino"] ?? Calendario.porDefecto,
                                         todoElDia: rango.todoElDia)
                    Diario.escribir("bandeja: evento «\(texto)» \(rango.descripcion)")
                } else {
                    let i = Fechas.interpretar(cuando)
                    try Recordatorios.crear(titulo: texto,
                                            lista: crudo["destino"] ?? Recordatorios.listaPorDefecto,
                                            componentes: i.componentes)
                    Diario.escribir("bandeja: recordatorio «\(texto)» \(i.descripcion)")
                }
            } catch {
                Diario.escribir("bandeja: ERROR con «\(texto)»: \(error.localizedDescription)")
            }
        }
    }

    private func avisar(_ mensaje: String) {
        NSApp.requestUserAttention(.informationalRequest)
        Diario.escribir(mensaje)
    }
}

enum Diario {
    static func escribir(_ texto: String) {
        NSLog("%@", texto)
        let ruta = ("~/Library/Logs/Recado.log" as NSString).expandingTildeInPath
        let sello = ISO8601DateFormatter().string(from: Date())
        guard let datos = "[\(sello)] \(texto)\n".data(using: .utf8) else { return }
        if let fh = FileHandle(forWritingAtPath: ruta) {
            fh.seekToEndOfFile()
            fh.write(datos)
            try? fh.close()
        } else {
            try? datos.write(to: URL(fileURLWithPath: ruta))
        }
    }
}
