import EventKit
import Foundation

enum FalloRecordatorio: LocalizedError {
    case sinPermiso
    case listaDesconocida(String)
    case guardado(String)

    var errorDescription: String? {
        switch self {
        case .sinPermiso:
            return "Falta el permiso para Recordatorios. La primera vez macOS lo pide: dale Permitir."
        case .listaDesconocida(let l):
            return "No existe la lista «\(l)»."
        case .guardado(let m):
            return "No se pudo guardar: \(m)"
        }
    }
}

/// Acceso a Recordatorios por EventKit: sin AppleScript, sin diálogo de
/// Automatización. Es la misma API que usa la app, así que ve todas las listas
/// de la cuenta (AppleScript sólo mostraba una parte).
enum Recordatorios {
    static let store = EKEventStore()

    static var listas: [String] {
        store.calendars(for: .reminder).map(\.title).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// La lista por defecto del sistema. Ojo: EventKit devuelve el título
    /// localizado ("Recordatorios") mientras AppleScript lo llama "Reminders":
    /// es la misma lista, así que el default se pregunta, nunca se asume.
    static var listaPorDefecto: String {
        store.defaultCalendarForNewReminders()?.title ?? listas.first ?? "Reminders"
    }

    static var autorizado: Bool {
        let estado = EKEventStore.authorizationStatus(for: .reminder)
        if #available(macOS 14.0, *) { return estado == .fullAccess }
        return estado == .authorized
    }

    static var estadoTexto: String {
        let estado = EKEventStore.authorizationStatus(for: .reminder)
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
            store.requestFullAccessToReminders { ok, _ in
                DispatchQueue.main.async { fin(ok) }
            }
        } else {
            store.requestAccess(to: .reminder) { ok, _ in
                DispatchQueue.main.async { fin(ok) }
            }
        }
    }

    @discardableResult
    static func crear(titulo: String,
                      lista: String,
                      componentes: DateComponents?,
                      notas: String? = nil) throws -> String {
        guard autorizado else { throw FalloRecordatorio.sinPermiso }
        let candidatas = store.calendars(for: .reminder)
        guard let destino = candidatas.first(where: { $0.title.caseInsensitiveCompare(lista) == .orderedSame })
                ?? candidatas.first(where: { $0.title.lowercased().hasPrefix(lista.lowercased()) })
        else { throw FalloRecordatorio.listaDesconocida(lista) }

        let recordatorio = EKReminder(eventStore: store)
        recordatorio.title = titulo
        recordatorio.calendar = destino
        if let componentes { recordatorio.dueDateComponents = componentes }
        if let notas, !notas.isEmpty { recordatorio.notes = notas }
        do {
            try store.save(recordatorio, commit: true)
        } catch {
            throw FalloRecordatorio.guardado(error.localizedDescription)
        }
        return recordatorio.calendarItemIdentifier
    }
}
