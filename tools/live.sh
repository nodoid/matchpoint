#!/bin/sh
# live.sh [out.png] [wait] - boot the tape in Oricutron full screen and grab
# the Oric picture.
#
# No key presses: the game's attract screen starts a demo rally by itself after
# two seconds.  Scripted keys are unreliable here because Oricutron only takes
# them while its window has the keyboard focus, and the terminal keeps taking
# it back between commands.
#
#   OCDIR  directory holding the Oricutron data files (roms/, tapes/)
#   OCBIN  the emulator binary; the 0.9 .app bundle is x86 only
OUT=${1:-/tmp/matchpoint.png}
WAIT=${2:-26}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OCDIR=${OCDIR:-$HOME/Downloads/Oricutron_osx_v09}
OCBIN=${OCBIN:-$HOME/RiderProjects/oricutron/oricutron}

pkill -x oricutron 2>/dev/null
sleep 1
( cd "$OCDIR" && nohup "$OCBIN" -R soft -m atmos -k none --vsynchack on \
    -t "$ROOT/build/matchpoint.tap" -a </dev/null >/tmp/oricutron.log 2>&1 & )
sleep "$WAIT"
screencapture -x /tmp/matchpoint_raw.png

python3 - "$OUT" <<'PY'
import sys
from PIL import Image

# Find the emulator's picture rather than guessing where the window is: the
# court is the only large patch of saturated green, yellow or white on screen.
# A screenshot of a locked or covered display has none of those, and silently
# saving the desktop is worse than failing.
ORIC = {(0, 255, 0), (0, 220, 0), (255, 255, 0), (255, 0, 0),
        (0, 255, 255), (255, 0, 255), (255, 255, 255)}
im = Image.open("/tmp/matchpoint_raw.png").convert("RGB")
px = im.load()
w, h = im.size
cols = [x for x in range(w)
        if sum(1 for y in range(0, h, 4) if px[x, y] in ORIC) > 3]
rows = [y for y in range(h)
        if sum(1 for x in range(0, w, 4) if px[x, y] in ORIC) > 3]
if not cols or not rows:
    sys.exit("no Oric picture on screen: is the display unlocked and "
             "Oricutron in front?")
box = (max(0, cols[0] - 4), max(0, rows[0] - 4),
       min(w, cols[-1] + 5), min(h, rows[-1] + 5))
im.crop(box).save(sys.argv[1])
print(sys.argv[1], box)
PY
