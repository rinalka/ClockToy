# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ClockToy is a SuperCollider (.scd) project: a digital clock rendered as a seven-segment
display whose currently-lit segments are scanned into musical events and sonified in
real time. CT8 is the current iteration; `CT7*.scd` files present here are the prior
iteration kept for reference/diffing. `backup 8/` and `old 8/` are snapshots of earlier
CT8 states, not active code — don't edit them, and don't treat them as current behavior.

## Running the project

There is no build step; SuperCollider evaluates source directly in the IDE (blocks
wrapped in parens `( ... )` are evaluated as a unit with Ctrl/Cmd+Enter).

The project is split across `CT8synths.scd`, `CT8tracks.scd`, and five GUI files —
`CT8guiClock.scd`, `CT8guiAdjust.scd`, `CT8guiSynth.scd`, `CT8guiReverb.scd`,
`CT8fakeData.scd` — but `CT8main.scd` loads all seven itself, in that order, via
`~loadAllCt8Files` (built on `thisProcess.interpreter.executeFile`, at the top of the
file). From a cold start (fresh boot, or after a crash), evaluating just `CT8main.scd` is
the entire startup procedure — it loads everything else itself, then boots the audio
server and starts playback. If a file fails to load (e.g. a syntax error introduced
mid-edit), it throws an `Error` pointing back at the post-window output above it.

To reload just one file after editing it (without re-running all of `CT8main.scd`), call
`~loadCt8File.("CT8guiSynth.scd")` (or whichever filename) directly.

To make a live edit take effect:
- Editing a function body in any file: re-evaluate that whole file (or use
  `~loadCt8File` for just one). Interpreter globals (`~`-prefixed environment variables)
  persist across evaluations, so this "hot reloads" the running instance without
  restarting `CT8main`.
- Editing `CT8synths.scd`'s SynthDefs specifically: re-evaluating the file re-installs
  them on the already-running server immediately (see the `if(s.serverRunning and: ...)`
  guard at the bottom of that file).
- Changing runtime parameters (tempo, 12/24-hour, real vs. simulated time, per-track
  on/off for all 13 tracks) can also be done live via the "Clock Toy Adjust" window,
  without re-evaluating any file. Synth Controls/Reverb Controls are currently disabled
  (see below) pending a rewrite, so which synth plays which role on `PT1`/`PT2` and the
  reverb's live parameters are for now only changeable by editing `CT8tracks.scd`/
  `CT8synths.scd` directly.

`CT8main.scd` hardcodes the audio device as `"ASIO : Focusrite USB ASIO"` — on a machine
without that interface, `s.boot` will fail; change `s.options.device` accordingly.

There is no automated test suite; verification is by ear/eye (run it and watch/listen).

## Architecture

Eight files, coordinated entirely through interpreter environment variables (`~name`
globals) rather than explicit module interfaces — changing a function's name or the
shape of shared state requires grepping all files for consumers, not just the one that
defines it. `CT8synths.scd` and `CT8tracks.scd` used to be one file (`CT8syn.scd`), split
so "what sounds exist" and "how tracks are built" can be worked on independently — see
their own bullets below for exactly where the line falls:

- **`CT8guiClock.scd`** — owns clock geometry, the seven-segment display window, and the
  scan from lit segments into abstract events. Its central product is `~clockEvents`
  (row-based scan) and `~columnEvents` (column-based scan): ordered arrays of
  `(row/column, panel, segment, role)` events, where `role` is an abstract tag like
  `\rowStart`/`\cell` or `\columnStart`/`\columnCell` — never a sound name. Also owns
  `~checkForNewMinute` (polled by main's TempoClock) and the flash/redraw functions
  (`~flashRow`, `~flashColumn`, `~drawDigit`, `~drawPanel`).

- **`CT8guiAdjust.scd`** — the "Clock Toy Adjust" window: tempo (a slider fixed to
  60-240 BPM, with a label showing the current value), per-track on/off (one button per
  track in `~trackNames`, grouped into percussion/bass/harmony/melody rows - including
  tracks with no builder yet, shown orange and enabled-but-silent), real-time vs.
  entered-time source, hour/minute/simulated-minute-length entry, and 12/24-hour format.
  `PT1`/`PT2` each get two buttons instead of one, on two different rows: a Snd button
  (`makeSoundButton`, `~trackEnabled[name]`) on the Percussion row, and a Clr button
  (`makeFlashButton`, `~trackFlashEnabled[name]`) on a dedicated Colour row kept at the
  very bottom of the window, separate from the track rows - so their sound and their
  clock-face flash/background color can be silenced independently; see
  `~trackShouldPlay`/`~syncTrackPlayer` (CT8tracks.scd) for how the shared player keeps
  running for either.

- **`CT8guiSynth.scd`** — the "Synth Controls" window: two pairs of dropdown menus (Row
  Start/Cell, Col Start/Cell) to assign *any* installed synth to any of the four role
  slots, live, plus one control row per synth in `~availableSynths` (CT8synths.scd),
  generated generically from that table. **Currently disabled** — `CT8main.scd` no longer
  calls `~makeSynthWindow`, pending a rewrite ("an all new method"); the function/file
  still loads and works if called manually, but the four role-assignment defaults it used
  to set (`~rowStartSynth`/`~rowCellSynth`/`~colStartSynth`/`~colCellSynth`) now live in
  `CT8tracks.scd` instead, so `PT1`/`PT2` keep working without this window.

- **`CT8guiReverb.scd`** — the "Reverb Controls" window: live Dec/LPF/Mix knobs for the
  persistent reverb Synth (`~clockRev`, running `\ELIreverb`), calling `.set` directly on
  it rather than going through `~synthParams` (it isn't retriggered per note like the
  per-note synth knobs in `CT8guiSynth.scd`). **Currently disabled** alongside Synth
  Controls, pending the same rewrite (planned to add a third reverb version and fold this
  into Synth Controls); `~reverbDec`/`~reverbLpf`/`~reverbMix` already default in
  `CT8synths.scd` independent of this window, so `~clockRev` is unaffected.

- **`CT8fakeData.scd`** — standalone (not part of the CT8synths/CT8tracks dependency
  chain), a mocked-up input-data panel for the planned "Daily Piece" generative mode (see
  the FUTURE DIRECTION note at the top of `CT8main.scd`): four editable `Plotter` curves
  (Actions, Heart Rate, Mood, Weather) standing in for real 24-hour data tables, scaled
  down to a few minutes for quick iteration.

- **`CT8synths.scd`** — owns everything sound-*generating*: SynthDefs (`\plucking`,
  `\hat`, `\baseD`, `\cym`, `\fm`, `\ELIreverb`, plus legacy/unused `\bassDrum`/
  `\shortWhistle`/`\clockVerb`), the `~availableSynths` table (`[synthName, [paramName,
  lo, hi, default, step], ...]`) that drives both the Synth Controls window and
  `~getSynthParam` (the lookup `CT8tracks.scd`'s Pbinds use to read live parameter
  values), and the reverb's own live-adjustable `~reverbDec`/`~reverbLpf`/`~reverbMix`
  (separate from `~availableSynths`/`~synthParams`, since `~clockRev` is one long-running
  Synth rather than a per-note one). Knows nothing about tracks, patterns, or the clock
  face - globals are declared before any function, so `~availableSynths` and the reverb
  defaults are visible at a glance. `\fm` is a multi-use FM synth brought in from another
  project — not wired into `~availableSynths` (so it isn't selectable from the Synth
  Controls window's Row/Col menus, and doesn't get live per-parameter knobs); `CT8tracks.scd`
  uses it directly for `PT3`/`HT1`/`MT1`/`BT1`, each with FM params hardcoded rather than
  read from a shared table. `\fm`'s `fx` (reverb-send) arg must be passed explicitly as
  `~revBus` (wrapped in `Pfunc { ~revBus }` inside a Pbind, since a bare Bus value in a
  Pbind key is suspect — see `~buildRowPattern`'s `\fx` comment, CT8tracks.scd), since a
  SynthDef default can't reference a bus that doesn't exist until the server boots.

- **`CT8tracks.scd`** — owns the musical-composition side: the track registry
  (`~trackNames`/`~trackPatterns`/`~trackPlayers`/`~trackEnabled`/`~trackFlashEnabled`/
  `~trackBuilders`), the row/col→synth role-assignment defaults
  (`~rowStartSynth`/`~rowCellSynth`/`~colStartSynth`/`~colCellSynth`), every
  `~buildXPattern` function that turns `CT8guiClock.scd`'s scan output into an actual
  Pbind, and the playback lifecycle (`~setStartPbinds`, `~stopPbinds`, `~updatePbinds`,
  `~restartPbinds`, `~tempoChange`, `~stopAll`, `~trackShouldPlay`, `~syncTrackPlayer`).
  Globals are declared before any function, for the same reason as `CT8synths.scd`. This
  is expected to be the most actively-changing file as the planned generative "Daily
  Piece" hierarchy (Piece → Phrase → Bar → Beat) gets designed on top of what's here now
  — see the FUTURE DIRECTION note in `CT8main.scd`. Reads `~availableSynths`/
  `~getSynthParam` from `CT8synths.scd` and `~rowPattern`/`~colPattern`/`~clockEvents`/
  `~columnEvents` from `CT8guiClock.scd`; converts those into simultaneous Pbind tracks,
  two of which (`PT1`/`PT2`) read `~rowStartSynth`/`~rowCellSynth` or
  `~colStartSynth`/`~colCellSynth` to decide which installed synth plays which role —
  freely reassignable live, not fixed to a particular track.

- **`CT8main.scd`** — the coordinator. Loads `CT8synths.scd`, `CT8guiClock.scd`,
  `CT8tracks.scd`, and the four remaining GUI files itself (`~loadAllCt8Files`, via
  `thisProcess.interpreter.executeFile`), verifies the load actually succeeded, tears
  down any previous run (`~stopAll`, clears the old TempoClock), sets runtime parameters
  (`~tempo`, `~twelveHourClock`, `~runningRealTime`), boots the audio server, then
  sequences: install SynthDefs → build all windows → draw initial digits → scan initial
  events → start Pbinds → schedule a repeating per-beat check for minute rollover
  (`~checkForNewMinute`). Also contains a FUTURE DIRECTION comment block sketching a
  planned generative "Daily Piece" mode driven by time-of-day data tables.

Six tracks are currently active — `PT1` (row scan), `PT2` (column scan), `PT3` (a fixed
percussion hit pattern), `HT1` (a chord-per-row harmony pad), `MT1` (a note-or-two-per-
column melody), `BT1` (a two-pitch bass hit on every row/column start) — one of each of
percussion/bass/rhythm-harmony/melody from 13 planned tracks (4 percussion `PT1-4`, 1
bass `BT1`, 4 rhythm/harmony `HT1-4`, 4 melody `MT1-4`) for a planned generative "Daily
Piece" mode; `PT4`/`HT2-4`/`MT2-4` are registered but inert. See the TRACK REGISTRY block
in `CT8tracks.scd`:
- **`~trackNames`** — all 13 track name symbols.
- **`~trackPatterns[name]`** / **`~trackPlayers[name]`** / **`~trackEnabled[name]`** — that
  track's built Pbind, its playing `EventStreamPlayer`, and whether the user wants its
  sound playing, each a `name -> value` Event rather than one-off globals per track.
- **`~trackFlashEnabled[name]`** — PT1/PT2-only: whether that track's clock-face flash/
  background color is wanted, independent of `~trackEnabled`'s sound switch (see the two
  paragraphs below). **`~trackShouldPlay.(name)`** — whether that track's
  `EventStreamPlayer` should be running at all (normally just `~trackEnabled[name]`,
  except PT1/PT2 also count `~trackFlashEnabled`). **`~syncTrackPlayer.(name)`** — stops a
  track's current player, then restarts it if `~trackShouldPlay` and a pattern exist;
  called by every on/off button (CT8guiAdjust.scd) so both kinds of toggle resync the same
  way.
- **`~trackBuilders[name]`** — the function that (re)builds `~trackPatterns[name]`;
  currently `PT1`/`PT2`/`PT3`/`HT1`/`MT1`/`BT1` have one registered (`~buildRowPattern`/
  `~buildColumnPattern`/`~buildSnarePattern`/`~buildHarmonyPattern`/`~buildMelodyPattern`/
  `~buildBassPattern`). Registering a builder for a new track name is the only step
  needed to bring it under the existing
  `~setStartPbinds`/`~stopPbinds`/`~updatePbinds`/`~restartPbinds` machinery, which all
  loop generically over `~trackNames` rather than hardcoding specific tracks.

`PT1` scans lit segments row-by-row (5 visual rows; first lit cell per row is
`\rowStart`, rest are `\cell`); `PT2` scans column-by-column (12 columns across 4 digits;
first lit cell per column is `\columnStart`, rest are `\columnCell`). Which synth plays
each role is picked by `~rowStartSynth`/`~rowCellSynth`/`~colStartSynth`/`~colCellSynth`
— not fixed to a particular track, freely reassignable by editing those globals directly
while the Synth Controls window (which used to expose them live) is disabled. Both
Pbinds' sound and clock-face flash are independently switchable even though they come
from the same event stream: each has a `\type` key that goes to `\rest` when
`~trackEnabled[name]` is off (the standard Event mechanism for "build this event's other
keys as normal, but don't spawn a synth for it"), and an `\updateGUI` key that skips its
flash call when `~trackFlashEnabled[name]` is off - both keys always return a non-nil
value regardless of which branch runs, since a Pfunc yielding bare `nil` is SC's
stream-protocol signal for "this stream has ended" (see `~dbgBeatBar`'s comment, same
file, for the bug this avoids).
`PT3` is different in kind: a hand-tuned `\fm` "snare" patch on a fixed 64-step hit/rest
template (`~snareTemplate`), nearest-neighbor resampled to `~numBeats` on every rebuild so
its loop always spans exactly one `PT1` bar; it isn't derived from `~clockEvents`/
`~columnEvents` at all, so unlike `PT1`/`PT2` it has no segment/flash tied to its hits, and
it bypasses `~availableSynths`/`~getSynthParam` entirely (its FM params are hardcoded
directly in `~buildSnarePattern` rather than being live-adjustable from the Synth Controls
window). `HT1` is also `\fm`-based and also bypasses `~availableSynths`, but unlike `PT3`
it is derived from `~rowPattern`: it plays one new chord (`\midinote` set to an array,
which Event/Pbind expands into simultaneous notes) at every `\rowStart` in the current
scan, holding for exactly that row's span in beats (computed fresh each rebuild from
`~rowPattern`, same grid `PT1` plays on) - so it changes chord in lockstep with `PT1`'s
row boundaries rather than on a fixed schedule of its own; its `\atk`/`\rel` are computed
per-event from that beat span converted to real seconds via `t.tempo`, since the SynthDef's
own envelope times are wall-clock seconds, not TempoClock beats. `MT1` mirrors `HT1`'s
structure exactly but from `~colPattern`/`\columnStart` instead of `~rowPattern`/
`\rowStart` (one slot per column instead of per row): rather than a fixed precomputed
chord sequence, its `\midinote` is a `Pfunc` that re-rolls live on every read, picking 1 or
2 random notes from the white keys (natural notes) one octave above `HT1`'s chord
register, so the melody varies bar to bar even when that minute's column layout doesn't
change. `BT1` is the low `\fm` hit that used to fire once per `PT1` cycle, before it was
pulled out into its own track: `~buildBassPattern` builds two independent sub-patterns -
one hit at every `\rowStart` in `~rowPattern` (midinote 20, same pitch as the original
hit) and one hit at every `\columnStart` in `~colPattern` (midinote 32, an octave higher)
- run simultaneously via `Ppar`, since the row-scan and column-scan grids have different
beat counts and can't share one `\dur` sequence; each sub-pattern's `\dur` is however many
beats that row/column spans, mirroring `HT1`/`MT1`'s row/column-span technique. All six,
plus every other still-unbuilt track, can be toggled independently at runtime via
`~trackEnabled[name]` - every track in `~trackNames` now has its own on/off button in the
Clock Toy Adjust window (`CT8guiAdjust.scd`), not just `PT1`/`PT2`; `PT1`/`PT2`
additionally have a separate `~trackFlashEnabled[name]` toggle for their flash.

`~rowPattern`/`~colPattern` are separate from the above: plain Arrays (not Pbinds),
re-published from `~clockEvents`/`~columnEvents` every time the scan re-runs, meant as
shared input for every future track's generator — not just PT1/PT2's own sound.
`~numBeats` is `~rowPattern.size`. All three are computed and declared in
`CT8guiClock.scd`, not `CT8tracks.scd`, even though only `CT8tracks.scd`'s builders read
them — the segment/panel geometry that scan needs only exists in `CT8guiClock.scd`, so
that's the only file that can actually produce them; look there for "what shared state
exists," not in `CT8tracks.scd`.
