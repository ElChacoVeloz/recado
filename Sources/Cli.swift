import Foundation
import EventKit

/// Modo sin interfaz, misma ruta de guardado que la ventana. Sirve para
/// probar desde la Terminal y para encadenarlo en scripts.
enum CLI {
    static func correr(_ args: [String]) -> Never {
        if args.contains("--ayuda") {
            print("""
            Recado --cli --texto "Llamar al dentista" [--cuando "hoy 4pm"] [--lista Recordatorios]

            Recordatorio (por defecto)
              --texto "..."    título
              --cuando "..."   hoy 4pm · mañana 9:00 · +2h · viernes 10am
              --lista X        lista de Recordatorios
              --notas "..."    notas

            Evento
              --tipo evento
              --cuando "..."   mañana 9:00 · hoy 4-6pm · (vacío = todo el día)
              --calendario X   calendario destino

            Otros
              --listas / --calendarios   qué hay y con qué permiso
              --simular                  sólo interpreta la fecha, no guarda
            """)
            exit(0)
        }

        if args.contains("--pedir-permiso") {
            let grupo = DispatchGroup()
            grupo.enter()
            Recordatorios.pedirPermiso { ok in print("recordatorios concedido: \(ok)"); grupo.leave() }
            grupo.enter()
            Calendario.pedirPermiso { ok in print("calendarios concedido: \(ok)"); grupo.leave() }
            _ = grupo.wait(timeout: .now() + 25)
            print("estado recordatorios: \(Recordatorios.estadoTexto) · calendarios: \(Calendario.estadoTexto)")
            exit(0)
        }

        if args.contains("--listas") {
            print("permiso recordatorios: \(Recordatorios.estadoTexto) · por defecto: \(Recordatorios.listaPorDefecto)")
            for nombre in Recordatorios.listas { print(nombre) }
            exit(0)
        }

        if args.contains("--calendarios") {
            print("permiso calendarios: \(Calendario.estadoTexto) · por defecto: \(Calendario.porDefecto)")
            for nombre in Calendario.nombres { print(nombre) }
            exit(0)
        }

        var texto = "", cuando = "", notas = ""
        var lista = Recordatorios.listaPorDefecto
        var calendario = Calendario.porDefecto
        var esEvento = false
        var i = 1
        while i < args.count {
            let a = args[i]
            func siguiente() -> String { i + 1 < args.count ? args[i + 1] : "" }
            switch a {
            case "--texto": texto = siguiente(); i += 2
            case "--cuando": cuando = siguiente(); i += 2
            case "--lista": lista = siguiente(); i += 2
            case "--calendario": calendario = siguiente(); i += 2
            case "--notas": notas = siguiente(); i += 2
            case "--tipo": esEvento = siguiente().lowercased().hasPrefix("e"); i += 2
            case "--evento": esEvento = true; i += 1
            default: i += 1
            }
        }

        guard !texto.isEmpty else {
            FileHandle.standardError.write(Data("falta --texto\n".utf8))
            exit(2)
        }

        let simular = args.contains("--simular")

        if esEvento {
            var tituloEvento = texto
            var cuandoEvento = cuando
            if cuandoEvento.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let extraido = Fechas.recortarHorario(de: tituloEvento) {
                cuandoEvento = extraido.horario
                tituloEvento = extraido.titulo
            }
            let rango = Fechas.interpretarRango(cuandoEvento)
            if simular {
                print("evento=\(tituloEvento) calendario=\(calendario) cuando=\(rango.descripcion)")
                exit(0)
            }
            do {
                let id = try Calendario.crear(titulo: tituloEvento,
                                              inicio: rango.inicio,
                                              fin: rango.fin,
                                              calendario: calendario,
                                              todoElDia: rango.todoElDia)
                print("OK \(id) | calendario=\(calendario) | \(rango.descripcion)")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("ERROR \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }

        let interpretacion = Fechas.interpretar(cuando)
        if simular {
            print("texto=\(texto) lista=\(lista) cuando=\(interpretacion.descripcion)")
            exit(0)
        }

        do {
            let id = try Recordatorios.crear(titulo: texto,
                                             lista: lista,
                                             componentes: interpretacion.componentes,
                                             notas: notas.isEmpty ? nil : notas)
            print("OK \(id) | lista=\(lista) | \(interpretacion.descripcion)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("ERROR \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
