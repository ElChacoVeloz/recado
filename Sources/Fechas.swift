import Foundation

/// Interpretación de fechas escritas a mano alzada: "hoy 4pm", "mañana 9:00",
/// "+2h", "viernes 10am", "2026-11-20 8:00", "20 de noviembre".
/// Todo se calcula en la zona del usuario y se devuelve como
/// componentes, que es lo que espera EventKit para el vencimiento.
struct Interpretacion {
    var componentes: DateComponents?
    var descripcion: String
}

/// Evento: inicio, fin opcional y si es de todo el día.
struct Rango {
    var inicio: DateComponents
    var fin: DateComponents?
    var todoElDia: Bool
    var descripcion: String
}

enum Fechas {
    static var zona: TimeZone {
        if let id = ProcessInfo.processInfo.environment["RECADO_ZONA"],
           let tz = TimeZone(identifier: id) { return tz }
        return .current
    }

    static var calendario: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zona
        c.locale = Locale(identifier: "es_MX")
        return c
    }

    private static let formas = DateFormatter()

    // MARK: - API

    static func interpretar(_ entrada: String, ahora: Date = Date()) -> Interpretacion {
        let crudo = entrada.trimmingCharacters(in: .whitespacesAndNewlines)
        if crudo.isEmpty { return Interpretacion(componentes: nil, descripcion: "sin vencimiento") }

        let t = normalizar(crudo)

        if let rel = relativo(t, ahora: ahora) { return rel }
        if let dia = diaExplicito(t, ahora: ahora) {
            return componer(dia: dia.fecha, hora: hora(t), ahora: ahora)
        }
        return componer(dia: calendario.startOfDay(for: ahora), hora: hora(t), ahora: ahora)
    }

    /// Texto legible de una fecha, para confirmar antes de guardar.
    static func describir(_ fecha: Date, conHora: Bool, ahora: Date = Date()) -> String {
        let cal = calendario
        let horaMin = String(format: "%02d:%02d", cal.component(.hour, from: fecha), cal.component(.minute, from: fecha))
        if conHora == false { return esHoy(fecha, ahora) ? "hoy (todo el día)" : relativaODia(fecha, ahora) + " (todo el día)" }
        if esHoy(fecha, ahora) { return "hoy \(horaMin)" }
        if let ayer = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: ahora)),
           cal.isDate(fecha, inSameDayAs: ayer) { return "mañana \(horaMin)" }
        return relativaODia(fecha, ahora) + " \(horaMin)"
    }

    // MARK: - Eventos (con hora de fin)

    /// Para calendarios: acepta "mañana 9:00", "hoy 4-6pm", "de 4 a 6 de la
    /// tarde", "viernes 10am a 11:30", o nada (todo el día).
    static func interpretarRango(_ entrada: String, ahora: Date = Date()) -> Rango {
        let crudo = entrada.trimmingCharacters(in: .whitespacesAndNewlines)
        if crudo.isEmpty {
            let dia = calendario.startOfDay(for: ahora)
            return Rango(inicio: componentes(dia, hora: 0, minuto: 0),
                         fin: componentes(calendario.date(byAdding: .day, value: 1, to: dia) ?? dia, hora: 0, minuto: 0),
                         todoElDia: true,
                         descripcion: "hoy (todo el día)")
        }

        let t = normalizar(crudo)
        let dia = diaExplicito(t, ahora: ahora)?.fecha ?? calendario.startOfDay(for: ahora)

        // rango explícito: "4-6pm", "10am a 11:30", "de 4 a 6 de la tarde"
        if let g = grupos(#"(\d{1,2}(?::\d{2})?)\s*(am|pm)?\s*(?:a|al|hasta|-|–|—)\s*(\d{1,2}(?::\d{2})?)\s*(am|pm)?"#, t),
           let h1 = horaSuelta(g[1]), let h2 = horaSuelta(g[3]) {
            // El meridiano del segundo manda; si no trae, hereda el del primero.
            let primero = !g[2].isEmpty ? aplicar(g[2], h1.hora) : aplicar(g[4], h1.hora)
            let segundo = !g[4].isEmpty ? aplicar(g[4], h2.hora) : (!g[2].isEmpty ? aplicar(g[2], h2.hora) : aplicar("", h2.hora))

            var ini = componentes(dia, hora: primero, minuto: h1.minuto)
            var fin = componentes(dia, hora: segundo, minuto: h2.minuto)
            if let i = calendario.date(from: ini), let f = calendario.date(from: fin) {
                if f <= i {
                    // "11pm a 1am" termina al día siguiente
                    let siguiente = calendario.date(byAdding: .day, value: 1, to: f) ?? f.addingTimeInterval(86400)
                    fin = calendario.dateComponents([.year, .month, .day, .hour, .minute], from: siguiente)
                }
            }
            let descripcion = textoRango(ini, fin, todoElDia: false, ahora: ahora)
            ini.second = 0
            return Rango(inicio: ini, fin: fin, todoElDia: false, descripcion: descripcion)
        }

        // hora única: el evento dura una hora
        if let h = hora(t) {
            let ini = componentes(dia, hora: h.hora, minuto: h.minuto)
            let base = calendario.date(from: ini) ?? ahora
            let f = calendario.date(byAdding: .hour, value: 1, to: base) ?? base.addingTimeInterval(3600)
            let fin = calendario.dateComponents([.year, .month, .day, .hour, .minute], from: f)
            return Rango(inicio: ini, fin: fin, todoElDia: false,
                         descripcion: textoRango(ini, fin, todoElDia: false, ahora: ahora))
        }

        // sin hora: todo el día
        let inicio = componentes(dia, hora: 0, minuto: 0)
        let siguiente = calendario.date(byAdding: .day, value: 1, to: dia) ?? dia
        return Rango(inicio: inicio,
                     fin: componentes(siguiente, hora: 0, minuto: 0),
                     todoElDia: true,
                     descripcion: describir(dia, conHora: false, ahora: ahora))
    }

    /// Busca fecha/hora al final del título y la separa:
    /// "Comida con Ana mañana 1-3pm" → ("Comida con Ana", "mañana 1-3pm").
    /// "Cumple de Ana 25 de diciembre" → ("Cumple de Ana", "25 de diciembre").
    static func recortarHorario(de titulo: String) -> (titulo: String, horario: String)? {
        let dia = #"(?:(?:hoy|mañana|manana|pasado mañana|pasado manana|(?:(?:el|este|próximo|proximo)\s+)?(?:lunes|martes|miércoles|miercoles|jueves|viernes|sábado|sabado|domingo)))"#
        let mes = #"(?:enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)"#
        let fecha = #"(?:\d{4}-\d{1,2}-\d{1,2}|\d{1,2}/\d{1,2}(?:/\d{2,4})?|\d{1,2}\s+(?:de\s+)?"# + mes + #")"#
        let casos: [(patron: String, exige: Bool)] = [
            // rango con hora: "1-3pm", "10am a 11:30", "de 4 a 6"
            (#"\s+"# + dia + #"?\s*(?:de\s+)?(\d{1,2}(?::\d{2})?)\s*(?:am|pm)?\s*(?:a|al|-|hasta)\s*(\d{1,2}(?::\d{2})?)\s*(?:am|pm)?$"#, true),
            // hora única explícita: "mañana 9:00", "viernes 10am", "a las 4"
            (#"\s+"# + dia + #"?\s*(?:a\s+las\s+)?(\d{1,2}(?::\d{2})?)\s*(?:am|pm)$"#, true),
            (#"\s+a\s+las\s+(\d{1,2}(?::\d{2})?)\s*(?:am|pm)?$"#, true),
            // fecha sola: "25 de diciembre", "20/12", "2026-11-20", "mañana"
            (#"\s+"# + fecha + #"$"#, false),
            (#"\s+"# + dia + #"$"#, false),
        ]
        for caso in casos {
            guard let re = try? NSRegularExpression(pattern: caso.patron, options: [.caseInsensitive]) else { continue }
            let rango = NSRange(titulo.startIndex..., in: titulo)
            guard let m = re.firstMatch(in: titulo, range: rango), m.range.location > 0 else { continue }
            let parte = (titulo as NSString).substring(with: m.range).trimmingCharacters(in: .whitespaces)
            let corte = titulo.index(titulo.startIndex, offsetBy: m.range.location)
            let limpio = String(titulo[..<corte]).trimmingCharacters(in: .whitespaces)
            guard !limpio.isEmpty, !parte.isEmpty else { continue }
            return (limpio, parte)
        }
        return nil
    }

    private static func componentes(_ dia: Date, hora: Int, minuto: Int) -> DateComponents {
        var c = calendario.dateComponents([.year, .month, .day], from: dia)
        c.hour = hora
        c.minute = minuto
        c.second = 0
        return c
    }

    private static func horaSuelta(_ s: String) -> (hora: Int, minuto: Int)? {
        let partes = s.split(separator: ":")
        guard let h = Int(partes[0]) else { return nil }
        let m = partes.count > 1 ? (Int(partes[1]) ?? 0) : 0
        guard h <= 23, m <= 59 else { return nil }
        return (h, m)
    }

    /// Sin am/pm, una hora de 1 a 7 se entiende de la tarde ("de 4 a 6").
    private static func aplicar(_ meridiano: String, _ hora: Int) -> Int {
        switch meridiano {
        case "pm": return hora < 12 ? hora + 12 : hora
        case "am": return hora == 12 ? 0 : hora
        default: return (hora >= 1 && hora <= 7) ? hora + 12 : hora
        }
    }

    private static func textoRango(_ ini: DateComponents, _ fin: DateComponents, todoElDia: Bool, ahora: Date) -> String {
        let cal = calendario
        guard let i = cal.date(from: ini), let f = cal.date(from: fin) else { return "evento" }
        let hora = DateFormatter()
        hora.locale = Locale(identifier: "es_MX")
        hora.timeZone = zona
        hora.dateFormat = "HH:mm"
        let diaTexto = esHoy(i, ahora) ? "hoy" : relativaODia(i, ahora)
        if todoElDia { return "\(diaTexto) (todo el día)" }
        return "\(diaTexto) \(hora.string(from: i))–\(hora.string(from: f))"
    }

    // MARK: - Piezas


    private struct Dia { var fecha: Date }

    private static func esHoy(_ fecha: Date, _ ahora: Date) -> Bool {
        calendario.isDate(fecha, inSameDayAs: ahora)
    }

    private static func relativaODia(_ fecha: Date, _ ahora: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.timeZone = zona
        let cal = calendario
        if cal.isDate(fecha, inSameDayAs: ahora) { return "hoy" }
        let dias = cal.dateComponents([.day], from: cal.startOfDay(for: ahora), to: cal.startOfDay(for: fecha)).day ?? 0
        if dias == 1 { return "mañana" }
        if dias == 2 { return "pasado mañana" }
        f.dateFormat = "EEE d MMM"
        return f.string(from: fecha)
    }

    private static func normalizar(_ s: String) -> String {
        let plano = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_MX"))
        var t = plano.lowercased()
        t = t.replacingOccurrences(of: " de la manana", with: " am")
        t = t.replacingOccurrences(of: " por la manana", with: " am")
        t = t.replacingOccurrences(of: " de la tarde", with: " pm")
        t = t.replacingOccurrences(of: " por la tarde", with: " pm")
        t = t.replacingOccurrences(of: " de la noche", with: " pm")
        t = t.replacingOccurrences(of: "a las ", with: "")
        t = t.replacingOccurrences(of: "  ", with: " ")
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func grupos(_ patron: String, _ texto: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: patron) else { return nil }
        let rango = NSRange(texto.startIndex..., in: texto)
        guard let m = re.firstMatch(in: texto, range: rango) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            guard let r = Range(m.range(at: i), in: texto) else { return "" }
            return String(texto[r])
        }
    }

    /// "+2h", "+30m", "+3d", "en 45 minutos", "en 2 horas".
    private static func relativo(_ t: String, ahora: Date) -> Interpretacion? {
        var resto = t
        var esOffset = false
        if resto.hasPrefix("+") { resto.removeFirst(); esOffset = true }
        else if resto.hasPrefix("en ") { resto = String(resto.dropFirst(3)); esOffset = true }
        guard esOffset,
              let g = grupos(#"^(\d+)\s*([a-z]*)$"#, resto.trimmingCharacters(in: .whitespaces)),
              let n = Int(g[1]) else { return nil }

        var c = DateComponents()
        switch g[2] {
        case "", "h", "hr", "hrs", "hora", "horas": c.hour = n
        case "m", "min", "mins", "minuto", "minutos": c.minute = n
        case "d", "dia", "dias": c.day = n
        case "s", "sem", "semana", "semanas": c.weekOfYear = n
        case "seg", "segs", "segundo", "segundos": c.second = n
        case "mes", "meses": c.month = n
        default: return nil
        }
        guard let fecha = calendario.date(byAdding: c, to: ahora) else { return nil }
        return componer(dia: fecha, hora: nil, ahora: ahora, forzarHora: true, fechaDirecta: fecha)
    }

    private static let diasSemana: [String: Int] = [
        "domingo": 1, "lunes": 2, "martes": 3, "miercoles": 4,
        "jueves": 5, "viernes": 6, "sabado": 7,
    ]

    private static let meses: [String: Int] = [
        "enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6,
        "julio": 7, "agosto": 8, "septiembre": 9, "setiembre": 9, "octubre": 10,
        "noviembre": 11, "diciembre": 12,
    ]

    private static func diaExplicito(_ t: String, ahora: Date) -> Dia? {
        let cal = calendario
        let hoy = cal.startOfDay(for: ahora)

        // 2026-11-20
        if let g = grupos(#"(\d{4})-(\d{1,2})-(\d{1,2})"#, t),
           let y = Int(g[1]), let m = Int(g[2]), let d = Int(g[3]),
           let f = cal.date(from: DateComponents(year: y, month: m, day: d)) { return Dia(fecha: f) }

        // 20/11 o 20/11/2026
        if let g = grupos(#"(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?"#, t),
           let d = Int(g[1]), let m = Int(g[2]) {
            var y = cal.component(.year, from: ahora)
            if g[3].count >= 2, let escrito = Int(g[3]) { y = escrito < 100 ? 2000 + escrito : escrito }
            if let f = cal.date(from: DateComponents(year: y, month: m, day: d)) {
                return Dia(fecha: f < hoy ? (cal.date(byAdding: .year, value: 1, to: f) ?? f) : f)
            }
        }

        // 20 de noviembre / 20 noviembre
        for (nombre, numero) in meses {
            if let g = grupos(#"(\d{1,2})\s+(?:de\s+)?"# + nombre, t), let d = Int(g[1]),
               let f = cal.date(from: DateComponents(year: cal.component(.year, from: ahora), month: numero, day: d)) {
                return Dia(fecha: f < hoy ? (cal.date(byAdding: .year, value: 1, to: f) ?? f) : f)
            }
        }

        if t.contains("pasado manana") { return Dia(fecha: cal.date(byAdding: .day, value: 2, to: hoy) ?? hoy) }
        if let g = grupos(#"en\s+(\d+)\s+dias?"#, t), let n = Int(g[1]) {
            return Dia(fecha: cal.date(byAdding: .day, value: n, to: hoy) ?? hoy)
        }
        if t.contains("manana") { return Dia(fecha: cal.date(byAdding: .day, value: 1, to: hoy) ?? hoy) }
        if t.contains("hoy") || t.contains("ahora") { return Dia(fecha: hoy) }

        // viernes, próximo lunes…
        for (nombre, numero) in diasSemana where t.contains(nombre) {
            let estricto = t.contains("proximo") || t.contains("proxima") || t.contains("next")
            let desde = estricto ? ahora : hoy.addingTimeInterval(-1)
            if let f = cal.nextDate(after: desde,
                                    matching: DateComponents(weekday: numero),
                                    matchingPolicy: .nextTime) {
                return Dia(fecha: cal.startOfDay(for: f))
            }
        }
        return nil
    }

    private static func hora(_ t: String) -> (hora: Int, minuto: Int, explicita: Bool)? {
        if let g = grupos(#"(\d{1,2}):(\d{2})\s*(am|pm)?"#, t), let h = Int(g[1]), let m = Int(g[2]) {
            var hora = h
            if g[3] == "pm" && hora < 12 { hora += 12 }
            if g[3] == "am" && hora == 12 { hora = 0 }
            return (hora, m, true)
        }
        if let g = grupos(#"(\d{1,2})\s*(am|pm)"#, t), let h = Int(g[1]) {
            var hora = h
            if g[2] == "pm" && hora < 12 { hora += 12 }
            if g[2] == "am" && hora == 12 { hora = 0 }
            return (hora, 0, true)
        }
        if t.contains("mediodia") { return (12, 0, true) }
        if t.contains("medianoche") { return (0, 0, true) }
        // hora suelta: "hoy 4" se entiende 4 de la tarde
        if let g = grupos(#"(?:^|\s)(\d{1,2})(?:\s|$)"#, t), let h = Int(g[1]), h <= 23 {
            let hora = (h >= 1 && h <= 7) ? h + 12 : h
            return (hora, 0, true)
        }
        return nil
    }

    private static func componer(dia: Date,
                                 hora h: (hora: Int, minuto: Int, explicita: Bool)?,
                                 ahora: Date,
                                 forzarHora: Bool = false,
                                 fechaDirecta: Date? = nil) -> Interpretacion {
        let cal = calendario
        var base = dia
        var conHora = forzarHora
        if let h {
            var comps = cal.dateComponents([.year, .month, .day], from: dia)
            comps.hour = h.hora
            comps.minute = h.minuto
            comps.second = 0
            if let f = cal.date(from: comps) { base = f }
            conHora = true
        } else if !forzarHora {
            var comps = cal.dateComponents([.year, .month, .day], from: dia)
            comps.hour = 0
            comps.minute = 0
            comps.second = 0
            if let f = cal.date(from: comps) { base = f }
        }
        if let fechaDirecta { base = fechaDirecta }
        var salida = cal.dateComponents([.year, .month, .day, .hour, .minute], from: base)
        salida.second = 0
        return Interpretacion(componentes: salida, descripcion: describir(base, conHora: conHora, ahora: ahora))
    }
}