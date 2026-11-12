# Recado

A tiny window to dictate a reminder **or a calendar event** without opening
anything else. It lives in the macOS menu bar, opens with **⌃⌥⇧R**, and writes
straight into Apple Reminders or your calendars through EventKit.

No Xcode: `swiftc` from the Command Line Tools builds the app, draws the icon,
signs it ad hoc and leaves a LaunchAgent behind.

The interface and the date grammar are in Spanish, because that is the language
it was written to be typed in.

## Requirements

- macOS 14 or later.
- Command Line Tools (`xcode-select --install`). Full Xcode is not needed.
- Permission to write to Reminders and Calendars — the first time the app runs,
  macOS asks once for each.

## Build and install

```bash
./build.sh        # compiles build/Recado.app, draws the icon, signs ad hoc
./instalar.sh     # copies it to ~/Applications and registers the LaunchAgent
```

`RECADO_SMOKE=0 ./build.sh` skips the date-parser smoke test that runs at the
end of the build. `RECADO_DESTINO=/somewhere/Recado.app ./instalar.sh` installs
outside `~/Applications`.

**Every rebuild invalidates the privacy permission.** The signature is ad hoc,
so the `cdhash` changes and macOS treats the binary as new: after compiling you
have to press *Allow* again in Reminders and in Calendars, once each. The footer
of the window shows the current state of both grants.

## Usage

1. ⌃⌥⇧R (or click the menu bar icon).
2. Pick **Recordatorio** or **Evento** in the selector at the top.
3. Type and press ⏎. Esc closes.
4. The *Cuándo* field takes plain language:

   `hoy 4pm` · `mañana 9:30` · `+2h` · `en 45 minutos` · `viernes 10am`
   `próximo lunes 9:00` · `2026-11-20` · `20/12 8:00` · `25 de diciembre 7pm`

   Empty means no due date. A bare hour (`4`) means 4 in the afternoon.

   **Events** also take ranges: `hoy 4-6pm`, `10am a 11:30`,
   `de 4 a 6 de la tarde`, `11pm a 1am` (ends the next day). No time at all makes
   it an all-day event; an open range defaults to one hour. Events carry a
   10-minute alarm.

5. In *Evento* mode, an empty *Cuándo* makes the app look inside the title:
   `Comida con Ana mañana 1-3pm` becomes "Comida con Ana" from 13:00 to 15:00.
   Same with bare dates: `Cumple de Ana 25 de diciembre`.

6. Destination: the selector starts on the system default list or calendar. You
   can force one at the end of the text with `@Casa` or `@Work`.

## Inbox (pushing from outside)

The app polls `~/Library/Application Support/Recado/bandeja.jsonl` every 2 s and
runs each line with **its own** permissions. This is the way to create events
from another machine: a binary launched over SSH inherits sshd's permission, not
the app's.

```json
{"tipo":"evento","texto":"Comida con Ana","cuando":"mañana 1-3pm","destino":"Personal"}
{"tipo":"recordatorio","texto":"Comprar café","cuando":"hoy 5pm","destino":"Casa"}
```

The file is deleted once processed; the result lands in
`~/Library/Logs/Recado.log`.

## Headless mode

```bash
RECADO=~/Applications/Recado.app/Contents/MacOS/Recado
"$RECADO" --cli --texto "Llamar al dentista" --cuando "hoy 4pm"
"$RECADO" --cli --evento --texto "Gym" --cuando "mañana 6-7:30am" --calendario "Work"
"$RECADO" --cli --simular ...   # parse only, saves nothing
"$RECADO" --listas
"$RECADO" --calendarios
```

Over SSH the CLI can read reminders but not write calendars, for the permission
reason above — use the inbox for that.

## Notes

- EventKit, not AppleScript: the app sees every real list and calendar, with no
  Automation prompt.
- The default list name follows the system language: EventKit calls it
  "Recordatorios", AppleScript calls it "Reminders". Same list, which is why the
  default is asked for with `defaultCalendarForNewReminders()`.
- Time zone: the user's current one (`TimeZone.current`). `RECADO_ZONA` — a tz
  identifier such as `Europe/Madrid` — overrides it for the parser.
- Signals, for testing without a keyboard: SIGUSR1 opens the panel, SIGWINCH
  opens it in event mode, SIGUSR2 saves, SIGHUP leaves a PNG in
  `~/Library/Logs/Recado-vista.png`.

## License

MIT — see [LICENSE](LICENSE).
