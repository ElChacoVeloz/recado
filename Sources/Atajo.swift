import Carbon.HIToolbox
import AppKit

/// Atajo global con `RegisterEventHotKey` de Carbon: no pide permisos de
/// Accesibilidad y funciona aunque la app esté en segundo plano.
func manejadorAtajo(_ _: EventHandlerCallRef?,
                    _ evento: EventRef?,
                    _ datos: UnsafeMutableRawPointer?) -> OSStatus {
    guard let evento, let datos else { return OSStatus(eventNotHandledErr) }
    let atajo = Unmanaged<AtajoGlobal>.fromOpaque(datos).takeUnretainedValue()
    var pulsada = EventHotKeyID()
    let err = GetEventParameter(evento,
                                EventParamName(kEventParamDirectObject),
                                EventParamType(typeEventHotKeyID),
                                nil,
                                MemoryLayout<EventHotKeyID>.size,
                                nil,
                                &pulsada)
    guard err == noErr, pulsada.signature == atajo.firma, pulsada.id == atajo.identificador else {
        return OSStatus(eventNotHandledErr)
    }
    DispatchQueue.main.async { atajo.disparar() }
    return noErr
}

final class AtajoGlobal {
    let firma: OSType = 0x5243444F   // 'RCDO'
    let identificador: UInt32 = 1

    private var referencia: EventHotKeyRef?
    private var manejador: EventHandlerRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    deinit { desregistrar() }

    func registrar(codigo: UInt32 = UInt32(kVK_ANSI_R),
                   modificadores: UInt32 = UInt32(controlKey | optionKey | shiftKey)) -> OSStatus {
        var tipo = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let puntero = Unmanaged.passUnretained(self).toOpaque()
        let err = InstallEventHandler(GetApplicationEventTarget(),
                                      manejadorAtajo,
                                      1,
                                      &tipo,
                                      puntero,
                                      &manejador)
        guard err == noErr else { return err }

        let ident = EventHotKeyID(signature: firma, id: identificador)
        return RegisterEventHotKey(codigo, modificadores, ident,
                                   GetApplicationEventTarget(), 0, &referencia)
    }

    func desregistrar() {
        if let referencia { UnregisterEventHotKey(referencia) }
        if let manejador { RemoveEventHandler(manejador) }
        referencia = nil
        manejador = nil
    }

    func disparar() { callback() }
}
