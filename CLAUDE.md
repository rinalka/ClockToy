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

The project is split across `CT8synths.scd`, `CT8harmonySelect.scd`, `CT8tracks.scd`, and
five GUI files — `CT8guiClock.scd`, `CT8guiAdjust.scd`, `CT8guiPercGenerator.scd`,
`CT8guiSynthLab.scd`, `CT8fakeData.scd` — but `CT8main.scd` loads all eight itself, in
that order, via `~loadAllCt8Files` (built on `thisProcess.interpreter.executeFile`, at
the top of the file). From a cold start (fresh boot, or after a crash), evaluating just
`CT8main.scd` is the entire startup procedure — it loads everything else itself, then
boots the audio server and starts playback. If a file fails to load (e.g. a syntax error
introduced mid-edit), it throws an `Error` pointing back at the post-window output above
it.

To reload just one file after editing it (without re-running all of `CT8main.scd`), call
`~loadCt8File.("CT8guiPercGenerator.scd")` (or whichever filename) directly.

To make a live edit take effect:
- Editing a function body in any file: re-evaluate that whole file (or use
  `~loadCt8File` for just one). Interpreter globals (`~`-prefixed environment variables)
  persist across evaluations, so this "hot reloads" the running instance without
  restarting `CT8main`.
- Editing `CT8synths.scd`'s SynthDefs specifically: re-evaluating the file re-installs
  them on the already-running server immediately (see the `if(s.serverRunning and: ...)`
  guard at the bottom of that file).
- Changing runtime parameters (tempo, real vs. simulated time, 12/24-hour format,
  per-track sound on/off, and row/col clock-face flash on/off) can all be done live via
  the "Clock Toy Adjust" window, without re-evaluating any file. All four percussion
  tracks (`PT1`-`PT4`) and both bass tracks (`BT1`-`BT2`) have their
  instrument/pattern/pitch/volume/wet/level/source configured live via the separate
  "Percussion + Bass Generator" window (`CT8guiPercGenerator.scd`) instead — see its own
  bullet below; that window is now the only live amp control for those six tracks, the
  "Synth Controls" window having been removed entirely (it had gone fully vestigial -
  see `CT8tracks.scd`'s bullet), and also the only live control for their individual
  built-in reverb tail (Wet/Level, `~percWet[name]`/`~percLevel[name]` for PT1-4,
  `~bassWet[name]`/`~bassLevel[name]` for BT1-2 - separate from `~clockRev`, which
  PT1-4 never reach anyway; see `CT8synths.scd`'s `~allpassWash` bullet). There is no
  live GUI for `~clockRev`'s own reverb parameters either (the old Reverb Controls
  window was removed, not just disabled) — adjust `~reverbDec`/`~reverbLpf`/`~reverbMix`
  in `CT8synths.scd` directly. The Synth Lab window (`CT8guiSynthLab.scd`) has its own
  "tune while it plays" mechanism: a Loop toggle + speed slider that keeps retriggering
  the selected instrument so short/percussive synths (`\hat`/`\cym`/`\baseD`/`\kick`)
  stay audible long enough to hear a slider move, including each one's own `\wet`/
  `\level` sliders - it is deliberately standalone, not connected to the live
  composition at all; its purpose is to audition/tune settings before dialing the same
  values into the Percussion + Bass Generator by hand. **Temporarily not auto-opened**
  at boot, along with the Fake Data window (`CT8fakeData.scd`), while the Percussion +
  Bass Generator's own per-track layout is being reworked - both files' functions are
  still loaded and untouched, just not auto-called (`~makeSynthLabWindow.value`/
  `~makeFakeDataWindow.value`, commented out in `CT8main.scd`/at the bottom of
  `CT8fakeData.scd` respectively); evaluate either call by hand if you need that window
  meanwhile.

`CT8main.scd` hardcodes the audio device as `"ASIO : Focusrite USB ASIO"` — on a machine
without that interface, `s.boot` will fail; change `s.options.device` accordingly.

There is no automated test suite; verification is by ear/eye (run it and watch/listen).

## Architecture

Nine files, coordinated entirely through interpreter environment variables (`~name`
globals) rather than explicit module interfaces — changing a function's name or the
shape of shared state requires grepping all files for consumers, not just the one that
defines it. `CT8synths.scd` and `CT8tracks.scd` used to be one file (`CT8syn.scd`), split
so "what sounds exist" and "how tracks are built" can be worked on independently — see
their own bullets below for exactly where the line falls:

- **`CT8guiClock.scd`** — owns clock geometry, the seven-segment display window, the scan
  from lit segments into abstract events, and the clock-face flashing itself. Its central
  product is `~clockEvents` (row-based scan) and `~columnEvents` (column-based scan):
  ordered arrays of `(row/column, panel, segment, role)` events, where `role` is an
  abstract tag like `\rowStart`/`\cell` or `\columnStart`/`\columnCell` — never a sound
  name. Also owns `~checkForNewMinute` (polled by main's TempoClock), the flash/redraw
  functions (`~flashRow`, `~flashColumn`, `~drawDigit`, `~drawPanel`), and the row/col
  flash *players* themselves (see below) — flashing is a property of the clock display,
  not of any track, and keeps running independent of whether `PT1`/`PT2` exist or are
  making sound.

- **`CT8guiAdjust.scd`** — the "Clock Toy Adjust" window: tempo (a slider fixed to
  60-240 BPM, with a label showing the current value), per-track sound on/off (one button
  per track in `~trackNames`, grouped into harmony/melody rows - `makeTrackButton`,
  via `~syncTrackPlayer` - including tracks with no builder yet, shown orange and
  enabled-but-silent), real-time vs. entered-time source, hour/minute/simulated-minute-
  length entry, 12/24-hour format, and a Colour row with two buttons (Row Clr / Col Clr,
  `makeFlashButton`) toggling `~rowFlashEnabled`/`~colFlashEnabled` (CT8guiClock.scd) via
  `~syncFlashPlayer`. No percussion or bass row any more - `PT1`-`PT4`/`BT1`-`BT2`'s
  on/off buttons moved to the Percussion + Bass Generator window
  (`CT8guiPercGenerator.scd`), next to each track's name, since that window is otherwise
  the sole home for everything else about those six tracks.

- **`CT8guiPercGenerator.scd`** — the "Percussion + Bass Generator" window
  (`~makePercGeneratorWindow`, dark-themed to match `CT8guiSynthLab.scd`): live control
  over how each of `PT1`/`PT2`/`PT3`/`PT4` (via `makeTrackSection`) and `BT1`/`BT2` (via
  `makeBassTrackSection`, a separate but near-identical closure - see its own paragraph
  below) gets generated, independently, via one repeated multi-row control block per
  track, each block its own `CompositeView` (`trackContainer`) sitting on a
  randomly-rolled muted background color (`Color.rand(0.7)`, re-rolled fresh every time
  the window is built - the same convention `CT8fakeData.scd` uses for its Actions
  plotter panel) purely to visually separate the blocks; label text inside each block is
  black (`labelColor`), not the window's own white, for contrast against it. The window
  is `resizable: true` (unlike its PT1-4-only predecessor) and tall enough for all six
  blocks plus header/buttons, in case a shorter screen still can't show all of it at
  once.
  PT1-4's blocks come first, under a "PERCUSSION + BASS GENERATOR (PT1-PT4, BT1-BT2)"
  header; BT1-2's come after, under their own "BASS GENERATOR (BT1-BT2)" sub-heading.
  Every block is split into two side-by-side panes, `leftPane` (25% of the block's
  width) and `rightPane` (75%), rather than one flat stack of rows (an earlier version's
  layout - see git history if you need it).
  `leftPane` holds 4 vertical `Slider`s: Mix/Vol are that instrument's own tiny built-in
  `~allpassWash` tail (`~percWet[name]`/`~percLevel[name]` or `~bassWet[name]`/
  `~bassLevel[name]` - see `CT8synths.scd`'s bullet; separate from the `~clockRev` send
  every other track uses, read/written live via `Pfunc` so neither needs a rebuild) -
  renamed from the old Wet/Level labels, same globals, same behavior, just moved and
  relabeled. Send A/Send B are plain `Slider`s with no backing global and no `.action_`
  - placeholders for a planned future multi-output-channel send feature, not wired to
  anything yet.
  `rightPane` has three rows:
  Row 1 is the track name + an on/off `Button` (`onOffButton`) + Source + Instrument.
  The on/off button is now a plain red/green square with no label (both `.states_`
  entries are a bare space, `" "`) - the title text beside it already names the track;
  same convention as the per-track buttons `CT8guiAdjust.scd` used to have for
  `PT1`-`PT4`/`BT1`-`BT2`, just un-labeled now. Every percussion and bass track always
  has a builder, so there's no orange/unbuilt case to handle. Source is Row scan vs.
  Column scan (`~percSource[name]`/`~bassSource[name]`); Instrument is
  `\baseD`/`\cym`/`\hat`/`\kick` (percussion) or `\fm`/`\plucking` (bass).
  Row 2 is the Pattern/Pitch/Volume menus, all together on one row - each menu's own
  sub-control (below) used to sit directly beside it on its own row; moving those down
  into row 3 freed up room for all three menus to share row 2. Pattern is the same flat
  list it always was, now thirteen entries (twelve for bass) rather than ten/nine -
  "Random" was dropped from every label (per feedback), so a pattern's label now ends in
  "%" exactly when it has a Percent sub-control to show, and doesn't when it's
  deterministic: First beat only (percussion only - not a useful choice for a bass
  part, per feedback, so `makeBassTrackSection`'s own `patternSymbols` list drops it);
  Every beat; Start of Row/Col (label tracks whichever Source is selected, `\startOnly`);
  1/8th % / 1/3 % (`\random8thPercent`/`\random3rdPercent` -
  `~percSplitPercent[name]`% of beats become a double hit/triplet, re-rolled fresh every
  rebuild); 1/8th (last of bar) / 1/3 (last of bar)
  (`\random8thLastBar`/`\random3rdLastBar` - only the bar's very last beat, deterministic,
  every bar); 1/8th (last of row/col) / 1/3 (last of row/col)
  (`\random8thLastRowCol`/`\random3rdLastRowCol` - only the last beat of every row/column
  span, deterministic); 4/3 % / 4/3 (last of bar) / 4/3 (last of row/col)
  (`\random4to3Percent`/`\random4to3LastBar`/`\random4to3LastRowCol` - the inverse of the
  1/8th/1/3 families: instead of expanding one beat into 2/3 sub-hits, these MERGE a run
  of 4 consecutive baseline beats into 3 equal-length hits spanning that same total time,
  same pitch throughout the merged group. `\random4to3Percent` rolls
  `~percSplitPercent[name]`% per non-overlapping group of 4, scanning from the bar's
  start; `\random4to3LastBar` merges only the bar's final 4 beats, every bar;
  `\random4to3LastRowCol` merges the final 4 beats of every row/column span. A bar or
  span shorter than 4 beats simply can't merge and is left as individual beats,
  unchanged - expect this with `\random4to3LastRowCol` especially, since most columns and
  many rows won't have 4 beats to begin with); Skip % (`\randomSkip` -
  `~percSplitPercent[name]`% of beats go silent, span unchanged, re-rolled fresh every
  rebuild - it used to be a fixed, non-adjustable ~1/4, now it shares the same Percent
  slider/global as the "%" split/merge patterns above, so switching between any of them
  keeps whichever percent was already set). Pitch is Fixed/Rising at
  start/Random for percussion, Fixed/Random for bass (no Rising there). Volume is
  Fixed/Alternate for both.
  Row 3 has one fixed-width `CompositeView` per menu above (`patternSubView`/
  `pitchSubView`/`volumeSubView`, each exactly as wide as its own row-2 menu so the two
  rows visually line up), holding that menu's own sub-control:
  Under Pattern, a Percent `Slider` (+ readout) - visible for every "%"-labeled pattern
  (the two 1/8th-1/3rd split percents, the 4/3 merge percent, and Skip %;
  `updatePatternPercentVisibility`, called whenever the Pattern menu changes) -
  same value/meaning as the old Percent `NumberBox`, just a `Slider` now (0-1 native,
  linlin'd to 0-100). Toggling it with `.visible_` is safe here (unlike Volume's old
  two-widget-set problem, below) since it's the *only* content in its own dedicated
  fixed-size sub-view, not a sibling of something that stays visible alongside it.
  Under Pitch, a single dual-handle `RangeSlider` (+ readout) - replacing the old
  per-mode widget set entirely (one box for Fixed/two for Rising/four for Random).
  `~percBasePitch[name]` is now always `[lo, hi]` (percussion, Hz, mapped 20-8000); bass
  has no equivalent `~bassBasePitch` any more and instead writes straight into
  `~currentRange[name]` (`CT8harmonySelect.scd`, MIDI 0-127) - the same global
  `HT1`/`MT1` already read for their own chord-note picks. Each Pitch mode just
  interprets `[lo, hi]` differently (see `~buildPercPattern`'s own comment,
  `CT8tracks.scd`, for the exact rule per mode) - Fixed reads `hi`; Random picks
  anywhere in `[lo, hi]` (chord-aware for bass, via `~chordNoteInRange`; plain `rrand`
  for percussion); Rising (percussion only) climbs from `lo` toward `hi` in 8 fixed
  steps per hit, resetting at every row/column start. Because the same slider means
  something sensible in every mode, it stays visible across all of them - nothing to
  show or hide here any more, unlike the old mode-specific widget-swapping.
  Under Volume, the same idea: one dual-handle `RangeSlider` (+ readout) for
  `~percVolumeLevels[name]`/`~bassVolumeLevels[name]`, now always `[lo, hi]` (0-4, same
  `linlin` mapping the old Volume `Slider`s used) - replacing the old
  Fixed-`Slider`-or-two-Alternate-`Slider`s switch, and the fixed-size-placeholder-
  container fix that switch used to need (two full sibling widget sets built directly
  in the same row meant the row's flow width always included both, even hidden, so
  Alternate's two sliders didn't actually fit - moving each mode's widgets into their
  own dedicated child container fixed it at the time; collapsing both modes onto one
  `RangeSlider` now makes that fix moot, since there's only ever one widget set to
  begin with). Fixed reads `hi`; Alternate alternates `hi`, `lo` every hit, high end
  first.
  A control change only updates its global, deliberately *not* rebuilding/restarting
  that track immediately - doing that would desync it from every other track, the same
  problem `CT8guiTracksLab.scd` hit and fixed by waiting for a shared rebuild point
  (Mix/Vol are the one exception, read live via `Pfunc`). The change takes effect at the
  clock's next natural rebuild automatically, or immediately via the "Apply now" button,
  which reruns the full `~stopPbinds`/`~updatePbinds`/`~restartPbinds` cycle (every
  track together) so nothing falls out of phase - and also `~rebuildFlashPatterns`/
  `~restartFlashPlayers` (`CT8guiClock.scd`), so the row/col flash restarts in lockstep
  with the Pbinds. A second "Reset to defaults" button calls `~resetPercConfig`
  (`CT8tracks.scd`) for every percussion track AND `~resetBassConfig` for every bass
  track - unlike their own `?`-based initialization (which only fills in a value the
  first time, so tuning survives a re-evaluation), these unconditionally overwrite every
  `~percX[name]`/`~bassX[name]` back to its original default - then rebuilds this whole
  window from scratch (a plain re-call of `~makePercGeneratorWindow`, since the button's
  own closure belongs to the window instance about to be replaced) and applies
  immediately the same way Apply now does.

  `makeBassTrackSection` (`BT1`/`BT2`'s block) mirrors `makeTrackSection` closely enough
  that it's kept as its own closure rather than parameterizing one function over both -
  the two tracks' choices differ enough (instrument list, pattern list, pitch units and
  mode count) that threading all of it through one shared function would need about as
  many parameters as just writing the block twice. Sets each track's
  `~bassSource`/`~bassInstrument`/`~bassPattern`/`~bassPitchMode`/`~bassVolumeMode`/
  `~bassVolumeLevels`/`~bassWet`/`~bassLevel`/`~bassSplitPercent` entry (`CT8tracks.scd`)
  plus the shared `~currentRange[name]` (`CT8harmonySelect.scd`) for pitch, which
  `~buildBassTrackPattern` reads fresh on every rebuild - same "only updates the global,
  never rebuilds immediately" discipline as PT1-4's controls, and the same Apply
  now/Reset to defaults buttons cover both track sets together.

- **`CT8guiSynthLab.scd`** — the "Endless Synth - Sound Lab" window (`~makeSynthLabWindow`):
  a standalone instrument-audition panel, incorporated from a separate file the user
  brought in (originally `Ct8synthLab.scd`). Pick a synth from a menu, hit PLAY NOTE, and
  every one of its params gets a slider with live numeric readout (`makeSlider`, generic
  over each `specs` entry's `[name, default, lo, hi, curve]`); some params (not envelope
  segment timings or the pluck excitation) update the currently-sounding note live via
  `currentSynth.set`. A LOOP toggle + interval number box repeatedly re-fires the
  currently-selected instrument on an `AppClock`-scheduled self-reschedule (same
  keep-going/return-nil-to-stop idiom as `~checkForNewMinute`/`~tempoChange`) so
  short/percussive synths (`\hat`/`\cym`/`\baseD`/`\kick`, which free themselves almost
  instantly) stay audible long enough to actually hear a slider move - STOP NOTES and
  `~stopSynthLab` both turn the loop off too, so it never outlives the notes it's
  retriggering or the window itself. Entirely self-contained: its own private stereo bus/
  Groups/`\allpassReverb` instance (`revBus`/`sourceGroup`/`fxGroup`/`reverb`, all local
  vars), completely separate from the project's shared `~revBus`/`~clockRev` - nothing
  played here reaches or affects the live clock composition. `~synthLabWindow` and
  `~stopSynthLab` (the only two globals this file needs) follow the same close-on-CmdPeriod
  convention as `~adjustWindow`/`~percGeneratorWindow`, except `~stopSynthLab` also frees the
  private Groups/Bus, not just the window - `CT8main.scd`'s `~closeWindowsOnCmdPeriod`
  calls it accordingly. Plays `\drone`/`\lead`/`\seq`/`\noise`/`\kick`/`\droneChord`/
  `\baseD` directly from `CT8synths.scd` (`\baseD` already uses a single `out` arg with no
  hardcoded extra reverb-send line, so it's directly compatible with this lab's bus
  convention), but keeps its own `\labPlucking`/`\labHat`/`\labCym` variants defined
  locally (bug-fixed, single-`out`-bus versions of this project's `\plucking`/`\hat`/
  `\cym` - `\plucking` specifically needed replumbing away from the real one's two-output
  dry+`~revBus`-send design for the lab's one-bus-per-instrument convention; `\hat`/`\cym`
  didn't have that problem, but keep their own copies anyway, consistent with the split)
  rather than reusing the real ones, to avoid an `outbus`-vs-`out` arg-name mismatch that
  would have silently routed around the lab's reverb bus. `\hat`/`\cym`/`\baseD`/`\kick`
  all now also take `\wet`/`\level` args (their own tiny built-in `~allpassWash` tail -
  see `CT8synths.scd`'s bullet below); `\labHat`/`\labCym` had to be hand-updated to match
  since nothing shares *SynthDef* code across this split, but both now call
  `~allpassWash` directly rather than hand-copying its body - it's a plain helper
  function with no bus assumptions baked in, not a SynthDef, so reusing it isn't the kind
  of sharing this split otherwise avoids. `\baseD`/`\kick` didn't need hand-updating,
  since this lab plays those two real SynthDefs directly already. `\fm` got the same
  `\labX`-variant treatment for a different reason: real `\fm`'s only reverb path used to
  be a hardcoded `fx`/`fxsend` send this lab's `trigger` never sets - playing real `\fm`
  here directly would leak a quiet, unprocessed copy of every note straight to hardware
  bus 0 (`fx`'s default), bypassing the lab's private reverb bus entirely. (Real `\fm` has
  since also gained its own `\wet`/`\level`/`~allpassWash` tail - added for `BT1`/`BT2`'s
  Wet/Level sliders, see `CT8synths.scd`'s bullet below - but that doesn't change this
  lab's `fx`/`fxsend` leak concern, which is independent of it.) `\labFm` drops
  `fx`/`fxsend` and adds its own `\wet`/`\level` - `~allpassWash` (CT8synths.scd) -
  instead, same as every other `\labX` variant now (it briefly used `FreeVerb` like they
  did, by the same mistake, since fixed); real `\fm` is otherwise untouched, since
  `HT1`/`MT1` still depend on its `fx`/`fxsend` send to reach `~clockRev`. Its `specs`
  entry's ranges are deliberately
  wider than its own SynthDef defaults - wide enough to cover every real-track preset
  already in the project (`HT1`/`MT1`'s current values, and old `PT3`'s now-retired
  snare patch) - since the point of tuning here is finding values to hand-copy into
  `CT8tracks.scd`, not just staying within `\fm`'s own defaults.

- **`CT8fakeData.scd`** — standalone (not part of the CT8synths/CT8tracks dependency
  chain), a mocked-up input-data panel for the planned "Daily Piece" generative mode (see
  the FUTURE DIRECTION note at the top of `CT8main.scd`): four editable `Plotter` curves
  (Actions, Heart Rate, Mood, Weather) standing in for real 24-hour data tables, scaled
  down to a few minutes for quick iteration.

- **`CT8harmonySelect.scd`** (new, in progress) — owns the shared harmonic concept the
  rhythm/harmony and melody tracks (`HT1`-`4`, `MT1`-`4`) are meant to eventually generate
  around: a "current chord" those tracks pick notes from, rather than each inventing its
  own pitch material independently (`PT1`-`4` are unaffected, staying on the Percussion
  Generator's own Pitch modes; `BT1`-`2` moved onto the generic Bass Generator config -
  see `CT8tracks.scd`'s BASS GENERATOR CONFIG bullet - but still read `~currentChord`
  from here for their own Random pitch mode, just once per rebuild rather than live).
  `~chords[set][chordIndex]` is one
  3-, 4-, or 5-note chord, written as real MIDI note numbers already in one specific
  octave (9 chord sets: C major/minor triads, major/minor/harmonic-minor/melodic-minor
  7ths, and major/harmonic-minor/melodic-minor 9ths - every set still has exactly 7
  chords, I-VII, so `~chordMarkov`, below, stays set-agnostic) - each entry's chord name
  (`C`, `Dm7`, `Bdim`, etc.) lives only as a trailing `//` comment there, so
  `~chordNames[set][chordIndex]` is a second table in the exact same `[set][chordIndex]`
  shape holding those same names as actual strings, purely so logging (below) can print
  one - kept in sync with `~chords` by hand, since nothing can read a comment back at
  runtime. `~keys`/`~currentKey` are the equivalent pair for transposition: `~keys` is a
  12-entry name table (`["C", "C#", ..., "B"]`), purely for logging, the same role
  `~chordNames` plays for `~chords`; `~currentKey` (0-11) doubles as both the index into
  `~keys` AND the actual semitone offset applied - no separate offset table needed, since
  a chromatic step from C already *is* the semitone count. Picking `~currentKey` from the
  last two keys via its own Markov chain (mirroring `~chordMarkov`, below) is a planned
  future step; for now it just sits at `0` (C), a complete no-op. `~currentRange[name]` is
  a `name -> [lo, hi]` dictionary (same convention as `~percX`/`~bassX`, `CT8tracks.scd`)
  holding the MIDI bounds `~chordNoteInRange` (below) picks within, per track - replacing
  what used to be a literal baked directly into each chord-aware track's own
  `~chordNoteInRange` call (`HT1`/`MT1`: 60-96; `BT1`/`BT2`: 12-59). Starts at those same
  values, just as a live global each track reads instead of a literal, so a future
  per-bar-varying range (some tracks' ranges narrow and fixed, others recalculated every
  bar - not yet designed) only has to reassign this, not touch any builder.
  `~chordNoteInRange.(chord, lo, hi)` is the one real consumer-facing function so far -
  picks a tone from `chord` at random, transposes it by `~currentKey` semitones (added
  before the `% 12`, not multiplied, and before picking candidates - transposing the
  final result afterward instead could push it outside the requested `[lo, hi]`), then
  picks again at random among every octave of that (transposed) pitch class inside
  `[lo, hi]` inclusive, so "which note" and "which octave" are two independent random
  choices. `~currentChord` is the one shared "current chord" global. Read LIVE, not
  snapshotted into a local var, by `~buildHarmonyPattern`/`~buildMelodyPattern`
  (`HT1`/`MT1`, `CT8tracks.scd`); `~buildBassTrackPattern` (`BT1`/`BT2`) also reads it, for
  their Random pitch mode specifically, but only once per rebuild. `~chordMarkov` (a
  second-order Markov table keyed by `[secondLastChord, lastChord]`, chords numbered 1-7)
  and `~computeNextChord` (walks that table, falling back to a flat weighted choice for
  any `[prev,prev]` pair it has no entry for, then advances `~secondLastChord`/
  `~lastChord` and returns the picked chord's actual MIDI notes) are the chord-progression
  engine - renamed from `~nextChord`, which is now a plain variable instead: the
  *lookahead* chord, holding whatever `~currentChord` will become at the next bar
  boundary, pre-computed ahead of time via `~computeNextChord` rather than computed in the
  moment `~checkForNewChordBar` needs it (the two couldn't both be named `~nextChord`, and
  the variable kept the name since that's the one every consumer-facing reference to "the
  next chord" actually means). `~computeNextChord` also writes `~currentChordNumber` (the
  raw 1-7 Markov chord number it picked, before the `- 1` that turns it into an array
  index) as a global rather than a local - purely so something outside it can report it;
  nothing reads it back for logic. At piece start (currently: whenever this file is
  evaluated - a real start trigger, `~startPiece`, is a planned future step),
  `~chordSet` is picked at random from all 9 sets (`(0..~chords.size - 1).choose`, no
  longer a hardcoded `2`, and no hardcoded upper bound either - it always spans however
  many sets `~chords` actually has) and `~currentChord` is set directly to that set's
  "I" chord (index `0`), with
  `~secondLastChord`/`~lastChord` seeded as though just arriving at I from IV (`1`/`4` -
  the same fixed history this file always hardcoded, just now applied to whichever set
  got picked) - `~computeNextChord` is then called once immediately so the lookahead
  `~nextChord` is ready before the first bar boundary ever needs it.
  `~checkForNewChordBar` is what actually *advances* `~currentChord` - a plain beat
  counter (`~chordBarBeatCount`), completely independent of any one track's own Pbind (it
  used to live inside `~buildMelodyPattern`'s own `\midinote` `Pfunc`, an arbitrary
  coupling since nearly every chord-aware track reads `~currentChord`, not just `MT1`):
  once `~chordBarBeatCount` reaches `~numBeats` (the same row-scan bar length `PT1`/`HT1`
  play on, re-read fresh each call so it tracks a bar length that changes mid-progression)
  it resets to 0, moves the lookahead into place (`~currentChord = ~nextChord`), posts its
  name (`~chordNames[~chordSet][~currentChordNumber - 1]`, still correctly in sync with
  the chord that was just moved into `~currentChord`, since nothing has recomputed it yet)
  alongside the raw `~currentChord` array, `~chordSet`, and the actual array index
  (`~currentChordNumber - 1`) it came from, THEN calls `~computeNextChord` again to
  refresh the lookahead for the bar after this one - that order matters, since computing
  the new lookahead first would overwrite `~currentChordNumber` before the log line reads
  it. So the Markov table's behavior can be read and verified from the post window at a
  glance, by name, not just by number. Scheduled from
  `CT8main.scd`'s boot sequence via a second `t.sched(0, {...; 1})` call, the same
  repeating-check idiom `~checkForNewMinute` already uses, once per beat. Loads right
  after `CT8guiClock.scd` and before `CT8tracks.scd`, since `~buildHarmonyPattern`/
  `~buildMelodyPattern` need `~chords`/`~currentChord`/`~chordNoteInRange` to already
  exist (though only at the point their builder is actually *called*, not at file-load
  time, so the ordering constraint is looser than it looks).

- **`CT8synths.scd`** — owns everything sound-*generating*: SynthDefs (`\plucking`,
  `\hat`, `\baseD`, `\cym`, `\fm`, `\ELIreverb`, `\drone`/`\lead`/`\seq`/`\noise`/`\kick`/
  `\droneChord`/`\allpassReverb` - incorporated from the user's Sound Lab file, not yet
  used by any track, auditioned via `CT8guiSynthLab.scd` for now; the legacy/unused
  `\bassDrum`/`\shortWhistle`/`\clockVerb` that used to live here too have been deleted
  outright, not just left unused, since nothing referenced them), `~allpassWash` (a plain
  helper function, not a SynthDef - a chain of 10 `AllpassN` filters crossfaded against
  the dry signal by `wet` and scaled by `level`, same algorithm `\allpassReverb` itself
  uses but inline rather than reading from a bus; `level` defaults to 1 here, not
  `\allpassReverb`'s own 0.6, so `wet=0, level=1` is truly a no-op), and the reverb's own
  live-adjustable `~reverbDec`/`~reverbLpf`/`~reverbMix` (for `~clockRev`, one
  long-running Synth rather than a per-note one). `\hat`/`\cym`/`\baseD`/`\kick`/`\fm`/
  `\plucking` each call `~allpassWash` on their own output now for a tiny built-in reverb
  tail, defaulting to `wet=0`/`level=1` (a no-op) so it's inaudible wherever nothing sets
  it - this *used* to be `FreeVerb` for the first four, which turned out to be a mistake
  and was swapped out project-wide. For `\baseD`/`\cym`/`\hat`/`\kick` this tail exists
  because they never had any reverb path at all - they don't declare an `\fx` arg, so the
  `\fx` key `~buildPercPattern` passes them (CT8tracks.scd) is silently ignored, unlike
  `\fm`'s real `\fx`/`\fxsend` send to `~clockRev` - so this per-voice tail is genuinely
  the only reverb `PT1`-`PT4` (via the Percussion Generator's `~percWet[name]`/
  `~percLevel[name]`/Wet+Level sliders) or `CT8guiSynthLab.scd`/`CT8guiTracksLab.scd`
  (auditioning `\baseD`/`\cym`/`\hat`/`\kick` standalone) can ever have - deliberately
  separate from `~clockRev`, not a replacement for it. `\fm`/`\plucking` got the same
  tail added later for a different reason - both already had a working path to
  `~clockRev` (`\fm`'s `fx`/`fxsend`, `\plucking`'s hardcoded `~revBus` send), but neither
  had a *per-track*, independently dialable tail the way the other four did, which is
  what `BT1`/`BT2`'s own Wet/Level sliders (Bass Generator config, `CT8tracks.scd`) need;
  both existing sends are passed through unaffected by `wet`/`level` (see each SynthDef's
  own comment). One caveat, not yet addressed for every instrument with this tail:
  `\baseD`/`\kick` free themselves via `DetectSilence` watching the tail's own
  POST-`~allpassWash` output, so a nonzero `wet`'s tail rings out fully before the synth
  frees; `\hat`/`\cym`/`\fm`/`\plucking` still free via a fixed-duration envelope/
  `Done.freeSelf` tied to the *dry* signal instead, so a nonzero `wet` on any of those
  four still gets cut off abruptly rather than ringing out - acceptable for "simple," not
  yet decoupled for these four. Knows
  nothing about tracks, patterns, or the clock face - globals are declared before any
  function, so the reverb defaults are visible at a glance. Used
  to also own `~availableSynths`/`~synthParams`/`~getSynthParam` (a per-synth live-param
  table feeding the old Synth Controls window and `CT8tracks.scd`'s amp lookups) - removed
  entirely once the Percussion Generator's own Volume row (see `CT8guiPercGenerator.scd`)
  took over as PT1-4's only amp source and the Synth Controls window (its only other
  consumer) was deleted; nothing in the project reads a per-synth param table any more.
  `\fm` is a multi-use FM synth brought in from another project; `CT8tracks.scd` uses it
  directly for `HT1`/`MT1` (no longer `PT3` - that track moved onto the generic
  Percussion Generator's `\baseD`/`\cym`/`\hat`/`\kick` instruments along with `PT1`/`PT2`/
  `PT4`) and as one of `BT1`/`BT2`'s two selectable Bass Generator instruments (the
  other, `\plucking`, has its own hand-tuned bass-register envelope - see its own
  comment in this file), each of HT1/MT1's FM params hardcoded rather than read from a
  shared table (BT1/BT2 read theirs from the generic Bass Generator config instead, same
  idea as PT1-4). `\fm`'s `fx` (reverb-send) arg must be passed explicitly as `~revBus`
  (wrapped in `Pfunc { ~revBus }` inside a Pbind, since a bare Bus value in a Pbind key is
  suspect — see `~buildPercPattern`'s `\fx` comment, CT8tracks.scd), since a SynthDef
  default can't reference a bus that doesn't exist until the server boots.

- **`CT8tracks.scd`** — owns the musical-composition side only: the track registry
  (`~trackNames`/`~trackPatterns`/`~trackPlayers`/`~trackEnabled`/`~trackBuilders`), the
  Percussion Generator config for `PT1`-`PT4` (`~percSource`/`~percInstrument`/
  `~percPattern`/`~percPitchMode`/`~percBasePitch`/`~percVolumeMode`/`~percVolumeLevels`/
  `~percWet`/`~percLevel`/`~percSplitPercent`, each a `name -> value` dictionary keyed by
  track-name symbol, set live by `CT8guiPercGenerator.scd` - `~percBasePitch[name]`/
  `~percVolumeLevels[name]` are both `[lo, hi]` pairs now (one dual-handle `RangeSlider`
  each in the GUI), not single scalars, so every Pitch/Volume mode just reads the pair
  differently rather than needing its own separate globals (the old `~percPitchStep`/
  `~percRandomPitches`/`~percVolume` are gone, superseded); `~percSplitPercent[name]`
  only matters when `~percPattern[name]` is one of the four "%"-labeled patterns
  (shared between `\random8thPercent`/`\random3rdPercent`/`\random4to3Percent`/
  `\randomSkip`, so switching a track between any of them keeps whichever percent was
  already set - `\randomSkip` used to be a fixed, non-adjustable ~1/4 before it joined
  this group; there's no separate "variant" global any
  more - the split-type/variant combination is just which flat `~percPattern[name]`
  symbol is chosen), and `~percWet[name]`/`~percLevel[name]` are the odd ones out of the
  whole group, read via plain `Pfunc`s rather than baked into a pre-resolved array like
  the rest, so unlike every other one of these each takes effect immediately with no
  rebuild needed), the parallel Bass Generator config for `BT1`-`BT2` (`~bassSource`/
  `~bassInstrument`/`~bassPattern`/`~bassPitchMode`/`~bassVolumeMode`/
  `~bassVolumeLevels`/`~bassWet`/`~bassLevel`/`~bassSplitPercent` - same shape and same
  live-`CT8guiPercGenerator.scd`-set/`?`-guarded-default convention as percussion's, just
  a shorter list since bass has fewer pitch modes, no per-instrument pitch-arg-name
  dispatch to carry, and no `~bassBasePitch` of its own at all - pitch reads the shared
  `~currentRange[name]`, `CT8harmonySelect.scd`, instead - see BASS GENERATOR CONFIG's
  own comment for exactly which differences), every
  `~buildXPattern` function that turns `CT8guiClock.scd`'s scan output into an actual
  Pbind, and the playback lifecycle (`~setStartPbinds`, `~stopPbinds`, `~updatePbinds`,
  `~restartPbinds`, `~tempoChange`, `~stopAll`, `~syncTrackPlayer`). The old
  `~rowStartSynth`/`~rowCellSynth`/`~colStartSynth`/`~colCellSynth` (vestigial since `PT1`/
  `PT2` moved onto the Percussion Generator) are gone too, now that the Synth Controls
  window that was their only remaining reader has been deleted. Knows nothing about
  flashing - that moved entirely to `CT8guiClock.scd`, so this file only has to care that
  `~rowPattern`/`~colPattern` exist and stay in sync, not whether anything visual is on or
  off. Globals are declared before any function, for the same reason as `CT8synths.scd`.
  This is expected to be the most actively-changing file as the planned generative "Daily
  Piece" hierarchy (Piece → Phrase → Bar → Beat) gets designed on top of what's here now —
  see the FUTURE DIRECTION note in `CT8main.scd`. Reads `~rowPattern`/`~colPattern`/
  `~clockEvents`/`~columnEvents` from `CT8guiClock.scd`; converts those into simultaneous
  Pbind tracks. `PT1`/`PT2`/`PT3`/`PT4` all read the Percussion Generator's per-track
  config globals via one shared, parameterized builder (`~buildPercPattern.(name)` - see
  below), rather than each having its own bespoke builder the way they used to; `BT1`/
  `BT2` mirror that exactly via their own shared builder, `~buildBassTrackPattern.(name)`,
  reading the Bass Generator config instead.

- **`CT8main.scd`** — the coordinator. Loads `CT8synths.scd`, `CT8guiClock.scd`,
  `CT8harmonySelect.scd`, `CT8tracks.scd`, and the four remaining GUI files itself
  (`~loadAllCt8Files`, via
  `thisProcess.interpreter.executeFile`), verifies the load actually succeeded, tears
  down any previous run (`~stopAll`, clears the old TempoClock), sets runtime parameters
  (`~tempo`, `~twelveHourClock`, `~runningRealTime`), boots the audio server, then
  sequences: install SynthDefs → build all windows (including `~makeSynthLabWindow`) →
  draw initial digits → scan initial events → start Pbinds → schedule two repeating
  per-beat checks, one for minute rollover (`~checkForNewMinute`) and one for the shared
  chord progression (`~checkForNewChordBar` - `CT8harmonySelect.scd`'s own bullet has the
  detail). Also contains a FUTURE
  DIRECTION comment block sketching a planned generative "Daily Piece" mode driven by
  time-of-day data tables. `s.options.memSize` is 655360 KB (640MB, up from 64MB) -
  bumped for the Sound Lab's heavier synths (`\drone`/`\kick`/`\droneChord` each run
  8-20+ simultaneous oscillators per note); this is boot-time-only and the only place it
  can take effect, since the server is already running by the time any `~makeXWindow`
  (including the Sound Lab's) gets called.

Only three tracks are currently enabled by default — `PT1`, `PT2`, `PT3` (all three
Percussion Generator-driven, see below) — out of 13 planned tracks (4 percussion
`PT1-4`, 2 bass `BT1-2`, 4 rhythm/harmony `HT1-4`, 4 melody `MT1-4`) for a planned
generative "Daily Piece" mode. `PT4`, `BT1`, `BT2`, `HT1` (a chord-per-row harmony pad),
and `MT1` (a single-note-per-column melody) all have real builders too (`PT4`/`BT1`/`BT2`
share the two generic builders, `~buildPercPattern`/`~buildBassTrackPattern`; `HT1`/`MT1`
their own bespoke ones) and are fully playable - just disabled by default until toggled
on in the Percussion + Bass Generator window (`PT4`/`BT1`/`BT2`, beside each one's name)
or the Clock Toy Adjust window (`HT1`/`MT1`); `HT2-4`/`MT2-4` are still registered but
inert (no builder exists for them yet). See the TRACK REGISTRY block in `CT8tracks.scd`:
- **`~trackNames`** — all 13 track name symbols.
- **`~trackPatterns[name]`** / **`~trackPlayers[name]`** / **`~trackEnabled[name]`** — that
  track's built Pbind, its playing `EventStreamPlayer`, and whether the user wants its
  sound playing, each a `name -> value` Event rather than one-off globals per track.
- **`~syncTrackPlayer.(name)`** — stops a track's current player, then restarts it if
  `~trackEnabled[name]` and a pattern exist; used for any future per-track on/off UI.
- **`~trackBuilders[name]`** — the function that (re)builds `~trackPatterns[name]`;
  currently `PT1`/`PT2`/`PT3`/`PT4`/`BT1`/`BT2`/`HT1`/`MT1` have one registered. `PT1`-`PT4`
  each get a small wrapper closure (`{ ~buildPercPattern.(\PT1) }`, etc.) around the one
  shared `~buildPercPattern` function; `BT1`/`BT2` mirror that with their own shared
  `~buildBassTrackPattern`; `HT1`/`MT1` keep their own bespoke builders
  (`~buildHarmonyPattern`/`~buildMelodyPattern`). Registering a builder
  for a new track name is the only step needed to bring it under the existing
  `~setStartPbinds`/`~stopPbinds`/`~updatePbinds`/`~restartPbinds` machinery, which all
  loop generically over `~trackNames` rather than hardcoding specific tracks.

`PT1`/`PT2`/`PT3`/`PT4` are now all driven identically by the Percussion Generator window
(`CT8guiPercGenerator.scd`) through one shared, parameterized builder,
`~buildPercPattern.(name)` (`CT8tracks.scd`) - replacing what used to be three different
mechanisms (PT1's own generator-driven pre-resolve, PT2's fixed two-synth-role system,
PT3's hand-tuned `~snareTemplate`). For each track, `~buildPercPattern` first picks its
scan source from `~percSource[name]`: `\row` reads `~rowPattern`/`~clockEvents` (start
role `\rowStart`), `\col` reads `~colPattern`/`~columnEvents` (start role `\columnStart`)
- defaults preserve each track's historical identity (`PT1`/`PT3` default `\row`, `PT2`/
`PT4` default `\col`). It then pre-resolves the whole bar into flat `dur`/pitch/rest
arrays (the same technique `CT8guiTracksLab.scd`'s prototype validated), per
`~percPattern[name]`: `\firstBeat`/`\everyBeat`/`\startOnly` just pick which beats of a
plain every-beat grid get a slot (one, all, or row/column-starts only); the other ten
choices all start from that same full every-beat grid and then replace some slots with
something else. Six of those ten are a (split-type, variant) combination flattened
into one symbol each - `splitCount`/`splitVariant`, derived from `pattern` via two
`switch`es, un-flatten it back inside `~buildPercPattern` - rather than a Pattern menu
plus a nested Variant sub-menu (an earlier version had exactly that, but it was both
confusing and, per feedback, buggy: the sub-menu's controls only ever rendered once; now
each combination is its own top-level `~percPattern[name]` value, so there's nothing left
to nest or to go stale). Split-type: `\random8th*` double the hit (each half the
original span), `\random3rd*` triple it (each a third). Variant: `*Percent`
(`~percSplitPercent[name]`% of beats, re-rolled fresh every rebuild, same as
`~percPitchMode[name]`'s own `\random` option), `*LastBar` (only the bar's very last
beat, deterministic, every bar), or
`*LastRowCol` (only the last beat of every row/column span, deterministic - computed as
`startIdx.drop(1).collect(_ - 1) ++ [events.size - 1]`, i.e. one beat before each start
after the first, plus the bar's final beat for the last span). Three more,
`\random4to3Percent`/`\random4to3LastBar`/`\random4to3LastRowCol`, are a second,
separate mechanism using the same three variant names (`mergeVariant`, not
`splitVariant`) but the opposite operation: instead of EXPANDING one baseline beat into
2 or 3 sub-hits, they MERGE a run of 4 consecutive baseline beats into 3 equal-length
hits spanning that same total time (`mergeStart`, a boolean array over baseline-slot
positions, marks which 4-beat groups actually merge - computed by its own
`\random`/`\lastOfBar`/`\lastOfRowCol` switch, paralleling `splitVariant`'s but
operating on groups of 4 rather than single beats). `\random4to3Percent` rolls
`~percSplitPercent[name]`% independently per non-overlapping group of 4, scanning from
the bar's start; `\random4to3LastBar` merges only the bar's final 4 beats, every bar;
`\random4to3LastRowCol` merges the final 4 beats of every row/column span (via the same
`startIdx`/`lastOfGroupIdx` span boundaries the split variant's own `*LastRowCol` uses).
A bar or span shorter than 4 beats simply isn't offered a merge and is left as
individual beats - unavoidable for `\random4to3LastRowCol` especially, since most
columns and many rows don't have 4 beats to begin with. Merging 4 slots into 3 replaces
the main per-slot loop's `.do` with a manual `while`, since a merge advances the
baseline-slot index by 4 instead of 1; the merged group's 3 hits all share the first of
the 4 slots' own pitch (same "one pitch per origin" rule the splits above already use).
The last of these thirteen choices, `\randomSkip` (label "Skip %" - silence,
`~percSplitPercent[name]`% of beats, span unchanged, always the plain-random rule,
re-rolled fresh every rebuild), stands alone - it has no
split-type/variant or merge combination, just the one behavior - but, per feedback, it
NOW shares `~percSplitPercent[name]` with every other "%"-labeled pattern above (it used
to be a fixed, non-adjustable ~1/4), so switching a track between any of these "%"
patterns and Skip % keeps whichever percent was already set. Which beats
actually rest - from either `\randomSkip` or `~trackEnabled[name]` being off - is tracked
via a parallel `restFlags` array and a `beatIndex` counter inside `\type`'s `Pfunc`, since
a `Pfunc` has no direct access to another key's own `Pseq` position. Which single instrument
plays every hit comes from `~percInstrument[name]` (`\baseD`/`\cym`/`\hat`/`\kick` - each
needs its pitch value in a different Pbind key, `\basefreq` for `\baseD`/`\cym`, `\freq`
for `\hat`, `\drumFreq` for `\kick`, picked once per rebuild via a `pitchArgName` switch
on the chosen instrument), how pitch
varies from `~percPitchMode[name]` (`~percBasePitch[name]` is `[lo, hi]` - fixed always
reads `hi`; rising climbs from `lo` toward `hi` in 8 fixed steps per hit, resetting at
every start; random picks anywhere in `[lo, hi]`), and how amp varies from
`~percVolumeMode[name]` (`~percVolumeLevels[name]` is also `[lo, hi]` - fixed reads
`hi`; alternate alternates `hi`/`lo` every sounding hit) - this last one is a flat
`Pseq`, not folded into the
`\type` Pfunc, since (unlike `restFlags`) amp has no need to read `~trackEnabled[name]`.
`\wet`/`\level` keys (`Pfunc { ~percWet[name] }`/`Pfunc { ~percLevel[name] }`) set that
instrument's own tiny built-in `~allpassWash` tail (CT8synths.scd) - the two keys here
that are genuinely live, since each is a single flat value with nothing to pre-resolve,
unlike everything else in this Pbind.
All four are purely musical - `\type` goes to `\rest` when `~trackEnabled[name]` is off or
(for `\randomSkip`) when this beat was chosen as a rest (the standard Event mechanism for
"build this event's other keys as normal, but don't spawn a synth for it"), but none of
them drive the clock-face
flash; that's a fully independent process (`~buildRowFlashPattern`/`~buildColFlashPattern`,
`CT8guiClock.scd` - see below), tied only to `PT1`/`PT2`'s roles regardless of whether
those tracks are enabled, built, or even exist. `HT1`/`MT1` are both `\fm`-based, with
their params hardcoded directly in each builder rather than read from any shared table,
and both read the one shared `~currentChord` global (`CT8harmonySelect.scd`)
live - not snapshotted into a local var, so a chord change is heard on whichever track's
very next hit comes after it, regardless of which of them is enabled/playing. `HT1` is
derived from `~rowPattern`: it plays one new chord at every `\rowStart` in the current
scan, holding for exactly that row's span in beats (computed fresh each rebuild from
`~rowPattern`, same grid `PT1` plays on) - so it changes chord in lockstep with `PT1`'s
row boundaries rather than on a fixed schedule of its own; its `\atk`/`\rel` are computed
per-event from that beat span converted to real seconds via `t.tempo`, since the SynthDef's
own envelope times are wall-clock seconds, not TempoClock beats. Its `\midinote` used to
be a fixed 3-chord `Pseq`; now it's a `Pfunc` - `Array.fill(4, { ~chordNoteInRange.(
~currentChord, ~currentRange[\HT1][0], ~currentRange[\HT1][1]) })`, 4 independent
tone-and-octave picks within `~currentRange[\HT1]` (60-96 by default, three octaves
above middle C) - but still fires exactly once per row event either way, so the
"one new chord per row-start" cadence is unchanged, only where the notes come from
differs. `MT1` mirrors `HT1`'s structure but from `~colPattern`/`\columnStart`
instead of `~rowPattern`/`\rowStart` (one slot per column instead of per row), with two
deliberate differences from `HT1`, per feedback that a MELODY track should be built the
same way a BASS track is rather than just being `HT1` on a different scan: its
`\midinote` is a single `~chordNoteInRange.(~currentChord, ~currentRange[\MT1][0],
~currentRange[\MT1][1])` pick, not an `Array.fill(4, {...})` chord stab - a melody plays
one note at a time, never a chord, unlike `HT1` (still a live-re-rolling `Pfunc`, so the
melody varies bar to bar even when that minute's column layout doesn't change - used to
pick 1-or-2 notes from a fixed white-keys scale, before the `Array.fill(4, ...)` chord
version, before this single-note version); and its `\amp` is no longer a hardcoded flat
value but reads `~hmVolumeMode[\MT1]`/`~hmVolumeLevels[\MT1]` (the Harmony + Melody
Generator window's own Volume row, `CT8guiHarmonyMelodyGenerator.scd` - built earlier as
a placeholder, now actually wired up for this one track), resolved once per column-slot
via the exact same Fixed-reads-hi/Alternate-flips-hi-lo `nextAmp` convention
`~buildBassTrackPattern` uses for `BT1`/`BT2`, rather than live per-hit. Neither `HT1`
nor `MT1` advances the chord progression itself - see `~checkForNewChordBar`,
`CT8harmonySelect.scd`'s own bullet, for where that lives instead.

`BT1`/`BT2` are driven by the Bass Generator config exactly the way `PT1`-`PT4` are
driven by the Percussion Generator config - same single-source-scan/pre-resolve-the-bar
technique, through their own shared, parameterized builder,
`~buildBassTrackPattern.(name)` (`CT8tracks.scd`), replacing `BT1`'s old bespoke builder
(a fixed `Ppar` of a row-start AND a column-start sub-pattern running simultaneously,
always both at once) and giving `BT2` a real builder for the first time. Each of
`BT1`/`BT2` instead picks ONE scan via `~bassSource[name]` (`\row`/`\col`, same as
`PT1`-`4`) - running `BT1` on `\row` and `BT2` on `\col` (their defaults) approximates the
old single `BT1`'s "both at once" behavior, just as two independent tracks instead of
one `Ppar`. `~bassInstrument[name]` picks `\fm` or `\plucking` (`BT1`/`BT2` default to one
each) - both take a plain `\midinote` key (no per-instrument pitch-arg-name dispatch
needed, unlike `~buildPercPattern`'s `pitchArgName` switch) and a plain `\amp` key (no
amp-arg-name dispatch either). `~bassPitchMode[name]` is Fixed (reads the high end of
`~currentRange[name]`, `CT8harmonySelect.scd`, a plain MIDI note) or Random (picks a
tone from `~currentChord` via `~chordNoteInRange`, constrained to that same
`[lo, hi]`) - no separate `~bassBasePitch` any more, both modes share
`~currentRange[name]` (12-59, "below middle C", by default, and now live-adjustable
from this window's own Pitch `RangeSlider` too), the same global `HT1`/`MT1` read live,
just resolved once per rebuild here instead - so a mid-bar chord change isn't heard on
`BT1`/`BT2` until their next rebuild, unlike `HT1`/`MT1`'s live per-hit read. `\fx`
reaches `~clockRev` through `\fm`'s real `fx`/`fxsend` send (ignored by `\plucking`, which
has no `\fx` arg - its own hardcoded, independently-attenuated `~revBus` send, via its
own `dynamic` arg, is separate and untouched either way - see `CT8synths.scd`'s bullet);
`\wet`/`\level` are each instrument's own tiny built-in `~allpassWash` tail, same
live-`Pfunc` convention as `~percWet[name]`/`~percLevel[name]`. Every
built track (`PT1-4`/`BT1-2`/`HT1`/`MT1`), plus every other still-unbuilt track, can be
toggled independently at runtime via `~trackEnabled[name]` - `PT1`-`4`/`BT1`-`2` have
their on/off buttons in the Percussion + Bass Generator window
(`CT8guiPercGenerator.scd`), beside each track's name; every other track has its own
on/off button in the Clock Toy Adjust window (`CT8guiAdjust.scd`) instead.

**Track Copy ("Copy T")** — `CT8tracks.scd`'s TRACK COPY section, restricted to
`BT1`/`BT2`/`MT1`-`4` only (not `HT1`-`4`/`PT1`-`4` - both bass and melody are single-
note-per-event, so a `(dur, midinote)` pair means the same thing on either side of a
copy; harmony plays chords and percussion's pitch is Hz, neither fits). No GUI yet -
tried by hand from the post window: `~copyTStartRecord.(sourceName, beats)` tapes that
track's actual sounding `(dur, midinote)` pairs for the next `beats` TempoClock beats
into `~copyBuffer` (only real `\note` hits, never rests - this feature doesn't try to
preserve a recording's silence, per feedback); `~copyTStartPlayback.(destName)` then has
`destName` splice that buffer in, verbatim, in place of its own normal pitch/duration
(same instrument/amp/wet/pan/everything else about it untouched) until the buffer runs
out, then falls straight back to its own normal pattern. `~makeCopyAwarePair` is the
shared mechanism both `~buildBassTrackPattern` and `~buildMelodyPattern`'s `\dur`/
`\midinote` keys go through instead of a plain `Pseq`/`Pfunc` - each wraps a retained,
manually-advanced stream of that track's own normal pattern, so pausing it to serve a
copy and resuming afterward picks up exactly where it left off, with no separate
"resume position" bookkeeping needed. `~copyTapFor.(name)`, a trailing `\copyTap` key on
every eligible track's Pbind, is the recorder side, reading back the FINAL resolved
`\dur`/`\midinote`/`\type` for that event (after any override above has already had its
say) the same way `HT1`'s own `\rel` key already reads back `ev[\dur]`. Each playback
snapshots `~copyBuffer` into its own `~copyPlayBuffer[name]` the moment it starts, so a
later recording finishing can't disturb a playback already under way elsewhere; its own
`~copyPlayIdx[name]` is a global, not a Pbind-local var, so a rebuild mid-playback
(minute change, Apply now) resumes from where it was rather than restarting the buffer.
Note-cutoffs were the one thing asked to be handled carefully: recording only checks its
beat countdown AFTER subtracting a captured hit's own duration, so the last note always
finishes naturally rather than being truncated to land exactly on the requested beat
count; playback only ever swaps in a COMPLETE `(dur, midinote)` pair at an event boundary
(a Pbind asks for these once per event, never mid-event), so falling back to the normal
pattern once the buffer is exhausted always happens cleanly between notes.

Row/col clock-face flashing is a separate, independent process from any of the above now
— see `CT8guiClock.scd`'s "ROW/COL FLASH PLAYERS" section: `~buildRowFlashPattern`/
`~buildColFlashPattern` build visual-only Pbinds (always `\type, \rest`, so they never
spawn a synth) that walk the same `~clockEvents`/`~columnEvents` PT1/PT2 read, calling
`~flashRow`/`~flashColumn` via `\updateGUI`, gated by `~rowFlashEnabled`/
`~colFlashEnabled` (both default `true`). `~rebuildFlashPatterns`/`~restartFlashPlayers`/
`~stopFlashPlayers` mirror `~updatePbinds`/`~restartPbinds`/`~stopPbinds`'s shape but are
called alongside them, not through them - every place that rebuilds tracks after a scan
(minute rollover, source/format toggles) also rebuilds the flash patterns, and
`~stopAll` also calls `~stopFlashPlayers`. `~syncFlashPlayer.(\row` or `\col)` is what the
Colour row's two buttons (`CT8guiAdjust.scd`) call to toggle one live.

`~rowPattern`/`~colPattern` are separate from the above: plain Arrays (not Pbinds),
re-published from `~clockEvents`/`~columnEvents` every time the scan re-runs, meant as
shared input for every future track's generator — not just PT1/PT2's own sound.
`~numBeats` is `~rowPattern.size`. All three are computed and declared in
`CT8guiClock.scd`, not `CT8tracks.scd`, even though only `CT8tracks.scd`'s builders read
them — the segment/panel geometry that scan needs only exists in `CT8guiClock.scd`, so
that's the only file that can actually produce them; look there for "what shared state
exists," not in `CT8tracks.scd`.
