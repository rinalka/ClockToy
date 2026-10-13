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
  `~monoWet[name]`/`~monoLevel[name]` for BT1-2 - separate from `~clockRev`, which
  PT1-4 never reach anyway; see `CT8synths.scd`'s `~allpassWash` bullet). There is no
  live GUI for `~clockRev`'s own reverb parameters either (the old Reverb Controls
  window was removed, not just disabled) — adjust `~reverbDec`/`~reverbLpf`/`~reverbMix`
  in `CT8synths.scd` directly. The Synth Lab window (`CT8guiSynthLab.scd`) has its own
  "tune while it plays" mechanism: a Loop toggle + speed slider that keeps retriggering
  the selected instrument so short/percussive synths (`\hat`/`\cym`/`\baseD`/`\kick`)
  stay audible long enough to hear a slider move, including each one's own `\wet`/
  `\level` sliders - it is deliberately standalone, not connected to the live
  composition at all; its purpose is to audition/tune settings before dialing the same
  values into the Percussion + Bass Generator by hand. Re-enabled per feedback -
  `~makeSynthLabWindow.value` is back in `CT8main.scd`'s boot sequence, auto-opening it
  alongside every other window again. The Fake Data window (`CT8fakeData.scd`) is
  still **not auto-opened** at boot, while the Percussion + Bass Generator's own
  per-track layout is being reworked - its own function is still loaded and untouched,
  just not auto-called (`~makeFakeDataWindow.value`, commented out at the bottom of
  `CT8fakeData.scd`); evaluate it by hand if you need that window meanwhile.

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
  `makeMonoTrackSection`, a separate but near-identical closure - see its own paragraph
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
  `~allpassWash` tail (`~percWet[name]`/`~percLevel[name]` or `~monoWet[name]`/
  `~monoLevel[name]` - see `CT8synths.scd`'s bullet; separate from the `~clockRev` send
  every other track uses, read/written live via `Pfunc` so neither needs a rebuild) -
  renamed from the old Wet/Level labels, same globals, same behavior, just moved and
  relabeled. Send A/Send B (relabeled "SdA"/"SdB" - were "Dry"/"Rev") are real now too,
  per feedback (the "mixer phase" - see `CT8tracks.scd`'s own AUX SENDS bullet for the
  full mechanism): `~sendAAmt[name]`/`~sendBAmt[name]`, same live-`Pfunc`,
  no-rebuild-needed convention as Mix/Vol. `rightPane` gained one more row for this too
  - Send A/Send B's own target-effect menus, picking which of `~auxEffectNames` each
  one's amount actually feeds - sitting after whichever other rows a given block
  already had (so last for `makeTrackSection`'s own three rows below; after the COPY
  TRACK ROW, further down, for `makeMonoTrackSection`'s four).
  Row 1 is the track name + an on/off `Button` (`onOffButton`) + Source + Instrument.
  The on/off button is now a plain red/green square with no label (both `.states_`
  entries are a bare space, `" "`) - the title text beside it already names the track;
  same convention as the per-track buttons `CT8guiAdjust.scd` used to have for
  `PT1`-`PT4`/`BT1`-`BT2`, just un-labeled now. Every percussion and bass track always
  has a builder, so there's no orange/unbuilt case to handle. Source is Row scan vs.
  Column scan (`~percSource[name]`/`~monoSource[name]`); Instrument is
  `\baseD`/`\cym`/`\hat`/`\kick` (percussion) or `\fm`/`\plucking` (bass).
  Row 2 is the Pattern/Pitch/Volume menus, all together on one row - each menu's own
  sub-control (below) used to sit directly beside it on its own row; moving those down
  into row 3 freed up room for all three menus to share row 2. Pattern is the same flat
  list it always was, now thirteen entries (twelve for bass) rather than ten/nine -
  "Random" was dropped from every label (per feedback), so a pattern's label now ends in
  "%" exactly when it has a Percent sub-control to show, and doesn't when it's
  deterministic: First beat only (percussion only - not a useful choice for a bass
  part, per feedback, so `makeMonoTrackSection`'s own `patternSymbols` list drops it);
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
  start/Random/Falling at start/Looping at start for percussion (its own separate
  Hz-based scheme - unrelated to the below; Falling is Rising's mirror, per feedback -
  starts at `hi`
  and steps down toward `lo` in the same 8 fixed steps, but WRAPS back to `hi` once
  it would go below `lo`, rather than clamping and staying there the way Rising does;
  Looping starts at the midpoint of `[lo, hi]`, picks a random direction - up or down -
  once per start, then REVERSES direction at whichever bound it reaches instead of
  wrapping or clamping, bouncing back and forth);
  Fixed/Random/Rising/Falling/Looping/Arp Rising/Arp Falling/Arp Looping for bass, in
  that menu order (chord/scale-based -
  see
  `~buildMonoTrackPattern`'s own bullet, `CT8tracks.scd`, and `~chordRootInRange`/
  `~chordTopInRange`/`~makeRisingPitchGen`/`~makeFallingPitchGen`/`~makeLoopingPitchGen`/
  `~chordArpIntervals`,
  `CT8harmonySelect.scd`'s
  own bullet - the three Arp modes reuse the exact same Rising/Falling/Looping
  generator functions, just stepping through the current chord's own tones instead of
  its parent scale's degrees). Whenever Dur Pat (same menu, directly to Pitch's own
  left) is one of the three 1/8th patterns (`\random8thPercent`/`\random8thLastBar`/
  `\random8thLastRowCol`) OR one of the three 1/3rd patterns (`\random3rdPercent`/
  `\random3rdLastBar`/`\random3rdLastRowCol` - the 4/3 family does NOT get its own set
  of Arp sub-variants, per feedback - "the 4/3 Dur pat is done there will be no sub
  variants," settling what an earlier pass had left as "a planned separate later
  step"), each of the three Arp modes expands into
  its own family of sub-variants in this same menu - a DIFFERENT set of four for 1/3rd
  than the three for 1/8th, per feedback: Up/Down/Ran for 1/8th (Arp Rising Up/Down/Ran,
  Arp Falling Up/Down/Ran, Arp Looping Up/Down/Ran - 9 entries, turning the base 8
  Pitch choices into 14 while a 1/8th pattern is selected), or Repeat/Up/Down/Lop for
  1/3rd (Arp Rising Repeat/Up/Down/Lop, Arp Falling Repeat/Up/Down/Lop, Arp Looping
  Repeat/Up/Down/Lop - 12 entries, turning the base 8 into 17 while a 1/3rd pattern is
  selected). The menu's own item list is rebuilt live by `updatePitchMenuItems`
  (`CT8guiPercGenerator.scd`/`CT8guiHarmonyMelodyGenerator.scd`'s own
  `makeMonoTrackSection`) every time Dur Pat changes, picking between
  `basePitchSymbols`/`basePitchLabels` (8), `pitchSymbols18`/`pitchLabels18` (14), and
  `pitchSymbols13`/`pitchLabels13` (17) - `baseArpOf` always collapses
  `~monoPitchMode[name]` back to its bare Arp symbol first (it recognizes symbols from
  EITHER extended family), then `upVariantOf`/`repeatVariantOf` re-expands it into
  whichever family is now showing (defaulting to that family's own first entry - Up for
  1/8th, Repeat for 1/3rd) - so jumping directly from a 1/8th pattern to a 1/3rd one (or
  back) renormalizes correctly too, not just toggling to/from the plain base 8, and the
  global never ends up pointing at a symbol the currently-visible list doesn't contain.
  Both families only change anything inside their own kind of split - the FIRST note of
  a 1/8th split pair, or a 1/3rd triplet, still always comes from the normal Rising/
  Falling/Looping generator call, same as every other Pit Pat; it's only the REMAINING
  note(s) that these sub-variants touch, in `~buildMonoTrackPattern`'s own
  split-handling code (`CT8tracks.scd`), via two DIFFERENT helpers
  (`CT8harmonySelect.scd`) depending on which family: 1/8th uses `~chordStepTone` -
  Up/Down always step one fixed direction, Ran rerolls a fresh random direction per
  split pair, and if the current chord has no tone exactly a whole TONE (2 semitones)
  away in that direction, it falls back to a SEMITONE, and if even that isn't a chord
  tone, it just repeats the first note. 1/3rd uses the separate `~chordSemitoneStep`
  instead - per feedback, correcting an earlier misreading of the same instruction:
  "very similar to 1/8 BUT arp rising will repeat the note[: an explicit Repeat
  choice, see below,] and instead of moving by tones[, like 1/8 does,] [it moves by]
  semi tones where possible, repeat when not possible [if even a semitone isn't a
  chord tone]" - so 1/3rd's Up/Down/Lop never attempt a whole-tone step at all, only
  ever a semitone, falling straight back to a repeat if that one semitone isn't
  available either. Repeat is its own explicit choice that just repeats the first
  note across all 3 (the plain pre-this-feature behavior, now surfaced as a named
  option rather than only reachable as a fallback); Up walks UP the triplet two
  `~chordSemitoneStep` calls in a row (note 2 from note 1, note 3 from note 2 - "play
  the first note, go up a semitone, then another semitone," per feedback); Down
  mirrors it walking down; Lop arcs up then back down (note 2 up from note 1, note 3
  down from note 2) - a little loop/arch shape across the triplet, distinct from Up or
  Down's straight run (this exact shape for "Lop" is this session's own
  interpretation of a deliberately terse instruction, not something the user spelled
  out note-by-note - worth a sanity-check by ear against intent). Every other Pit Pat
  choice, including the bare, un-suffixed Arp modes if either extended pattern happens
  to still show them (e.g. right after `~resetMonoConfig`, before
  `updatePitchMenuItems` has had a chance to run against the live Dur Pat), falls
  through to the older "same pitch for every sub-hit in the split" behavior unchanged.
  Volume is
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
  steps per hit, resetting at every row/column start; Falling (percussion only) is its
  mirror, resetting to `hi` at every row/column start and stepping down toward `lo` in
  the same 8 fixed steps, but wrapping back to `hi` (not clamping, the way Rising does)
  once it would go below `lo`; Looping (percussion only) starts at the midpoint of
  `[lo, hi]`, picks a random direction (up or down) fresh at every row/column start, then
  steps in that direction in the same 8 fixed steps - but REVERSES direction at
  whichever bound it reaches, bouncing back and forth, rather than wrapping or clamping.
  Because the same slider means
  something sensible in every mode, it stays visible across all of them - nothing to
  show or hide here any more, unlike the old mode-specific widget-swapping.
  Under Volume, the same idea: one dual-handle `RangeSlider` (+ readout) for
  `~percVolumeLevels[name]`/`~monoVolumeLevels[name]`, now always `[lo, hi]` (0-4, same
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
  (`CT8tracks.scd`) for every percussion track AND `~resetMonoConfig` for every bass
  track - unlike their own `?`-based initialization (which only fills in a value the
  first time, so tuning survives a re-evaluation), these unconditionally overwrite every
  `~percX[name]`/`~monoX[name]` back to its original default - then rebuilds this whole
  window from scratch (a plain re-call of `~makePercGeneratorWindow`, since the button's
  own closure belongs to the window instance about to be replaced) and applies
  immediately the same way Apply now does.

  `makeMonoTrackSection` (`BT1`/`BT2`'s block) mirrors `makeTrackSection` closely enough
  that it's kept as its own closure rather than parameterizing one function over both -
  the two tracks' choices differ enough (instrument list, pattern list, pitch units and
  mode count) that threading all of it through one shared function would need about as
  many parameters as just writing the block twice. Sets each track's
  `~monoSource`/`~monoInstrument`/`~monoPattern`/`~monoPitchMode`/`~monoVolumeMode`/
  `~monoVolumeLevels`/`~monoWet`/`~monoLevel`/`~monoSplitPercent` entry (`CT8tracks.scd`)
  plus the shared `~currentRange[name]` (`CT8harmonySelect.scd`) for pitch, which
  `~buildMonoTrackPattern` reads fresh on every rebuild - same "only updates the global,
  never rebuilds immediately" discipline as PT1-4's controls, and the same Apply
  now/Reset to defaults buttons cover both track sets together.

- **`CT8guiSynthLab.scd`** — the "Endless Synth - Sound Lab" window (`~makeSynthLabWindow`):
  a standalone instrument-audition panel, incorporated from a separate file the user
  brought in (originally `Ct8synthLab.scd`). Pick a synth from a menu, hit PLAY NOTE, and
  every one of its params gets a slider with live numeric readout (`makeSlider`, generic
  over each `specs` entry's `[name, default, lo, hi, curve]` - `curve` is `\lin`/`\exp`
  for most params, positioning the slider linearly or exponentially across `[lo, hi]`,
  or `\midi` (added per feedback, for `\droneChord`'s own `note1`-`note4` - below) which
  positions the slider exactly like `\lin` but rounds every value a drag or a typed
  number produces to the nearest integer and shows 0 decimals instead of 3, since a
  fractional MIDI note (e.g. `48.237`) is a real but out-of-tune pitch once `.midicps`'d,
  not the clean semitone picking a note should land on); some params (not envelope
  segment timings or the pluck excitation) update the currently-sounding note live via
  `currentSynth.set`. Per feedback, selecting an instrument here (`populateLiveOverrides`,
  called from both `menu.action` and once at the window's own initial build, so the
  default-selected instrument gets identical treatment to one picked by hand) also
  populates `~labLiveOverrides` (`CT8tracks.scd`'s own SYNTH LAB LIVE OVERRIDES bullet
  has the full mechanism) with every one of that instrument's own tunable params
  (`\wet`/`\level`/any `\noteN` excluded), clearing whatever a previously-selected
  instrument had been pushing - every slider's own callback both updates
  `currentSynth` (if one's still playing) and writes into `~labLiveOverrides`, so
  whichever live track is currently using that same instrument follows the slider too.
  Per feedback ("set the text color to red... for any controls that are being
  controlled by clocktoy when it is running"), `makeSlider`'s own label text turns red
  instead of white for exactly the params `~labLiveOverrides` is currently tracking for
  whichever instrument is selected (an `isLive` flag `rebuild` computes per slider,
  checking `~labLiveOverrides[selected][sp[0]]`) - `populateLiveOverrides` has to run
  BEFORE `rebuild`, not after, so this check sees the CURRENT instrument's own set, not
  a stale one from whatever was selected before. The two top-level Reverb sliders
  (Wet/dry, Output level - this lab's own private reverb, unrelated to any live track)
  never pass `isLive`, so they stay white always.
  A LOOP toggle + interval number box repeatedly re-fires the
  currently-selected instrument on an `AppClock`-scheduled self-reschedule (same
  keep-going/return-nil-to-stop idiom as `~checkForNewMinute`/`~tempoChange`) so
  short/percussive synths (`\hat`/`\cym`/`\baseD`/`\kick`, which free themselves almost
  instantly) stay audible long enough to actually hear a slider move - STOP NOTES and
  `~stopSynthLab` both turn the loop off too, so it never outlives the notes it's
  retriggering or the window itself. Entirely self-contained: its own private stereo bus/
  Groups/`\allpassReverb` instance (`revBus`/`sourceGroup`/`fxGroup`/`reverb`, all local
  vars), completely separate from the project's shared `~revBus`/`~clockRev` - nothing
  played here reaches or affects the live clock composition. Every note here routes to
  `revBus` as its OWN `\out` arg (`trigger`'s own code), which `reverb` then sends on to
  hardware `out: 0` - this bus is the ONLY path to output, not a parallel dry+wet send,
  so whatever `revWet`/`revLevel` (its own Wet/dry and Output level sliders) are set to
  colours EVERY instrument unconditionally, on top of whatever that instrument's own
  `\wet`/`\level` tail (if it has one) is separately set to. `revWet`/`revLevel` now
  default to `0`/`1` (were `0.4`/`0.6`) - per feedback ("there is that issue with the
  reverb, so turn the synthlab reverb off"), matching the project's universal
  wet=0/level=1 no-op convention everywhere else, since the old nonzero default was
  colouring every instrument's sound here unconditionally, independent of (and
  compounding with) its own tail - this was making `\droneChord` in particular not
  sound like its own true, dry self when auditioned here. The two sliders still exist
  and still work live if a reverb tail is wanted while tuning. `\droneChord`'s own
  `specs` entry (below) is kept in sync with the real SynthDef's defaults for the same
  reason - it had drifted (amp/attack/sustain/release still read the synth's OLD
  defaults after a tuning pass changed them, and `\wet`/`\level` weren't in this entry
  at all), so auditioning here started from a different sound than the live composition
  actually makes. `~synthLabWindow` and
  `~stopSynthLab` (the only two globals this file needs) follow the same close-on-CmdPeriod
  convention as `~adjustWindow`/`~percGeneratorWindow`, except `~stopSynthLab` also frees the
  private Groups/Bus, not just the window - `CT8main.scd`'s `~closeWindowsOnCmdPeriod`
  calls it accordingly. Plays `\drone`/`\lead`/`\seq`/`\noise`/`\kick`/`\droneChord`/
  `\shimmerPad`/`\baseD` directly from `CT8synths.scd` (`\baseD`/`\shimmerPad` already use
  a single `out` arg with no
  hardcoded extra reverb-send line, so they're directly compatible with this lab's bus
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
  Generator's own Pitch modes; `BT1`-`2` moved onto the generic Mono Track config -
  see `CT8tracks.scd`'s MONO TRACK CONFIG bullet - but still read `~currentChord`
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
  runtime. `~scales[set]` is a third table, flat (not `[set][chordIndex]` - every chord
  within one set shares the same parent scale, so the extra dimension would just repeat
  the same array seven times) holding that set's own 7-degree scale as semitone offsets
  from the tonic (e.g. `~scales[0]` is `[0, 2, 4, 5, 7, 9, 11]`, the major scale, for set
  0's major triads) - what the Rising pitch mode (`~buildMonoTrackPattern`/
  `~buildMelodyPattern`, `CT8tracks.scd`) climbs through. No chromatic scale is defined -
  no chord set needs one. `~keys`/`~currentKey` are the equivalent pair for transposition: `~keys` is a
  12-entry name table (`["C", "C#", ..., "B"]`), purely for logging, the same role
  `~chordNames` plays for `~chords`; `~currentKey` (0-11) doubles as both the index into
  `~keys` AND the actual semitone offset applied - no separate offset table needed, since
  a chromatic step from C already *is* the semitone count. Picking `~currentKey` from the
  last two keys via its own Markov chain (mirroring `~chordMarkov`, below) is a planned
  future step; for now it just sits at `0` (C), a complete no-op. `~currentRange[name]` is
  a `name -> [lo, hi]` dictionary (same convention as `~percX`/`~monoX`, `CT8tracks.scd`)
  holding the MIDI bounds `~chordNoteInRange` (below) picks within, per track - replacing
  what used to be a literal baked directly into each chord-aware track's own
  `~chordNoteInRange` call (`HT1`/`MT1`: 60-96; `BT1`/`BT2`: 12-59). Starts at those same
  values, just as a live global each track reads instead of a literal, so a future
  per-bar-varying range (some tracks' ranges narrow and fixed, others recalculated every
  bar - not yet designed) only has to reassign this, not touch any builder.
  `~chordNoteInRange.(chord, lo, hi)` picks a tone from `chord` at random, transposes it
  by `~currentKey` semitones (added before the `% 12`, not multiplied, and before picking
  candidates - transposing the final result afterward instead could push it outside the
  requested `[lo, hi]`), then picks again at random among every octave of that
  (transposed) pitch class inside `[lo, hi]` inclusive, so "which note" and "which octave"
  are two independent random choices - the Random pitch mode's own function.
  `~chordRootInRange.(chord, lo, hi)` is its deterministic sibling, for Fixed, Rising,
  and Looping (all three start from the same root) -
  same transpose-then-match-every-octave approach, but always `chord[0]` (the chord's own
  root, as written) and always the LOWEST matching octave inside `[lo, hi]`, not a random
  pick. `~makeRisingPitchGen.(chord, intervals, lo, hi)` returns a stateful zero-arg
  generator for the Rising pitch mode: starts at `~chordRootInRange`'s own note, then each
  later call climbs one further degree up `intervals`, extending into higher
  octaves once they're exhausted; once the next degree would land above
  `hi`, it wraps back to the start note and climbs again ("the whole thing starts over,"
  per feedback, not clamping and staying there the way percussion's own, unrelated Rising
  pitch mode does). `intervals` isn't resolved inside the generator - the CALLER decides
  what list of semitone offsets to pass: `~scales[~chordSet]` (the current chord's
  parent scale) for plain Rising, or `~chordArpIntervals.(chord)` (below) for Arp
  Rising, so this one function and its two siblings below serve both pairs of modes.
  `~chordTopInRange.(chord, lo, hi)` is `~chordRootInRange`'s own
  mirror, for Falling - same approach but the HIGHEST matching octave inside `[lo, hi]`,
  since Falling starts at the top of the range and descends.
  `~makeFallingPitchGen.(chord, intervals, lo, hi)` is `~makeRisingPitchGen`'s mirror:
  starts at `~chordTopInRange`'s own note, descends `intervals` one degree per
  call (extending into LOWER octaves), and wraps back to the top once the next degree
  would land below `lo`. `~makeLoopingPitchGen.(chord, intervals, lo, hi)` is a third
  variant, per feedback: starts at `~chordRootInRange`'s own note (same starting point
  Rising uses), picks a random direction (up or down) once, then steps through
  `intervals` in that direction like Rising/Falling do - but instead of
  wrapping back to the start once it would cross a bound, it REVERSES direction at
  whichever bound it reaches and continues stepping from there, bouncing between `lo`
  and `hi` indefinitely; the reversing call recomputes its own step in the new
  direction immediately, rather than re-emitting the turning-point note (which would
  otherwise repeat it twice in a row). `~chordArpIntervals.(chord)`, per feedback, is
  the intervals list behind the three Arp modes (Arp Rising/Arp Falling/Arp Looping) -
  each chord tone's offset from the chord's own root (`chord[0]`), e.g. `[60, 64, 67]`
  gives `[0, 4, 7]`, deliberately not re-transposed by `~currentKey` here since
  `~chordRootInRange`/`~chordTopInRange` already transpose the root itself, and a fixed
  interval structure doesn't change under transposition. For exactly a 3-note chord,
  the root an octave up is appended, turning the 3-note shape into a 4-note arpeggio
  (`[0, 4, 7]` -> `[0, 4, 7, 12]`) - 4- and 5-note chords are left as-is. A fresh
  generator (any of the three, plain or Arp) is made
  once per rebuild (same
  as the plain
  `durs`/pitch arrays every chord-aware track already pre-resolves once per bar), so the
  climb/descent/bounce resets only at the next full bar, never at a row/column-start
  within it -
  a row/column-boundary-aware version is a planned, separate, future step, per feedback.
  `~chordStepTone.(chord, key, note, dir)` and `~chordSemitoneStep.(chord, key, note,
  dir)` are the pair of helpers behind the 1/8th and 1/3rd Arp sub-variant families
  respectively (only offered, in the Pitch menu, when Dur Pat is one of those six
  patterns - see that menu's own bullet, `CT8guiPercGenerator.scd`, for the full
  picture): given one note (the first note of a 1/8th split pair, or any note within a
  1/3rd triplet), each derives the NEXT one, checking the CURRENT chord
  (`chord.collect { |n| (n + key) % 12 }`, every tone's pitch class, not just the root)
  for a tone at the candidate pitch class. `~chordStepTone` (1/8th) tries a whole TONE
  (2 semitones) in `dir` (`1` up, `-1` down) first; if the chord has no tone there,
  falls back to a SEMITONE in the same direction; if the chord has no tone there
  either, gives up and returns `note` unchanged - per feedback: "If the structure of
  the current chord is such that a tone is not possible it will move a semi tone. If a
  semi tone is not possible it will repeat the first note." `~chordSemitoneStep`
  (1/3rd) is simpler and, per feedback correcting an earlier misreading of this same
  instruction, deliberately does NOT try a tone first: it only ever attempts a
  SEMITONE in `dir`, falling straight back to repeating `note` if even that isn't a
  chord tone - "it should play the first note, go up a semitone, then another
  semitone," not a tone followed by a semitone. `~buildMonoTrackPattern`
  (`CT8tracks.scd`) picks `dir` itself and decides how many times to call the
  appropriate helper per split: for 1/8th (`~chordStepTone`), a fixed `1`/`-1` for
  Up/Down or a fresh `[1, -1].choose` per split pair for Ran, called once to get the
  pair's second note; for 1/3rd (`~chordSemitoneStep`), two calls chained (Up: `1`
  then `1` again from the result; Down: `-1` then `-1` again; Lop: `1` then `-1`) to
  get the triplet's second and third notes, while 1/3rd's own Repeat skips both
  helpers entirely and just reuses the first note for all three. Every other Pit
  Pat/Dur Pat combination leaves every note of a split identical, as before.
  `~currentChord` is the one shared "current chord" global. Read LIVE, not
  snapshotted into a local var, by `~buildPolyPattern`
  (`HT1`, `CT8tracks.scd`); `~buildMonoTrackPattern` (`BT1`/`BT2`/`MT1`/`MT2`) also reads it, for
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
  after `CT8guiClock.scd` and before `CT8tracks.scd`, since `~buildPolyPattern`/
  `~buildMonoTrackPattern` need `~chords`/`~currentChord`/`~chordNoteInRange` to already
  exist (though only at the point their builder is actually *called*, not at file-load
  time, so the ordering constraint is looser than it looks).

- **`CT8synths.scd`** — owns everything sound-*generating*: SynthDefs (`\plucking`,
  `\hat`, `\baseD`, `\cym`, `\fm`, `\ELIreverb`, `\drone`/`\lead`/`\seq`/`\noise`/`\rumble`/
  `\kick`/
  `\droneChord`/`\shimmerPad`/`\noiseCarrier`/`\rumbleCarrier`/`\fxPulse`/
  `\allpassReverb` - incorporated from the user's Sound Lab
  file; every one but `\droneChord`/`\shimmerPad` is still only auditioned via
  `CT8guiSynthLab.scd`, not used by any
  track. `\rumble` (the user's own SynthDef, brought in directly) is a 20-voice textural
  drone - 5 detuned saws plus pink noise per voice, each independently bandpass-swept,
  wave-folded, and spread across a slowly moving stereo field - checked and fixed per
  feedback ("check it out, fix the output"): `{...} ! size` (4 places) duplicated the
  UNEVALUATED function `size` times rather than calling it `size` times (the exact same
  bug already found and fixed in `\shimmerPad`, above - `\drone`'s own near-identical
  20-voice design already uses `Array.fill` for exactly this reason), so every one of
  the 20 voices was hearing the SAME random saw mix, the SAME noise signal, and the SAME
  base pan position, not 20 independent ones - fixed by switching all four to
  `Array.fill(size, {...})`. Also gained the standard `wet`/`level`/`auxBusA`-`auxAmtB`
  tail (`~allpassWash`/`~auxSend`, this file's own bullet) it was missing entirely, and
  added to the Synth Lab (`CT8guiSynthLab.scd`) with every param exposed - its own `out`
  arg needed no `\labRumble` variant, same as `\baseD`. `detune` is declared as an arg
  but never actually read anywhere in the body - flagged rather than silently wired in,
  since how it should affect the saw spread is a creative call, not an obvious bug fix;
  it's still exposed as a Synth Lab slider (per feedback, every param) but currently has
  no audible effect. `amp` default dropped *0.25 (`0.1` -> `0.025`) per feedback
  ("rumble same story *.25") - `\rumbleCarrier` (FXT1/FXT2's own bullet, `CT8tracks.scd`)
  has no `amp` arg of its own, so the same proportional cut goes directly into its own
  signal chain instead (`* 0.25` right before its own `Out.ar`). `\lead`/`\seq`'s own `freq` arg is a MIDI note number now, not Hz (default
  `69`/`76` - the nearest integer MIDI note to each one's old literal Hz default,
  `440`/`660`) - same "plain control arg, `.midicps`'d inside the body" pattern as
  `\droneChord`'s own `note1`-`note4`, below, so the Synth Lab's `\midi` slider curve
  (integer-rounded, 0 decimals) means something sensible for them too, per feedback
  ("put frequency to midi" - both already had every one of their other params exposed
  in the Synth Lab already; `\noise` has no `freq` arg at all, so nothing to convert
  there). `\lead`'s own `sharpness` calculation used to compute `freq.cpsmidi` (Hz back
  to MIDI) - now simplified away, since `freq` already IS the MIDI value it used to
  convert TO. `\lead`'s `freq` is clamped to `[30, 99]` (both internally,
  `freq.clip(30, 99)`, and in the Synth Lab's own slider range, which can no longer
  produce an out-of-range value in the first place) - per feedback ("lead needs to
  limit freq to never go below 30 or above 99"). `\lead` also gained a real `rel`
  control arg (its overall envelope's release time) - per feedback ("added a release
  variable rel to lead, can you please see it gets into synthlab") - replacing a
  hardcoded local var of the same name; that envelope's own release segment is curve
  `-4` now (was unspecified, i.e. linear) for a gradual decay, per feedback ("i would
  like the release for the overall envelope to be gradual") - not the literal `\exp`
  curve type, which is degenerate for a segment ending at 0 (holds at its start level
  until the very last instant, then drops instantly - a different failure mode than
  `\exp`'s own NaN-at-a-zero-start bug found earlier on `\droneChord`/`\shimmerPad`,
  but still wrong); `-4` is this project's own established, safe way to get a gradual
  decay on a segment touching zero (same curve `\shimmerPad`/`\kick` use).
  `\droneChord` (four simultaneous MIDI notes, `note1`-`note4`, eight sine
  oscillators per note, each detuned in cents: a static per-oscillator offset,
  `Rand(-1, 1) * detune` (`detune` is now a plain +/- cents amount, default 10 - a later
  hand-edit's redesign; it used to be a 0-1 normalized spread instead, `1` fully in tune,
  `0` up to +/- a semitone), plus a slow `LFNoise2`-driven wobble on top
  (`driftRate`/`driftDepth`, in Hz/cents - new in that same edit), summed in cents and
  converted to a frequency ratio via `2 ** (cents / 1200)`) is one of HT1/HT2's own two
  selectable Instruments now (alongside `\shimmerPad` - `\fm`/`\plucking` dropped as
  choices for these two specifically, per feedback restricting them to instruments that
  manage a chord as one voicing - see `~buildPolyPattern`'s own bullet, `CT8tracks.scd`,
  for the full redesign). `note1`-`note4` are plain control args, not read from
  `~currentChord` inside the SynthDef body - a UGen graph function runs once in sclang,
  at `.add` time, so a direct `~currentChord` reference in there would freeze whatever
  chord was current at THAT moment forever, never updating per note; `~buildPolyPattern`
  is what reads `~currentChord` live and feeds it in as these four args instead, fresh
  every trigger. `amp`/`attack`/`sustain`/`release` defaults were tuned per feedback
  across three passes (`attack`/`sustain`/`release` to 0.012/0.12/5 - was "very soft and
  slow" before; `amp` raised three times, 0.2 -> 0.4 -> 0.8 -> 1.5, still "too low"
  each time before that) - `attack`/`sustain`/`release` are themselves now fed live per chord by
  `~buildPolyPattern`'s own per-chord envelope calculation for HT1/HT2 (see that
  bullet), so these SynthDef-level defaults only actually apply when something else
  plays `\droneChord` directly (the Synth Lab). The envelope's own curve changed from
  `\sine` to a numeric `-4` (`Env.linen`'s own curve arg) to approximate that redesign's
  "the curve should be exponential" - NOT the literal `\exp` curve type, which a first
  pass used and which turned out to silence everything: `\exp`'s curve formula divides
  by the segment's own start level, and this envelope's attack segment starts at 0,
  so every note produced NaN that poisoned the shared hardware output bus every other
  track also sums into (per feedback: "everything works until i try to play a
  dronechord - then all sound stops"). `-4` is SuperCollider's own safe
  exponential-ish shape for envelopes that touch 0 - the same reason `Env.perc`'s own
  default curve is `-4`, not `\exp`. `wet`/`level` are its own tiny
  built-in `~allpassWash` tail, same convention as every other instrument's, defaulting
  to a no-op like always (`level`'s own default is `2` now, from the same hand-edit as
  the detune redesign). `\shimmerPad` (the user's own SynthDef, brought in and then
  reworked here) is HT1/HT2's other selectable Instrument -
  a 5-voice `DynKlank` resonator bank (one resonance per chord tone) excited by
  `PinkNoise`, each voice's own small Hz-domain frequency jitter, ring/decay time, and
  `LFNoise2`-driven amplitude wobble independently randomized. `note1`-`note5` are
  plain control args, fed live from `~currentChord` by `~buildPolyPattern` exactly like
  `\droneChord`'s own `note1`-`note4` - the original version read a hardcoded `myChord`
  array directly inside the SynthDef body instead, the same frozen-forever mistake
  `\droneChord` made before its own fix. The original also had several further bugs,
  all fixed in the same pass: `{...}.dup(numvoices)` duplicates the UNEVALUATED
  function `numvoices` times, not `numvoices` independent results, so `.midicps`/`+`
  ended up being called on an array of `Function`s rather than numbers - replaced with
  `Array.fill(numvoices, {...})`, which actually calls the block once per voice;
  `DynKlank`'s input argument was a typo (`ssig`, undeclared) instead of `sig`; `wet`/
  `level` were used but never declared as args; and two separate `Out.ar(out, ...)`
  calls summed together on the same bus rather than one replacing the other, collapsed
  into one. `atk`/`sus`/`rel` used to be hardcoded local vars (`2.0`/`1.0`/`5.0`) inside
  the SynthDef body; now real control args with those same defaults, same reason as
  `\droneChord`'s own `attack`/`sustain`/`release` above - `~buildPolyPattern` feeds
  them live per chord for HT1/HT2. The envelope's own curve changed from
  `[\sin, \lin, -4]` to `[-4, -4, -4]` to match "the curve should be exponential" -
  same fix as `\droneChord`'s own curve, above, and for the same reason: this
  envelope's attack segment starts at 0, so the literal `\exp` curve type a first pass
  used produced NaN there (dividing by that 0 start level), silencing everything, not
  just this synth, once it hit the shared output bus. Every other random element
  (per-voice jitter/ring time/`LFNoise2` rate) was
  also switched from plain-language methods (`.rand2`/`exprand`/`.choose`) to UGen-rate
  ones (`Rand`/`ExpRand`) - the plain-language ones only ever evaluate once, in sclang,
  at `.add` time (the same freezing issue as a direct `~currentChord` read, just easier
  to miss), so the shimmer texture would otherwise have been fixed forever rather than
  re-rolling fresh each time a new note plays. The original's own per-voice octave
  randomization (`[-12, 0, 12].choose`) was dropped rather than fixed in place, since
  `~chordNoteInRange` (via `~buildPolyPattern`) already picks a random octave within
  HT1's own Pitch range per note - stacking another independent octave shift inside the
  SynthDef on top of that could push a note back outside that range. The legacy/unused
  `\bassDrum`/`\shortWhistle`/`\clockVerb` that used to live here too have been deleted
  outright, not just left unused, since nothing referenced them), `~allpassWash` (a plain
  helper function, not a SynthDef - a chain of 10 `AllpassN` filters crossfaded against
  the dry signal by `wet` and scaled by `level`, same algorithm `\allpassReverb` itself
  uses but inline rather than reading from a bus; `level` defaults to 1 here, not
  `\allpassReverb`'s own 0.6, so `wet=0, level=1` is truly a no-op), the reverb's own
  live-adjustable `~reverbDec`/`~reverbLpf`/`~reverbMix` (for `~clockRev`, one
  long-running Synth rather than a per-note one), and `~auxSend` (another plain helper,
  same idea as `~allpassWash` - not a SynthDef) - the per-SynthDef half of the "mixer
  phase" aux-send system, per feedback: writes a copy of this synth's own finished
  output, scaled by `amtA`/`amtB`, to two destination buses (`busA`/`busB`), in addition
  to its normal `Out.ar(out, sig)` - a no-op by multiplication wherever a track's sends
  are still at their default 0, same "silent unless deliberately raised" convention as
  `~allpassWash`. `~auxEffectNames`/`~auxEffectBuses` are the actual effects registry -
  two parallel arrays (same convention `CT8guiSynthLab.scd`'s own `names`/`synthNames`
  already use), built inside `~installSynthDefs` itself (not at this file's own top
  level) because effect 0, "ELI Reverb," reuses `~revBus` directly - the exact same bus
  `\fm`/`\plucking`'s own `\fx` send already reaches, rather than standing up a second,
  redundant reverb instance - which doesn't exist until `CT8main.scd`'s boot sequence
  creates it, right before `~installSynthDefs` is first called. Adding a second effect
  (a bandpass filter, an echo - both planned, per feedback) later is just appending one
  more name and one more bus/Synth here, not a redesign. Every SynthDef a live track can
  actually select now takes `auxBusA`/`auxAmtA`/`auxBusB`/`auxAmtB` args and calls
  `~auxSend` on its own finished (post-`~allpassWash`) signal, right before its own
  final `Out.ar` - `\plucking`/`\hat`/`\cym`/`\baseD`/`\fm`/`\kick`/`\droneChord`/
  `\shimmerPad`, i.e. every instrument currently reachable from any track's own
  Instrument menu; `\drone`/`\lead`/`\seq`/`\noise` (Synth-Lab-only, not used by any
  track yet) don't need it. `\hat`/`\cym`/`\baseD`/`\kick`/`\fm`/
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
  what `BT1`/`BT2`'s own Wet/Level sliders (Mono Track config, `CT8tracks.scd`) need;
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
  shared table (BT1/BT2 read theirs from the generic Mono Track config instead, same
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
  rebuild needed), the parallel Mono Track config for `BT1`-`BT2` (`~monoSource`/
  `~monoInstrument`/`~monoPattern`/`~monoPitchMode`/`~monoVolumeMode`/
  `~monoVolumeLevels`/`~monoWet`/`~monoLevel`/`~monoSplitPercent` - same shape and same
  live-`CT8guiPercGenerator.scd`-set/`?`-guarded-default convention as percussion's, just
  a shorter list since bass has fewer pitch modes, no per-instrument pitch-arg-name
  dispatch to carry, and no `~bassBasePitch` of its own at all - pitch reads the shared
  `~currentRange[name]`, `CT8harmonySelect.scd`, instead - see MONO TRACK CONFIG's
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
  `BT2` mirror that exactly via their own shared builder, `~buildMonoTrackPattern.(name)`,
  reading the Mono Track config instead.

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

Every track starts disabled on every run now, per feedback - first "set things to start
with all tracks off," then, once it turned out that alone didn't actually hold
(`~trackEnabled` is an interpreter global, so a GUI click earlier in the same sclang
session - or an earlier run that session - survives a later `CT8main.scd` re-evaluation
by design, the same `?`-based convention every other per-track setting in this project
deliberately uses so GUI tuning isn't lost on a hot reload), "i would like all tracks to
start off. no matter what the last thing i did was!" `CT8tracks.scd`'s own
`~trackEnabled[name] = ~trackEnabled[name] ? false` guard (TRACK REGISTRY block) only
ever fills in a default the FIRST time a track's entry is set, so it's not what actually
guarantees this - `CT8main.scd`'s own RUNTIME PARAMETERS section does, with an
UNCONDITIONAL `~trackNames.do { |name| ~trackEnabled[name] = false }` that overwrites
every entry on every run regardless of GUI state, replacing both the old default-on
guard (`PT1`/`PT2`/`PT3`/`MT1` used to default on this way) and the old separate
`HT1`/`MT1`/`BT1`/`MT2` force-on block `CT8main.scd` used to run every time - for every
one of the 13
planned tracks (4 percussion `PT1-4`, 2 bass `BT1-2`, 2 harmony `HT1-2`, 2 fx
`FXT1-2`, 4 melody `MT1-4`) for a planned generative "Daily Piece" mode uniformly. The same section also
unconditionally resets every `~copyGuiTracks` track's `~copyPlaying`/
`~copyPlayStartArmed`/`~copyStopRequested`/`~copyPlayBuffer`/`~copyPlayIdx` (Track Copy,
below) for the identical reason - those are `?`-guarded in `CT8tracks.scd`'s own TRACK
COPY section, so without this a track left mid-playback (or mid-arming) from an
earlier run this same sclang session would otherwise keep looping its OLD copied
buffer on a fresh run too, completely bypassing its own current Pit Pat/Dur Pat
settings. Every track that HAS a
real builder can still be switched on by hand, either in the Percussion + Bass Generator
window (`PT1`-`4`/`BT1`-`2`) or the Harmony + Melody Generator/Clock Toy Adjust windows
(everything else) - see each one's own bullet, above, for exactly where its on/off button
lives. Per feedback ("I am reconsidering how I think of
these tracks... BT1/BT2/MT1/MT2 will be structured the same way"), `BT1`/`BT2`/`MT1`/
`MT2` are no longer thought of as separate "bass" and "melody" track families - they're
the four "Note" tracks (one of the project's three track families by now - Perc/Note/
Harmony, named `perc`/`mono`/`poly` in code for how many notes each ever sounds at
once), sharing one structure, one builder (`~buildMonoTrackPattern.(name)`), and one set
of config globals (`~monoX[name]`, `CT8tracks.scd`'s MONO TRACK CONFIG section -
renamed from `~bassX`/BASS GENERATOR CONFIG by this same reconception), differing only
in which options each one is currently set to - `MT1`/`MT2` used to have their own
bespoke builder (`~buildMelodyPattern`, with
hand-tuned FM voicing, now gone entirely) before this change. `PT4`, `BT2`, and `HT1`/
`HT2` (both chord-pad harmony tracks, restricted to `\droneChord`/`\shimmerPad`) also
have real builders (`PT4` shares `~buildPercPattern`; `BT2` shares
`~buildMonoTrackPattern`; `HT1`/`HT2` share their own `~buildPolyPattern` - `HT2` newly
registered, per feedback) and are fully
playable - just disabled by default like every other track now (see this section's own
opening paragraph, above) until toggled on in the Percussion + Bass Generator window
(`PT4`/`BT2`, beside each one's name) or the Harmony + Melody Generator/Clock Toy
Adjust windows (`HT1`/`HT2`). `FXT1`/`FXT2` (the new "fx" family, replacing `HT3`/
`HT4` entirely - see `~buildFxPattern`'s own bullet, above) ALSO have a real builder
and are fully playable the same way, toggled on in the Harmony + Melody Generator
window beside their own name; `MT3`/`MT4` are the only ones still registered but inert
(no builder exists
for them
yet). See the
TRACK REGISTRY block in `CT8tracks.scd`:
- **`~trackNames`** — all 13 track name symbols.
- **`~trackPatterns[name]`** / **`~trackPlayers[name]`** / **`~trackEnabled[name]`** — that
  track's built Pbind, its playing `EventStreamPlayer`, and whether the user wants its
  sound playing, each a `name -> value` Event rather than one-off globals per track.
- **`~syncTrackPlayer.(name)`** — stops a track's current player, then restarts it if
  `~trackEnabled[name]` and a pattern exist; used for any future per-track on/off UI.
- **`~trackBuilders[name]`** — the function that (re)builds `~trackPatterns[name]`;
  currently `PT1`/`PT2`/`PT3`/`PT4`/`BT1`/`BT2`/`MT1`/`MT2`/`HT1`/`HT2`/`FXT1`/`FXT2`
  have one
  registered. `PT1`-`PT4` each get a small wrapper closure (`{ ~buildPercPattern.(\PT1) }`, etc.)
  around the one shared `~buildPercPattern` function; `BT1`/`BT2`/`MT1`/`MT2` all mirror
  that with their own shared `~buildMonoTrackPattern` (the four Note tracks -
  see the paragraph above); `HT1`/`HT2` mirror that too, with their own shared
  `~buildPolyPattern` (`{ ~buildPolyPattern.(\HT1) }`/`{ ~buildPolyPattern.(\HT2) }`);
  `FXT1`/`FXT2` (replacing `HT3`/`HT4` entirely, not a mere rename - see
  `~buildFxPattern`'s own bullet, above) mirror that too, with their own shared
  `~buildFxPattern`. Registering a builder
  for a new track name is the only step needed to bring it under the existing
  `~setStartPbinds`/`~stopPbinds`/`~updatePbinds`/`~restartPbinds` machinery, which all
  loop generically over `~trackNames` rather than hardcoding specific tracks.

**AUX SENDS ("mixer phase")** — per feedback, every track in every family (keyed by
plain track name, not living inside any one family's own `~percX`/`~monoX`/`~polyX`
config, since all four families share this identically) now has two independently
assignable aux sends, Send A and Send B - the two previously-unused leftPane sliders
every track block already had. `~sendAEffect[name]`/`~sendBEffect[name]` are indices
into `~auxEffectNames`/`~auxEffectBuses` (`CT8synths.scd`'s own bullet has the
registry side - "ELI Reverb" is the only entry so far), each with its own target-effect
`PopUpMenu` in every track's block (`CT8guiPercGenerator.scd`/
`CT8guiHarmonyMelodyGenerator.scd`, one new row per block); `~sendAAmt[name]`/
`~sendBAmt[name]` are the actual 0-1 send amount, each its own leftPane slider (now
wired - the labels changed from "Dry"/"Rev" to "SdA"/"SdB" to match), defaulting to 0
("no-op until deliberately raised," same convention `~percWet[name]`/`~percLevel[name]`
already use). `~auxSendPbindArgs.(name)` is the one shared helper every builder in this
file (`~buildPercPattern`/`~buildMonoTrackPattern`/all three of `~buildPolyPattern`'s
branches) appends (via `++`) to its own Pbind argument array - four extra keys
(`\auxBusA`/`\auxAmtA`/`\auxBusB`/`\auxAmtB`), each a `Pfunc` (same reasoning as `\fm`'s
own `\fx` key - a live `Bus` reference sitting directly in a Pbind pair is suspect) read
fresh every event, so dragging a Send slider or re-assigning its target effect takes
effect immediately, no rebuild needed, exactly like Wet/Level. HT1's own Send A/Send B
are real and working even though that window's separate Mix/Vol controls still aren't
("not yet wired to playback") - aux sends are keyed by track name, not by whether
anything else in that section has been connected to actual playback yet.

**SYNTH LAB LIVE OVERRIDES** — per feedback ("I need a way to tune the presets so
lets connect the lab to the running synths"): `~labLiveOverrides[instrumentSym]` is an
Event of `{param: value}` for whichever ONE instrument is currently selected in the
Synth Lab (`CT8guiSynthLab.scd`'s own `menu.action` populates it fresh, clearing every
OTHER instrument's entry at the same time - the intended workflow is "run only one
track with that synth in it, tune it live," not several at once). Deliberately
excludes `\wet`/`\level` and any `\noteN` key, since those already have their own,
separate live controls this isn't meant to second-guess.
`~labOverrideArgs.(instrumentSym)` is the shared helper every builder appends the same
way `~auxSendPbindArgs` is - a flat array of `[key, Pfunc {...}, ...]` pairs, one per
currently-live-tuned param, read fresh every event like every other `Pfunc`-driven
control here. The SET of keys is only resolved at BUILD time, same as everything else a
Pbind's own argument array decides once - a param the Synth Lab hasn't started tracking
yet for an instrument won't appear on a live track until that track's next rebuild,
same "structure fixed at rebuild, values can be live" rule the rest of this file
already follows.

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
those tracks are enabled, built, or even exist. `HT1`/`HT2`/`MT1` all read the one
shared `~currentChord` global (`CT8harmonySelect.scd`)
live or once-per-rebuild respectively - see each one's own paragraph for which.

`HT1`/`HT2` are "going to change the rules," per feedback - no longer HT1's old bespoke
`\fm`-chord builder, now one shared, parameterized `~buildPolyPattern.(name)`, giving
`HT2` a real builder for the first time (`HT3`/`HT4` are explicitly untouched - "should
be ignored for now" - still no builder, still the original skeleton). Restricted to the
two instruments that manage a chord as one voicing - `\droneChord`/`\shimmerPad`
(`~polyInstrument[name]`) - `\fm`'s own "chord" was really 4 independently-triggered
Synths via array expansion and `\plucking` has no chord concept at all, so neither fits
here any more. `~polySource[name]` (Row/Col) is unchanged, feeding `events`/`startRole`
exactly like `PT1`-`4`'s own `~buildPercPattern`. Dur Pat (`~polyPattern[name]`) narrows
to exactly three: `\firstBeat` (one trigger per bar, beat 0), `\halfway` (TWO triggers
per bar - beat 0 AND beat `(events.size / 2).floor` - corrected per feedback from an
earlier version that fired only at the halfway point alone, once a bar, which just
sounded like an offset `\firstBeat` rather than "twice a bar"), `\startOnly` (one
trigger per row/column span). Each trigger's `\dur` (the gap to the NEXT trigger, in
beats) is the same `nextIdx - idx` technique every other builder in this file already
uses to compute a span, generalized to wrap the LAST trigger to `events.size +
baseSlotIdx[0]` rather than just `events.size` - the two only coincide when the
pattern's first trigger is at index 0, true for all three of these now (`\halfway`'s
own first trigger is beat 0 too, now that it fires there as well). Pit Pat
(`~polyPitchMode[name]`) narrows to `\fixed`/`\random`
(unchanged meaning - an independently-random, sorted voicing of `~chordNoteInRange`
picks, 4 notes for `\droneChord` or 5 for `\shimmerPad`, within `~currentRange[name]`)
plus two new ones, `\rising`/`\falling`: per feedback, these don't re-pick a fresh
voicing each trigger the way Fixed/Random do - they EVOLVE the existing one, dropping
the lowest (Rising) or highest (Falling) note and adding a new one a chord
tone-or-semitone step beyond the OTHER end (`~chordStepTone`, `CT8harmonySelect.scd` -
the same tone-else-semitone-else-repeat fallback the mono tracks' own Arp sub-variants
already use), reseeding a fresh random voicing once stepping further would leave
`~currentRange[name]` - Rising wraps at the top, Falling at the bottom, each at its own
end rather than a shared boundary. `~makeChordVoiceGen` (`CT8harmonySelect.scd`) is the
stateful generator behind this, one fresh instance per rebuild like every other
Rising/Falling generator in this project; a `Pfunc` on `\note1` alone calls it (or the
plain `~chordNoteInRange` picker for Fixed/Random) once per trigger and caches the
result, with `\note2` onward just indexing into that cached array - safe because Pbind
evaluates one event's keys in the order they're given, so `\note1`'s Pfunc always runs
before `\note2`'s for the same event. Accents (Volume) is gone entirely, per feedback -
no `\amp` key at all, so every chord just plays at its instrument's own SynthDef-default
amp. `\wet`/`\level` (`Pfunc { ~polyWet[name] }`/`Pfunc { ~polyLevel[name] }`) WERE
missing from this Pbind entirely until found per feedback ("shimmer at vol 0 is still
loud") - the Mix/Vol sliders (`CT8guiHarmonyMelodyGenerator.scd`'s own leftPane) had
been writing `~polyWet`/`~polyLevel` since the HT1/HT2 redesign without anything ever
reading them back, so those two sliders did literally nothing to the actual sound the
whole time - now live via `Pfunc`, same convention as every other family's own Mix/Vol.
`\shimmerPad`'s own `amp` default also dropped *0.25 (`0.125` -> `0.03125`) - still too
loud even accounting for the above - matching the same cut applied to `\rumble`/
`\rumbleCarrier` (`CT8synths.scd`'s own bullets, "rumble same story *.25").

THE BIG CHANGE, per feedback: the envelope is recalculated fresh for every chord played,
from the beats-until-the-next-chord `\dur` value above, plus 2 beats (deliberately
longer than the gap itself, so consecutive chords' envelopes always overlap somewhat),
converted to real seconds via `t.tempo` (both SynthDefs' envelopes are wall-clock, same
conversion `\fm`'s own old `\rel` already used). attack/sustain/release split
15%/45%/40% of that total (sums to 100% - feedback corrected the originally-stated
15/45/15, where release was meant to be 40% not 15%) - `\droneChord` takes this as
`\attack`/`\sustain`/`\release`, `\shimmerPad` as `\atk`/`\sus`/`\rel` (its own
hardcoded-local-vars-turned-control-args, `CT8synths.scd`'s own bullet); both
SynthDefs' own envelope curve is a numeric `-4` now too, to match ("the curve should
be exponential" - `-4`, not the literal `\exp` curve type, which divides by a
segment's start level and produced NaN on these envelopes' 0-start attack segment,
silencing all output, not just these two synths' own sound - see each SynthDef's own
bullet, `CT8synths.scd`, for the fix). These three keys are excluded from the Synth
Lab's own live-override
tracking for `\droneChord`/`\shimmerPad` specifically (`CT8guiSynthLab.scd`'s
`populateLiveOverrides`), for the same reason `\wet`/`\level`/`noteN` already are -
they now have their own separate live control (this per-chord calculation), so the lab's
own sliders shouldn't fight it for whichever of HT1/HT2 is currently using that
instrument; sliding them in the lab still works for standalone auditioning there, same
as always.

A Pbind's own `\dur` sequence only encodes the GAP between triggers, not which
absolute beat playback actually started on - a real problem for an EARLIER version of
`\halfway` that fired only at the halfway point alone (one trigger, sitting mid-bar,
unlike every other pattern's own first trigger at beat 0): without knowing which beat
the stream started on, that one trigger just fired at whatever beat playback happened
to begin (typically bar-start, indistinguishable from `\firstBeat`) - found per
feedback ("i don't hear droneChord change at half way - it only seems to change at
first of beat... confirmed by postln"). `leadIn`/`isLeadInEvent` (a one-off rest
inserted before the repeating cycle, for any pattern whose first trigger isn't at beat
0) fixed that version - now moot since `\halfway` was changed again, per further
feedback, to fire at beat 0 as well (see Dur Pat's own paragraph, above, for "twice a
bar"), but kept in the code as general, dormant machinery rather than ripped out, in
case a future Dur Pat choice ever starts mid-bar again. While adding the `\type` key
this needed, also picked up a missing `~trackEnabled[name]` check: HT1/HT2's own on/off
toggle had never actually silenced them before this fix, since no `\type` key existed
in this builder at all until now. The temporary debugging `postln` from that same
investigation (which chord-pad notes were resolving to, each trigger) has since been
removed again, per feedback ("turn off the chord postln").

`HT3`/`HT4` are GONE from `~trackNames` entirely now - per feedback ("going to take
HT3 and HT4 and rename them FXT1 and FXT2"), those two slots are `FXT1`/`FXT2` instead,
a wholly new "fx" track family (not a mere rename). Each FX track is actually TWO
Synths working together, per feedback ("treating the pulse as a separate event. the
bar long note gets triggered, but is sent to the input of a second event that is the
pulse envelope") - this replaced an EARLIER, single-SynthDef design (one Synth per bar,
masterEnv+burstEnv ADDED together inside it) that turned out to always leave an
audible floor (masterEnv's own constant hold level) underneath the pulse, making it
barely noticeable regardless of Pulse % - confirmed per feedback ("i do not hear a
pulse in rumble or in noise... if dur pat is first beat only, should i not just hear a
burst of noise and then almost nothing till the next bar"), which is exactly what the
ADDITIVE design could never produce (there was always a floor, never true silence).

`~buildFxPattern.(name)` (`CT8tracks.scd`) now builds TWO Pbinds running concurrently
as one `Ppar` (a `Ppar` is just another Pattern, so this needed no changes to the
surrounding `~trackPatterns[name]`/`.play(t, quant:1)`/`~syncTrackPlayer` machinery
every other track family already uses): a "carrier" pattern fires once per bar (`\dur,
events.size`, same bar-length-in-beats every other single-trigger-per-bar pattern in
this file uses), playing `\noiseCarrier`/`\rumbleCarrier` (`CT8synths.scd`'s own
bullets) into this track's own PRIVATE audio bus (`~fxCarrierBus[name]`) rather than
hardware output - it just needs to keep sounding continuously for the bar, no
Dur-Pat-driven pulsing baked in at all. A separate "pulse" pattern fires one event PER
PULSE (however many times a bar, per `~fxPattern[name]`'s own Dur Pat choice), each a
short-lived `\fxPulse` synth (ONE shared SynthDef, reused regardless of which carrier
is on the bus, since shaping a signal doesn't care what generated it) that reads FROM
that same bus and is the ONLY thing that actually reaches real output - between
pulses, nothing else is writing to `out` for this track, so it's genuine silence, not
a quieter hum. `~fxCarrierBus[name]` (a private 2-channel audio `Bus`) and
`~fxSourceGroup[name]`/`~fxPulseGroup[name]` (persistent `Group`s, the pulse group
created immediately AFTER the source group via `Group.after` - so the carrier's own
node always executes before the pulse's, regardless of which actually got triggered
first that instant, guaranteeing the pulse always reads that block's freshly-written
carrier signal rather than stale/empty data) are each allocated once, lazily, and
reused across rebuilds - same "allocate once, keep forever" convention as every other
persistent server resource in this project (`~revBus`, Groups, etc.).

`~fxInstrument[name]` is `\rumble` or `\noise` (both default `\rumble` now - per
feedback, "to hard to hear with noise... lets do it with rumble") - `\seq`/`\lead` are
still a planned follow-up, each needing their own carrier SynthDef variant the way
`\noiseCarrier`/`\rumbleCarrier` wrap `\noise`/`\rumble`'s own sound; `~fxSynthNames`
maps the friendly menu symbol to the actual carrier SynthDef, same role
`CT8guiSynthLab.scd`'s own `synthNames` plays there. `~fxSource[name]` (`\row`/`\col`,
`FXT1` defaults `\row`, `FXT2` `\col`, same convention every other family's own Source
uses) feeds `events`/`startRole` exactly like `PT1`-`4`'s own `~buildPercPattern` -
only matters for `\startOnly`, below. `~fxPattern[name]` is all three
originally-planned choices, per feedback ("have the dur pat choices be first beat
only, first of row/col, every beat"): `\firstBeat` (one pulse per bar), `\startOnly`
(one pulse per row/column span - IRREGULAR, since different rows/columns have
different widths), or `\everyBeat` (one pulse per beat, uniform) - `pulseDurs` is the
actual list of per-pulse span lengths, IN BEATS, computed once per rebuild via the
exact same `nextIdx - idx` gap technique every other builder in this file already uses
(`\firstBeat` is one span, the whole bar; `\everyBeat` is one span, one beat, cycled
via `Pseq`'s own infinite repeat; `\startOnly` is one span PER ROW/COLUMN, each that
span's own real width) - since each pulse is now its OWN independent Pbind event (the
same multi-event-per-bar technique every other family's own builder already uses), an
irregular span is exactly as easy to schedule as a uniform one; no buffer or
demand-rate machinery needed at all. `~fxPulsePercent[name]` (0-100) is what fraction
of THIS SPECIFIC pulse's own span length its "on" portion occupies - `pulsedur`/
`releaseDur` are computed fresh per trigger (`ev[\dur]`, that event's own resolved
span length) rather than a bar-wide average, so the envelope shape is exact for every
individual pulse, not approximated. `~fxWet[name]`/`~fxLevel[name]` (the usual
`~allpassWash` tail, now living on `\fxPulse`, not the carrier - the reverb send
should colour the actual audible bursts, not a signal nothing ever hears on its own)
double as FXT1/FXT2's ONLY overall volume control. Deliberately does NOT splice in
`~labOverrideArgs` (unlike every other builder) - `\noiseCarrier`/`\rumbleCarrier`/
`\fxPulse` are different SynthDefs from the Synth Lab's own plain `\noise`/`\rumble`
entries, and `\noise`'s own `dur` key (seconds) would collide with Pbind's reserved
`\dur` (beats) if the Synth Lab ever live-tracked it, silently breaking this track's
own bar-length scheduling.

`\noiseCarrier`/`\rumbleCarrier` (`CT8synths.scd`) reuse `\noise`/`\rumble`'s own
sound-generating chains verbatim (`\rumbleCarrier` keeps `\rumble`'s own unrelated
per-voice envelope/texture shaping untouched - that's part of the texture itself) but
replace the old single-envelope/dual-envelope designs with just a simple fade-in/
fade-out for the whole bar (`masterDur` seconds, plus a fixed 1-second tail - "a bit
tacked on the end" - so the synth's own total lifetime is `0.1+masterDur+1`, freed via
`doneAction:2`) - it exists only to avoid a click at the bar's own start/end, since
it's `\fxPulse` alone that decides what's actually audible at any given moment, not a
held level the way the old `masterEnv` was. `\fxPulse` applies a plain attack/hold/
release envelope (`[0,1,1,0]` over `[0.01, pulsedur, releaseDur]`) to whatever it reads
off the bus and is the ONLY source of amplitude shaping left - no floor underneath it
at all, so between pulses this is genuine silence. All of these use curve `-4`
uniformly, per feedback - genuinely safe even on attack segments starting at 0, unlike
the literal `\exp` curve type (see `\droneChord`/`\shimmerPad`/`\lead`'s own bullets
for why that one isn't). `\rumbleCarrier` answers `\rumble`'s own hand-written comment
("needs envlope that kind of pulses based on start of row/col").

`MT1` used to mirror `HT1`'s structure from `~colPattern`/`\columnStart`
through its own bespoke builder, `~buildMelodyPattern` - that builder is gone now,
along with the whole idea of "melody tracks" as their own family; `MT1`/`MT2` are driven
by `~buildMonoTrackPattern` instead, exactly like `BT1`/`BT2` - see that paragraph,
below, for the shared Note track structure all four now have. Neither `HT1` nor
`MT1`/`MT2` advances the chord progression itself - see `~checkForNewChordBar`,
`CT8harmonySelect.scd`'s own bullet, for where that lives instead.

`BT1`/`BT2`/`MT1`/`MT2` are four interchangeable "Note tracks" now, per feedback
("I am reconsidering how I think of these tracks... BT1/BT2/MT1/MT2 will be structured
the same way... they differ only in the options they are currently set to") - sharing one
structure, driven by the Mono Track config exactly the way `PT1`-`PT4` are driven by
the Percussion Generator config (same single-source-scan/pre-resolve-the-bar technique),
through their own shared, parameterized builder, `~buildMonoTrackPattern.(name)`
(`CT8tracks.scd`) - replacing `BT1`'s old bespoke builder (a fixed `Ppar` of a row-start
AND a column-start sub-pattern running simultaneously, always both at once) and `MT1`'s
old bespoke one (`~buildMelodyPattern`, with hand-tuned FM voicing - gone entirely now),
and giving `BT2`/`MT2` real builders for the first time. `~monoX[name]` (MONO TRACK
CONFIG, `CT8tracks.scd`) was `~bassX[name]` until this same reconception renamed it,
per feedback - the TRACK names (`BT1`/`BT2`/`MT1`/`MT2`) stayed put, only the globals'
own names changed; `MT1`/`MT2`'s own
GUI blocks stay physically in the Harmony + Melody Generator window
(`CT8guiHarmonyMelodyGenerator.scd`, not `CT8guiPercGenerator.scd`), per feedback not to
change any layout, even though they read/write these same `~monoX[name]` globals, via
that window's own `makeMonoTrackSection` - a near-exact copy of
`CT8guiPercGenerator.scd`'s own `makeMonoTrackSection`. Each of the four instead picks
ONE scan via `~monoSource[name]` (`\row`/`\col`, same as `PT1`-`4`) - `BT1`/`MT1` default
to `\row`, `BT2`/`MT2` to `\col` (`MT1`/`MT2` used to default to a fixed `\col`-only scan,
back when they were "melody" tracks - per feedback, `MT1`/`MT2` now split `\row`/`\col`
the same way `BT1`/`BT2` do). `~monoInstrument[name]` picks `\fm` or `\plucking` (`BT1`
defaults `\fm`, `BT2`/`MT1`/`MT2` default differently) - both take a plain `\midinote`
key (no per-instrument pitch-arg-name dispatch needed, unlike `~buildPercPattern`'s
`pitchArgName` switch) and a plain `\amp` key (no amp-arg-name dispatch either).
`~monoPitchMode[name]` is Fixed (`~chordRootInRange` -
the chord's own root note, deterministic, not a random pick), Random (`~chordNoteInRange`
- any chord tone, any octave, re-picked per baseline slot), Rising
(`~makeRisingPitchGen` - starts at the same root `~chordRootInRange` would give, then
climbs `~scales[~chordSet]` one degree per baseline slot, not per row/column-start,
wrapping back to the root once the climb would exceed the range's high end, and
resetting fully only at the next bar - see that function's own bullet,
`CT8harmonySelect.scd`, for the exact rule), Falling (`~makeFallingPitchGen`/
`~chordTopInRange` - the mirror of Rising: starts at the TOP of the range instead and
descends, same reset/wrap rules otherwise), Looping (`~makeLoopingPitchGen` - starts
at the same root `~chordRootInRange` gives, picks a random direction once, then steps
like Rising/Falling do but REVERSES direction at whichever bound it reaches instead of
wrapping, bouncing between `lo` and `hi`), or one of Arp Rising/Arp Falling/Arp Looping
- the exact same three generator functions as their plain counterparts, just fed
`~chordArpIntervals.(~currentChord)` (each chord tone's offset from its own root, with
a 3-note chord's root appended an octave up so it arpeggiates as 4 tones - see
`~chordArpIntervals`'s own bullet, `CT8harmonySelect.scd`) in place of
`~scales[~chordSet]`, so an Arp mode climbs/descends/bounces through the current
chord's own tones rather than its parent scale's degrees. Each of the three Arp modes
further splits into its own family of sub-variants depending on this track's Dur Pat -
Up/Down/Ran (`\arpRisingUp`/`\arpRisingDown`/`\arpRisingRan`, etc. - 9 symbols total)
for the three 1/8th patterns, or Repeat/Up/Down/Lop (`\arpRising3rdRepeat`/
`\arpRising3rdUp`/`\arpRising3rdDown`/`\arpRising3rdLop`, etc. - 12 symbols total) for
the three 1/3rd patterns - see the Pitch menu's own bullet, `CT8guiPercGenerator.scd`,
and `~chordStepTone`/`~chordSemitoneStep`'s own bullet, `CT8harmonySelect.scd`, for how
each family changes
the note(s) after the first in its own kind of split - no separate `~bassBasePitch` any
more, every one of these base/Up/Down/Ran/Repeat/Lop modes (29 symbols in total across
all three families) shares
`~currentRange[name]` (`~monoRangeDefaults`, `CT8tracks.scd`: `BT1`/
`BT2` default to 12-59, "below middle C"; `MT1`/`MT2` keep their own higher historical
default, 60-96, even though all four are otherwise identical in structure now - nothing
about "Note track" forces every one of them into the same register), the same
global `HT1` reads live, just resolved once per rebuild here instead - so a mid-bar
chord change isn't heard on any of the four until their next rebuild, unlike `HT1`'s
live per-hit read. Per feedback, which split/merge group a hit falls under (the six
1/8th-1/3rd/4/3
families) doesn't yet change how Rising/Falling/Looping (plain or Arp) advances - every hit in one such
group still shares its one pitch/one step, same "same pitch throughout the
group" rule Fixed/Random already followed - pending a separate, later pass specifically
on that. `\fx`
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
`BT1`/`BT2`/`MT1`-`4` only (not `HT1`-`4`/`PT1`-`4` - the Note tracks are all single-
note-per-event, so a `(dur, midinote)` pair means the same thing on either side of a
copy; harmony plays chords and percussion's pitch is Hz, neither fits). The original
GUI-less pair, `~copyTStartRecord.(sourceName, beats)` (tapes that
track's actual sounding `(dur, midinote)` pairs for the next `beats` TempoClock beats
into `~copyBuffer` - only real `\note` hits, never rests - this feature doesn't try to
preserve a recording's silence, per feedback) and `~copyTStartPlayback.(destName)`
(splices that buffer into `destName` in place of its own normal pitch/duration - same
instrument/amp/wet/pan/everything else about it untouched - transposed by a whole
number of octaves first, per feedback: `~copyOctaveShiftFor.(note, range)` finds
the single octave shift that brings the buffer's own FIRST note nearest the CENTER of
`destName`'s own `~currentRange[destName]`, then `~copyTStartPlayback` applies that
SAME shift to every note in the buffer, preserving the recorded phrase's own internal
intervals exactly rather than distorting them by correcting each note individually -
deliberately not re-checking any of the OTHER notes against the range afterward, so a
phrase spanning more than an octave can still land partly outside it, per feedback
("ignore for the time being if the new playback goes out of range")), still exist
unchanged (aside from that transposition, which both the GUI path and a direct
`~copyTStartPlayback` call now share) and still callable by hand from the post
window, but now also
have a real GUI (`~copyGuiTracks`, i.e. `BT1`/`BT2`/`MT1`/`MT2` only - `MT3`/`MT4` stay
copy-eligible at the data-model level, per feedback they're just unused now) built on
top of them, in each of those four tracks' own blocks (the Percussion + Bass
Generator/Harmony + Melody Generator windows): ONE shared, dual-purpose button, a
Playback timing dropdown, and a Stop Playback button. The button reads "Copy Track"
(`~copyButtonLabelFor.(name)`) for whichever track either IS the current source or
could still become one (no completed recording exists yet at all), and "Play Copy"
for every OTHER track once a completed `~copyBuffer` actually exists to play - before
that, every track still reads "Copy Track," since nothing exists yet for anyone to
play. "Copy Track" claims the source role and turns the other three's labels to "Play
Copy" (`~copyTrackButtonPressed`); "Play Copy," per feedback correcting an earlier
one-step design ("change the name on the copy track button to 'play copy', when it is
clicked turn it orange, and wait for a selection from the choice of next bar, next
row, next beat... wait for the play back to start change the 'play copy' to green"),
just ARMS that track and waits (`~copyPlayButtonPressed`) - it's the SEPARATE Playback
dropdown choice, made afterward, that actually schedules the start
(`~copyPlaybackMenuAction`), not the button click itself. Several behaviors changed
for the GUI path specifically (direct `~copyTStartRecord`/`~copyTStartPlayback` calls
are untouched): recording always waits for the source's own next bar boundary before
it actually starts (never the instant you click), and always tapes exactly one bar;
playback is this two-step arm-then-choose flow, scheduled to start on the
destination's next bar, next row/col start, or next beat depending on which the
dropdown picks; and playback LOOPS the copied bar indefinitely once started, rather
than playing it through once - Stop Playback ends the loop, but only once the CURRENT
pass finishes, never mid-buffer, per feedback ("finishes the current loop and goes
back to what it was doing"). `~copySourceTrack` is the one `~copyGuiTracks` name
currently selected as the source (or `nil`) - `~copyTrackButtonPressed.(name)`
reassigns this on every click (even re-clicking the already-selected track, which just
re-arms a fresh recording) rather than each button tracking independent state, which
is what actually enforces "only one source at a time." `~copyArmedSource` is non-nil
from the click until the scheduled next-bar callback actually starts the tape - both
that waiting period and an in-progress recording display as the same orange "copying"
button color (`~copyButtonStateFor.(name)` - `\idle`/`\copying`/`\ready`, i.e.
grey/orange/green - checks `~copyButtonLabelFor` first to know which of the two roles'
own state to read); there's no separate visual for "waiting to start" vs. "actively
taping," nor for "waiting for a Playback choice" vs. "choice made, start scheduled but
not yet arrived" on the Play Copy side - each pair collapses to the same orange.
`~copyPlayStartArmed[name]` is what the "Play Copy" role's own orange/green state
reads, true from the button click all the way through until `~copyTStartPlayback`
actually fires. Both `~copyBeatsUntilNextBar` and `~copyBeatsUntilNextRowCol.(source)`
compute a one-shot delay in TempoClock beats from right now, scheduled via a single
`t.sched` call rather than any new persistent per-beat checker - `~copyBeatsUntilNextBar`
reuses `~chordBarBeatCount`/`~numBeats` (`CT8harmonySelect.scd`'s own bar-boundary
counter, already exactly the row-scan bar length every track shares) instead of
tracking a second, separate bar counter; `~copyBeatsUntilNextRowCol` finds the next
`\rowStart`/`\columnStart` index in `~rowPattern`/`~colPattern` after the current beat
position, wrapping to the following bar's first start if the current bar has none
left - each array index already IS a beat offset (one event per beat), so no `\dur`
summing is needed. `~copyPlaybackMenuAction.(destName, source, choice)` is the
Playback dropdown's own `.action_` - it only actually computes a delay and schedules
anything if `~copyPlayStartArmed[destName]` is ALREADY true (the button was clicked
first); picking a menu item before that just posts a warning, since there's nothing
yet to schedule a start for. `source` is that destination's own
`~monoSource[destName]` at the moment of selection, not re-read later, so the delay
computed then and whatever `~copyBeatsUntilNextRowCol` actually waits for always agree
even if Source changes again before the scheduled moment arrives.
`~copyStopPlaybackPressed.(name)` either raises `~copyStopRequested[name]` (if already
looping - checked only at the next loop-wrap, inside `~makeCopyAwarePair`, so the
current pass always finishes cleanly) or cancels a still-pending
`~copyPlayStartArmed[name]` outright (if the scheduled start hasn't fired yet, there's
no loop in progress to let finish).
`~refreshAllCopyButtons` calls every registered `~copyButtonRefreshers[name]` closure
(each track's own redraw function, set when its block is built) so a change to this
shared state redraws every track's widgets at once, even across the two different
windows/files BT1/BT2 and MT1/MT2 live in - the cross-window coordination this
feature needs, since clicking BT1's button must also visually reset MT1/MT2's
buttons. `~makeCopyAwarePair` is the shared mechanism every eligible track's
`\dur`/`\midinote` keys go through (all four of
`BT1`/`BT2`/`MT1`/`MT2` via their one shared `~buildMonoTrackPattern` now) instead of a
plain `Pseq`/`Pfunc` - each wraps a retained,
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
pattern once a stopped loop's current pass finishes always happens cleanly between
notes, never inside one.

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
