import EventKit
import Foundation

enum FalloCalendario: LocalizedError {
    case sinPermiso
    case calendarioDesconocido(String)
    case guardado(String)

    var errorDescription: String? {
        switch self {
        case .sinPermiso:
            return "Falta el permiso para Calendarios. Dale «Permitir acceso» abajo."
        case .calendarioDesconocido(let c):
            return "No existe el calendario «\(c)»."
        case .guardado(let m):
            return "No se pudo guardar el evento: \(m)"
        }
    }
}

/// Calendarios por EventKit. Igual que con Recordatorios: nada de AppleScript,
/// así se ven todas las cuentas y no hay diálogo de Automatización.
enum Calendario {
    static let store = Recordatorios.store

    static var nombres: [String] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map(\.title)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static var porDefecto: String {
        store.defaultCalendarForNewEvents?.title ?? nombres.first ?? "Calendario"
    }

    static var autorizado: Bool {
        let estado = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { return estado == .fullAccess }
        return estado == .authorized
    }

    static var estadoTexto: String {
        let estado = EKEventStore.authorizationStatus(for: .event)
        switch estado {
        case .notDetermined: return "sin decidir"
        case .restricted: return "restringido"
        case .denied: return "denegado"
        case .authorized: return "autorizado"
        default:
            if #available(macOS 14.0, *), estado == .fullAccess { return "acceso total" }
            if #available(macOS 14.0, *), estado == .writeOnly { return "sólo escritura" }
            return "desconocido (\(estado.rawValue))"
        }
    }

    static func pedirPermiso(_ fin: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { ok, _ in DispatchQueue.main.async { fin(ok) } }
        } else {
            store.requestAccess(to: .event) { ok, _ in DispatchQueue.main.async { fin(ok) } }
        }
    }

    @discardableResult
    static func crear(titulo: String,
                      inicio: DateComponents,
                      fin: DateComponents?,
                      calendario: String,
                      todoElDia: Bool) throws -> String {
        guard autorizado else { throw FalloCalendario.sinPermiso }
        let candidatos = store.calendars(for: .event).filter { $0.allowsContentModifications }
        guard let destino = candidatos.first(where: { $0.title.caseInsensitiveCompare(calendario) == .orderedSame })
                ?? candidatos.first(where: { $0.title.lowercased().hasPrefix(calendario.lowercased()) })
        else { throw FalloCalendario.calendarioDesconocido(calendario) }

        let cal = Fechas.calendario
        guard let comienzo = cal.date(from: inicio) else { throw FalloCalendario.guardado("fecha de inicio inválida") }

        var termino: Date
        if let fin, let f = cal.date(from: fin) {
            termino = f
        } else if todoElDia {
            termino = cal.date(byAdding: .day, value: 1, to: comienzo) ?? comienzo.addingTimeInterval(86400)
        } else {
            termino = comienzo.addingTimeInterval(3600)
        }
        if termino <= comienzo { termino = comienzo.addingTimeInterval(todoElDia ? 86400 : 3600) }

        let evento = EKEvent(eventStore: store)
        evento.title = titulo
        evento.calendar = destino
        evento.startDate = comienzo
        evento.endDate = termino
        evento.isAllDay = todoElDia
        if !todoElDia {
            evento.addAlarm(EKAlarm(relativeOffset: -600))   // aviso 10 min antes
        }
        do {
            try store.save(evento, span: .thisEvent, commit: true)
        } catch {
            throw FalloCalendario.guardado(error.localizedDescription)
        }
        return evento.eventIdentifier ?? ""
    }
}
