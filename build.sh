#!/bin/bash
# Compila Recado.app con las herramientas de línea de comandos: sin Xcode.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Recado.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARQ="$(uname -m)"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ compilando…"
swiftc -O -swift-version 5 -parse-as-library \
    -sdk "$SDK" -target "${ARQ}-apple-macos14.0" \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/Recado" \
    -framework AppKit -framework SwiftUI -framework Carbon -framework EventKit

cp Info.plist "$APP/Contents/Info.plist"

echo "→ ícono…"
if swiftc -O -sdk "$SDK" -target "${ARQ}-apple-macos14.0" Icono.swift -o build/icono 2>/dev/null \
   && ./build/icono build/icono-1024.png 2>/dev/null && [ -s build/icono-1024.png ]; then
    mkdir -p build/AppIcon.iconset
    for t in 16 32 64 128 256 512; do
        sips -z $t $t build/icono-1024.png --out "build/AppIcon.iconset/icon_${t}x${t}.png" >/dev/null
        d=$((t * 2))
        sips -z $d $d build/icono-1024.png --out "build/AppIcon.iconset/icon_${t}x${t}@2x.png" >/dev/null
    done
    iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null \
        && echo "  listo" || echo "  (sin ícono, no pasa nada)"
else
    echo "  (no se pudo dibujar el ícono, la app funciona igual)"
fi

echo "→ firmando (ad hoc)…"
codesign --force --sign - "$APP" 2>/dev/null || echo "  (firma ad hoc falló)"

# Prueba de humo: sólo interpreta fechas, no escribe nada en Recordatorios.
if [ "${RECADO_SMOKE:-1}" = "0" ]; then
    echo "→ prueba de humo: omitida (RECADO_SMOKE=0)"
else
    echo "→ prueba de humo del intérprete de fechas…"
    for caso in "hoy 4pm" "mañana 9:30" "+2h" "viernes 10am" "2026-11-20"; do
        "$APP/Contents/MacOS/Recado" --cli --simular --texto "prueba" --cuando "$caso" \
            || { echo "  ¡ojo! falló con «$caso»"; exit 1; }
    done
fi

echo
echo "Listo: $(pwd)/$APP"
