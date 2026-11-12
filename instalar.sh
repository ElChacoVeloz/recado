#!/bin/bash
# Instala Recado.app en ~/Applications y lo deja arrancando solo.
# Otro destino: RECADO_DESTINO=/ruta/Recado.app ./instalar.sh
set -euo pipefail
cd "$(dirname "$0")"

DESTINO="${RECADO_DESTINO:-$HOME/Applications/Recado.app}"
PLIST="$HOME/Library/LaunchAgents/me.recado.Recado.plist"
UID_ACTUAL="$(id -u)"

[ -x "build/Recado.app/Contents/MacOS/Recado" ] || { echo "primero corre ./build.sh"; exit 1; }

echo "→ instalando en $DESTINO"
# rm -rf antes de copiar: cp -R sobre un bundle existente mete la app dentro de
# sí misma y se sigue corriendo el binario viejo.
mkdir -p "$(dirname "$DESTINO")"
rm -rf "$DESTINO"
cp -R "build/Recado.app" "$DESTINO"

echo "→ LaunchAgent"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>me.recado.Recado</string>
    <key>ProgramArguments</key>
    <array><string>$DESTINO/Contents/MacOS/Recado</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict><key>SuccessfulExit</key><false/></dict>
    <key>ProcessType</key><string>Interactive</string>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/Recado.err</string>
</dict>
</plist>
PLISTEOF

# bootstrap puede devolver "5: Input/output error" si el job anterior no
# terminó de morir: hay que reintentar en vez de darlo por fallo.
launchctl bootout "gui/$UID_ACTUAL/me.recado.Recado" >/dev/null 2>&1 || true
sleep 2
for intento in 1 2 3; do
    if launchctl bootstrap "gui/$UID_ACTUAL" "$PLIST" 2>/dev/null; then break; fi
    echo "  reintentando bootstrap ($intento)…"
    sleep 2
done
sleep 1

echo "→ estado"
launchctl print "gui/$UID_ACTUAL/me.recado.Recado" 2>/dev/null | grep -E "state|pid" | head -3 || echo "  (no arrancó)"
echo
echo "Listo. Atajo: ⌃⌥⇧R  ·  log: ~/Library/Logs/Recado.log"
