import SwiftUI
import AppKit

struct VistaRecado: View {
    @ObservedObject var modelo: Modelo
    var cerrar: @MainActor () -> Void

    @FocusState private var focoTarea: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            encabezado
            selectorModo
            campoTexto
            filaControles
            pieDeEstado
        }
        .padding(20)
        .frame(width: 560)
        .background(.regularMaterial)
        .onAppear {
            modelo.preparar()
            focoTarea = true
        }
        .onChange(of: modelo.foco) { _, _ in focoTarea = true }
        .onExitCommand(perform: cerrar)
    }

    // MARK: - Encabezado

    private var encabezado: some View {
        HStack(spacing: 11) {
            Image(systemName: "checklist")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 1) {
                Text("Recado").font(.system(size: 14, weight: .semibold))
                Text("Un recordatorio en Apple Recordatorios, sin abrir nada más")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("⌃⌥⇧R").font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary.opacity(0.7)))
                .help("Atajo global: control + opción + shift + R")
        }
    }

    private var selectorModo: some View {
        Picker("", selection: Binding(get: { modelo.modo },
                                      set: { modelo.cambiarModo($0) })) {
            ForEach(Modelo.Modo.allCases) { opcion in
                Text(opcion.rawValue).tag(opcion)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 220)
        .help("Recordatorio o Evento de calendario")
    }

    // MARK: - Campos

    private var campoTexto: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil").foregroundStyle(.secondary).font(.system(size: 13))
            TextField(modelo.modo == .recordatorio
                      ? "¿Qué hay que hacer?  (puedes terminar con @lista)"
                      : "¿Qué evento?  (ej. Comida con Ana mañana 1-3pm)",
                      text: $modelo.texto)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focoTarea)
                .onSubmit { modelo.guardar() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        )
    }

    private var filaControles: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(.secondary).font(.system(size: 12))
                TextField("Cuándo (opcional)",
                          text: $modelo.cuando)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { modelo.guardar() }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.40))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            )

            Menu {
                if modelo.modo == .recordatorio {
                    ForEach(modelo.listas, id: \.self) { nombre in
                        Button {
                            modelo.lista = nombre
                        } label: {
                            if nombre == modelo.lista {
                                Label(nombre, systemImage: "checkmark")
                            } else {
                                Text(nombre)
                            }
                        }
                    }
                } else {
                    ForEach(modelo.calendarios, id: \.self) { nombre in
                        Button {
                            modelo.calendario = nombre
                        } label: {
                            if nombre == modelo.calendario {
                                Label(nombre, systemImage: "checkmark")
                            } else {
                                Text(nombre)
                            }
                        }
                    }
                }
            } label: {
                Label(modelo.modo == .recordatorio ? modelo.lista : modelo.calendario,
                      systemImage: modelo.modo == .recordatorio ? "list.bullet" : "calendar")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 150)
            .help(modelo.modo == .recordatorio
                  ? "Lista de Recordatorios donde se guarda"
                  : "Calendario donde se guarda el evento")

            Button {
                modelo.guardar()
            } label: {
                Text("Guardar").frame(minWidth: 58)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(modelo.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Estado

    private var faltaPermiso: Bool {
        modelo.modo == .recordatorio ? !Recordatorios.autorizado : !Calendario.autorizado
    }

    @ViewBuilder
    private var pieDeEstado: some View {
        switch modelo.fase {
        case .inicial:
            HStack(spacing: 8) {
                Text("⏎ guarda · esc cierra")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if faltaPermiso {
                    Button(modelo.modo == .recordatorio
                           ? "Permitir acceso a Recordatorios"
                           : "Permitir acceso a Calendarios") {
                        if modelo.modo == .recordatorio { modelo.pedirPermiso() }
                        else { modelo.pedirPermisoCalendarios() }
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                } else {
                    Text("· \(modelo.permiso)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        case .listo(let mensaje):
            Label(mensaje, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .fallo(let mensaje):
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(mensaje).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
