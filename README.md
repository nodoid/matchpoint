# Match Point for the Oric Atmos

A recreation of Psion's 1984 tennis game *Match Point* for the 48K Oric Atmos.
You stand at the near baseline looking down the court, the computer stands at
the far one, and the ball has a real height: it arcs over the net, bounces, and
drops into it if you hit too low.

The picture is HIRES (240x200), the court is drawn in perspective, and the three
character rows underneath carry the messages. The scoreboard across the top is
`YOU` and `COMPUTER` against sets, games and points, scoring 0, 15, 30, 40 and
advantage as tennis does, with games to six (two clear) and the match to the
first player to take two sets. Points are announced by chord on the AY-3-8912.

The title screen also sets up the match: the arrows choose a surface (which sets
the stroke pace and how much speed a bounce keeps) and an opponent grade (which
sets the computer's shuffle speed and reach).

## Building

You need [cc65](https://cc65.github.io/) (`cl65`, `ca65`, `ld65`) and Python 3.

```sh
make            # builds build/matchpoint.tap
make run        # boots the tape in Oricutron and grabs the window
make sim        # runs the tape on a host 6502 and renders the screen
```

`build/matchpoint.tap` loads and runs on an Atmos from BASIC with `CLOAD""`, or
with `oricutron -m atmos -t build/matchpoint.tap -a`.  A ready-made tape ships
with this repository at that path, so `git clone` alone is enough to try it:
only rebuild if you change the sources.

## Controls

| Key | Action |
|-----|--------|
| Arrow keys | move around your half of the court; on the title screen pick the surface and the opponent |
| Space or `M` | start, serve, and hold to lob instead of drive |

You return the ball automatically when it reaches you and you are standing
close enough: the shot goes into the court the computer has left, so the game is
about getting across in time. Hold fire as the ball arrives to lob it instead of
driving it.

## How it is put together

| File | What it does |
|------|--------------|
| `src/header.s` | tape and BASIC headers so the file autoloads |
| `src/hw.s` | VIA, AY-3-8912, keyboard matrix, 50Hz frame timer |
| `src/screen.s` | HIRES screen, plotting, lines, sprites, the game's own font |
| `src/match.s` | the court, the ball, the players, the hitting and the match |
| `src/zp.inc` | zero page: the screen pointers, then the ball, players and score |
| `src/hw.inc` | hardware addresses, court geometry and the key matrix positions |

### The court

Depth runs 0 at the far baseline to 127 at the near one, and x runs 64 to 192
between the sidelines with the centre at 128. Depth is 8.8 fixed point and only
seven bits wide on purpose: with a top of 127, a ball that runs off the far
baseline goes negative and can still be told apart by its sign bit.

The projection, for a half width `halfw` at that depth, is

```
line    = 40 + (depth * 9) >> 3
halfw   = 52 + (depth >> 1) - (depth >> 4)
sx      = 120 + ((x - 128) * halfw) >> 6
```

so the far baseline is 104 pixels wide and the near one 216. The court is drawn
once; only the two players and the ball are saved and restored each frame.

### The colours

The Oric has no colour registers.  A video byte whose bits 6 and 5 are both
clear is a serial attribute: it sets the ink or the paper for the rest of that
scanline, and is itself drawn as one character cell of the new paper colour.
So a court line is black outside, yellow across the run-off, green for the
court itself, then yellow and black again, and the stands are white speckle on
magenta and cyan paper alternating row by row.  The run-off is a quarter of the
half width plus twelve pixels, so it widens towards the near baseline the way
the original's does, and the ink attribute is set to white before the paper
goes green so the line work itself is white on green.  The passes run in this
order:

* `hud_draw` blanks the top of the picture, lays the speckle and colours the
  stands, then draws the banner box and its text;
* `court_draw` draws every line, then `court_colour` writes the attributes for
  each row, one cell outside each sideline so they never paint over the lines,
  and finishes with `apron`, the solid yellow bands above the far baseline and
  below the near one.

Attribute cells are six pixels wide, which is why the run-off and the stand
colours step rather than following the perspective exactly.

### The sound

`src/hw.s` contains a three-instruction bus driver for the AY-3-8912 (register,
value, set) and `src/match.s` sequences short step tables on top of it: the
serve toss, the racket thwack, the bounce, the net thud and win/lose chords,
plus a blip for the title menu. The module runs from the same 50Hz frame tick
as the rest of the game.

### The ball

Position and velocity are 8.8 fixed point, with the height in pixels. Each frame
it takes gravity (16/256 px per frame per frame), moves in all three axes, and:

* if it reaches the ground it bounces with three quarters of its speed, and is
  damped until it rests;
* if it crosses the net plane below the top of the net, the hitter loses the
  point - a serve into the net is a fault instead;
* when it reaches the player it is coming to, that player returns it if they are
  within reach and the ball is low enough, otherwise the point is awarded;
* a ball that leaves the court past a baseline loses the point for the player
  standing there, and one that leaves past a sideline loses it for the hitter.

A serve must land in the service box across the net, alternating sides every
game: a miss is a fault and the serve is taken again, and two faults running
give the receiver the point. Every groundstroke adds a little pace, capped at
four pixels per frame, so a rally quickens until a player finally cannot get to
the ball; the serves themselves step through four depths so roughly one in four
lands long and is faulted.

### The sprites

The two players and the ball keep every court byte they cover: each frame
`saves` run first, `stamps` second, and the next frame's `erase_all` restores
the rects registered by the previous one. Two flags keep the contract intact:
`ba_on` means "a rect is pending erase" and is only cleared once the restore
has actually run, while `ba_live` is the separate on-screen gate for the
stamps, so a ball going off court can never cancel an erase that is still
owed. The score digits painted on the court are redrawn by `hud_draw` on every
score change and are picture, not residue.

## Testing

`tools/simrun.py` runs the tape image on a host 6502 (py65) with enough of the
VIA and AY modelled to serve the keyboard, then renders the screen the way the
ULA would. It is the quick way to see a screen without the emulator:

```sh
# the attract screen starts a demo rally by itself after two seconds, then
# keeps playing; stop on a frame boundary so the sprites are all drawn
python3 tools/simrun.py --steps 700000 --until wait_frame \
    --until-after 600000 --out build/render.png

# or hold keys down to play it yourself: fire to start, fire again to serve
python3 tools/simrun.py --steps 300000 \
    --press 4:0:120000:130000 --press 4:0:160000:170000 --out build/sim.png
```

`--until SYM` stops when the PC reaches a label and `--until-after N` ignores
it until N steps have run, so `--until wait_frame` gives a whole frame rather
than a snapshot taken halfway through drawing it.

`tools/live.sh [out.png]` boots the tape in Oricutron full screen and grabs the
window.  It needs the machine unlocked and the emulator's window in front:
scripted key presses only reach the emulator once its window has the keyboard
focus, which is why the game can also start a demo rally on its own.

`--press ROW:COL:FROM:TO` holds a key matrix position down between two
instruction counts. Space is row 4, column 0. `--trace ADDR` prints a byte
whenever it changes, which is how the match state (`$40`), who hit last (`$42`)
and the score (`$44`) can be followed step by step.

## What is in and what is not

Working: the title, the perspective court with its service boxes and net, the
serve with faults and double faults, the rally with drives and lobs, the net and
the lines, the computer opponent at three grades, a choice of surface, the
sound effects, and the full 0/15/30/40/advantage scoring through games and the
best-of-three-sets match.

Simplified compared with the Psion original: the shot is returned automatically
when you are in position rather than by pressing a hit key at the right moment,
there are no serve-and-volley positions to hold, and a set has no tie-break -
games to six with two clear, or deuce and advantage on and on as before.

## Licence

DILLIGAF: "Do I Look Like I Give A Fuck". See [LICENSE](LICENSE) - do what you
like with this code, no conditions, no warranty of any kind. That covers the
code and assets written for this project, not Psion's 1984 original.
