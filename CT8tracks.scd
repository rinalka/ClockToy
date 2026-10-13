// ============================================================================
// CT8tracks.scd
// CLOCKTOY - TRACK GENERATION AND PLAYBACK LIFECYCLE
// ============================================================================
//
// This file owns the musical-composition side of the project: the track
// registry (which tracks exist, whether each is enabled, what Pbind it's
// currently playing), the per-track builder functions that turn the clock
// scan's output (~rowPattern/~colPattern/~clockEvents/~columnEvents, from
// CT8guiClock.scd) into actual Pbinds - each track reading its own
// Percussion Generator config for pitch/volume rather than any shared
// per-synth table - and the start/stop/rebuild lifecycle CT8main.scd and
// the GUI windows call into.

// Requires CT8synths.scd (the SynthDefs themselves - \baseD/\cym/\hat/\kick/
// \fm/\plucking), CT8guiClock.scd (~rowPattern/~colPattern/~clockEvents/
// ~columnEvents), and CT8harmonySelect.scd (~chords/~chordNoteInRange - the
// shared "current chord" concept HT1 reads live every hit; BT1/BT2/MT1/MT2
// (the Note tracks) also read it, for their Random/Fixed/Rising pitch
// modes, but only once per rebuild rather than live - see the Mono Track
// config below) to already be
// loaded - CT8main.scd's ~loadAllCt8Files loads every file in the right
// order.

(

// ---------------------------------------------------------------------------
// PERCUSSION GENERATOR CONFIG (PT1-PT4)
// ---------------------------------------------------------------------------
// Set live by the "Percussion Generator" window (CT8guiPercGenerator.scd).
// Every one of PT1/PT2/PT3/PT4 is driven entirely by these per-track
// dictionaries, keyed by track name symbol - replaces PT1's old singular
// ~pt1* globals, PT2's old ~colStartSynth/~colCellSynth two-synth-role
// system, and PT3's old hand-tuned ~snareTemplate hit pattern:
//   ~percSource[name]     - \row (scans ~rowPattern/~clockEvents, start role
//     \rowStart) or \col (scans ~colPattern/~columnEvents, start role
//     \columnStart). Defaults preserve each track's historical identity:
//     PT1/PT3 default \row, PT2/PT4 default \col.
//   ~percInstrument[name] - which installed synth plays every note this
//     track makes. Currently \baseD, \cym, \hat, or \kick - all take a
//     Hz-based pitch arg (not a scale degree), which is why pitch below is
//     plain Hz too.
//   ~percPattern[name]    - which beats in that source actually get a hit.
//     All thirteen choices are one flat list in the Percussion Generator (no
//     mode-within-mode submenu) - the split/variant combinations used to be
//     a single \random8th/\random3rd choice plus a separate
//     ~percSplitVariant[name], but that hid five of the six actual
//     behaviors behind an extra menu, so each combination now gets its own
//     top-level entry instead. Every percent-driven entry's menu label ends
//     in "%" (the only ones the Percussion Generator shows its Percent box
//     for); the deterministic "(last of bar)"/"(last of row/col)" entries
//     don't, since there's no percent to set for those:
//     \firstBeat  - one hit per bar, at the very first beat.
//     \everyBeat  - one hit per beat, no skipping.
//     \startOnly  - one hit at every row/column-start (skips plain cells).
//     \random8thPercent/\random3rdPercent ("1/8th %"/"1/3 %") - every beat,
//       but ~percSplitPercent[name]% of them (chosen fresh each rebuild,
//       independently per beat) are replaced by a double hit/triplet - the
//       beat's own span split evenly in two/three, same pitch throughout.
//     \random8thLastBar/\random3rdLastBar - same double-hit/triplet split,
//       but deterministic: only the bar's very last beat, always, every
//       bar - no randomness, no percent.
//     \random8thLastRowCol/\random3rdLastRowCol - same split, deterministic,
//       but on the last beat of every row/column span instead - one split
//       per row/col, not just one per bar.
//     \random4to3Percent/\random4to3LastBar/\random4to3LastRowCol
//       ("4/3 %"/"4/3 (last of bar)"/"4/3 (last of row/col)") - the inverse
//       of the 1/8th/1/3 families: instead of expanding ONE beat into 2/3
//       sub-hits, these MERGE a run of 4 consecutive baseline beats into 3
//       equal-length hits spanning that same total time (same pitch
//       throughout the merged group, same "same pitch across the group"
//       convention the splits above already use). \random4to3Percent rolls
//       ~percSplitPercent[name]% per non-overlapping group of 4, scanning
//       from the bar's start; \random4to3LastBar merges only the bar's
//       final 4 beats, every bar; \random4to3LastRowCol merges the final 4
//       beats of every row/column span. A bar or span shorter than 4 beats
//       simply can't merge and is left as individual beats, unchanged -
//       expect this with \random4to3LastRowCol especially, since most
//       columns and many rows won't have 4 beats to begin with.
//     \randomSkip ("Skip %") - every beat, but ~percSplitPercent[name]% of
//       them (chosen fresh each rebuild) are silent - the beat's span is
//       unchanged, it just doesn't sound. Now shares ~percSplitPercent[name]
//       with the "%" split/merge patterns above (switching between any of
//       these keeps whichever percent was already set) - it used to be a
//       fixed, non-adjustable ~1/4.
//   ~percPitchMode[name] - how the pitch arg varies hit to hit.
//     ~percBasePitch[name] is [lo, hi] - one dual-handle RangeSlider in the
//     Percussion Generator window (CT8guiPercGenerator.scd), not a
//     mode-specific widget set any more:
//     \fixed  - always the range's high end (hi).
//     \rising - resets to lo at every start, then climbs toward hi in 8
//       fixed steps per hit after that (clipped at hi - see this function's
//       own basePitches comment for why 8 specifically).
//     \falling - Rising's mirror, per feedback: resets to hi at every
//       start, then steps DOWN toward lo in the same 8 fixed steps, but
//       WRAPS back to hi (not clamping) once it would go below lo - see
//       this function's own basePitches comment for the exact rule.
//     \looping - a third variant, per feedback: no chord root to start
//       from here (percussion has no chord concept), so it starts at the
//       midpoint of [lo, hi], picks a random direction (up or down) fresh
//       at every start, then steps in that direction in the same 8 fixed
//       steps - but REVERSES direction at whichever bound it reaches
//       instead of wrapping or clamping, bouncing back and forth - see
//       this function's own basePitches comment for the exact rule.
//     \random - anywhere in [lo, hi], chosen independently each hit - no
//       chord-aware selection yet, that's a planned future step (unlike
//       BT1/BT2's own Random pitch mode, which already is).
//   PITCH/VOLUME REWORK (planned, not started): both ~percPitchMode and
//   ~percVolumeMode above are considered placeholders, due to be
//   redesigned once the non-percussion tracks (HT1-4/MT1-4) get real
//   chord-based pitch - PT1-4 will likely end up picking from a small set
//   of hand-built "chords" per instrument rather than these three modes.
//   ~percVolumeMode[name] - how amp varies hit to hit (replaces the old
//     Synth Controls window's per-synth amp slider, now removed - see
//     CLAUDE.md). ~percVolumeLevels[name] is also [lo, hi] now (one
//     dual-handle RangeSlider):
//     \fixed     - always the range's high end (hi).
//     \alternate - alternates hi, lo every hit (high end first).
//   ~percWet[name]/~percLevel[name] - this track's instrument's own tiny
//     built-in reverb tail (the \wet/\level args every percussion SynthDef
//     - \baseD/\cym/\hat/\kick, see CT8synths.scd - now takes; ~allpassWash's own
//     dry/wet crossfade and output-level knobs - a straight AllpassN wash,
//     not FreeVerb, which was a mistake the first time this existed).
//     ~percWet defaults to 0 (fully dry) and ~percLevel to 1 (unity gain),
//     matching the SynthDef args' own defaults - this is a SEPARATE,
//     per-voice reverb from the shared ~clockRev/~revBus send every other
//     track uses; PT1-4 were never reaching ~clockRev anyway (\baseD/\cym/
//     \hat don't declare an \fx arg, so the \fx key ~buildPercPattern
//     passes them below is silently ignored - see its comment there), so
//     this is the only reverb these four tracks can actually have. Unlike
//     every other Percussion Generator control, a \wet/\level change takes
//     effect immediately, live, on the very next note - both are plain
//     Pfunc reads, not baked into the pre-resolved dur/pitch/amp arrays the
//     way ~percPattern/~percPitchMode/~percVolumeMode are, so neither needs
//     a rebuild or an Apply now click.


~percTrackNames = [\PT1, \PT2, \PT3, \PT4];
~percSource = ~percSource ? ();
~percInstrument = ~percInstrument ? ();
~percPattern = ~percPattern ? ();
~percPitchMode = ~percPitchMode ? ();
~percBasePitch = ~percBasePitch ? ();
~percVolumeMode = ~percVolumeMode ? ();
~percVolumeLevels = ~percVolumeLevels ? ();
~percWet = ~percWet ? ();
~percLevel = ~percLevel ? ();
~percSplitPercent = ~percSplitPercent ? ();
~percSourceDefaults = (PT1: \row, PT2: \col, PT3: \row, PT4: \col);
~percInstrumentDefaults = (PT1: \kick, PT2: \baseD, PT3: \hat, PT4: \cym);
// Each instrument's own default pitch-arg value (as a MIDI note now, not
// Hz - see ~percBasePitch's own comment just below) and amp. Keyed by
// instrument rather than
// by track so ~percBasePitch/~percVolumeLevels' defaults, below, stay
// correct even if ~percInstrumentDefaults is changed later.
// MIDI equivalents of each instrument's own SynthDef default Hz value
// (CT8synths.scd), rounded to the nearest note - baseD 55 Hz, cym 300 Hz,
// hat 4200 Hz, kick 50 Hz - preserving each instrument's default CHARACTER
// under the new MIDI-note slider (per feedback, below) rather than
// resetting every track to one arbitrary shared note.
~percInstrumentPitchDefaults = (baseD: 33, cym: 62, hat: 108, kick: 31);
~percInstrumentVolumeDefaults = (baseD: 1, cym: 1, hat: 0.2, kick: 0.5);
// ~percBasePitch[name]/~percVolumeLevels[name] are both now [lo, hi] pairs -
// one dual-handle RangeSlider each in the Percussion + Bass Generator window
// (CT8guiPercGenerator.scd), replacing Pitch's old 3-widget-set-per-mode
// (one box/two boxes/four boxes for Fixed/Rising/Random) and Volume's old
// Fixed-Slider-or-two-Alternate-Sliders. \fixed now just reads the high end
// of each pair (hi); \random/\alternate use the whole [lo, hi] span; \rising
// climbs from lo toward hi - see ~buildPercPattern's own pitch comment,
// below, for that one's exact rule. Defaulting to [d, d] (a zero-width
// range at each instrument's own default) means Fixed mode's default
// behavior is unchanged from before the RangeSlider existed; Random/Rising/
// Alternate only actually vary once the handles are dragged apart.
~percTrackNames.do { |name|
    ~percSource[name] = ~percSource[name] ? ~percSourceDefaults[name];
    ~percInstrument[name] = ~percInstrument[name] ? ~percInstrumentDefaults[name];
    ~percPattern[name] = ~percPattern[name] ? \everyBeat;
    ~percPitchMode[name] = ~percPitchMode[name] ? \fixed;
    ~percBasePitch[name] = ~percBasePitch[name] ? {
        var d = ~percInstrumentPitchDefaults[~percInstrumentDefaults[name]];
        [d, d]
    }.value;
    ~percVolumeMode[name] = ~percVolumeMode[name] ? \fixed;
    ~percVolumeLevels[name] = ~percVolumeLevels[name] ? {
        var d = ~percInstrumentVolumeDefaults[~percInstrumentDefaults[name]];
        [d, d]
    }.value;
    ~percWet[name] = ~percWet[name] ? 0;
    ~percLevel[name] = ~percLevel[name] ? 1;
    ~percSplitPercent[name] = ~percSplitPercent[name] ? 33;
};

// Forcibly resets one track's whole Percussion Generator config back to
// these same original defaults - unlike the ? initialization just above
// (which only fills in a value the first time, so live tuning survives a
// re-evaluation of this file), this always overwrites, regardless of
// whatever's currently set. Used by the Percussion Generator window's
// "Reset to defaults" button (CT8guiPercGenerator.scd), which calls this
// for every track, rebuilds the window so the GUI reflects the reset
// values, then applies immediately the same way Apply now does.
~resetPercConfig = { |name|
    var pitchD, volD;
    ~percSource[name] = ~percSourceDefaults[name];
    ~percInstrument[name] = ~percInstrumentDefaults[name];
    ~percPattern[name] = \everyBeat;
    ~percPitchMode[name] = \fixed;
    pitchD = ~percInstrumentPitchDefaults[~percInstrumentDefaults[name]];
    ~percBasePitch[name] = [pitchD, pitchD];
    ~percVolumeMode[name] = \fixed;
    volD = ~percInstrumentVolumeDefaults[~percInstrumentDefaults[name]];
    ~percVolumeLevels[name] = [volD, volD];
    ~percWet[name] = 0;
    ~percLevel[name] = 1;
    ~percSplitPercent[name] = 33;
};


// ---------------------------------------------------------------------------
// MONO TRACK CONFIG (BT1/BT2/MT1/MT2 - the "Note" tracks)
// ---------------------------------------------------------------------------
// The project now groups its 13 tracks into three families - Perc tracks
// (PT1-4, ~percX config above), Note tracks (BT1/BT2/MT1/MT2, ~monoX
// here), and Harmony tracks (HT1-4, ~polyX, CT8guiHarmonyMelodyGenerator.scd)
// - named for their code prefix after how many notes they ever sound at
// once: perc(ussion) keeps its own name; mono(phonic), one note at a
// time, for BT1/BT2/MT1/MT2; poly(phonic), a chord at a time, for HT1-4.
// Per feedback, BT1/BT2/MT1/MT2 are no longer thought of as "bass tracks"
// and "melody tracks" with their own separate structures - they're four
// interchangeable Note tracks, differing only in which options they each
// happen to be set to (same Dur Pat/Pit Pat/Accents choices, same two
// instruments). MT1/MT2 share every one of these globals with BT1/BT2
// (keyed by \MT1/\MT2 right alongside \BT1/\BT2) and are built by the
// exact same ~buildMonoTrackPattern, below - MT1/MT2 used to have their
// own bespoke builder (~buildMelodyPattern, with hand-tuned FM voicing);
// that's gone now, since a bespoke per-track voicing is exactly the kind
// of difference this change removes. The track names BT1/BT2/MT1/MT2, and
// which window each one's controls physically live in (BT1/BT2 in the
// Percussion + Bass Generator window, CT8guiPercGenerator.scd; MT1/MT2
// still in the separate Harmony + Melody Generator window,
// CT8guiHarmonyMelodyGenerator.scd), stay exactly as they are, per
// feedback - only the structure (and the globals' own names, ~bassX ->
// ~monoX) underneath changes, so MT1/MT2's GUI blocks (unchanged in
// appearance) now read/write these same ~monoX globals instead of their
// own former, placeholder ~hmX ones. Set live by whichever window a given
// track's block happens to be in - per-track dictionaries keyed by track
// name symbol, read fresh on every rebuild by ~buildMonoTrackPattern,
// below - but a few shapes differ, since these two instruments
// (\fm/\plucking) aren't percussion's four:
//   - Both \fm/\plucking take a \midinote key directly (Pbind/Event's
//     standard pitch-key handling converts it to \freq for us), so there's
//     no per-instrument pitch-ARG-name dispatch the way baseD/cym/hat/kick
//     need (~buildPercPattern's pitchArgName switch). Pitch doesn't even
//     need its own ~bassBasePitch any more - all eight pitch modes read
//     ~currentRange[name] directly (CT8harmonySelect.scd), the exact same
//     global HT1/MT1 use for their own chord-note picks: Fixed is
//     ~chordRootInRange (the chord's own root note, deterministic, not a
//     random pick); Random is ~chordNoteInRange (any chord tone, any
//     octave, picked anew each baseline slot); Rising is
//     ~makeRisingPitchGen (starts at the same root ~chordRootInRange
//     would give, then climbs ~scales[~chordSet] one degree per baseline
//     slot - not per row/column-start - wrapping back to the root once
//     the climb would exceed the range's high end, and resetting fully
//     only at the next bar); Falling is ~makeFallingPitchGen, its mirror -
//     starts at the TOP of the range (~chordTopInRange) and descends
//     instead, wrapping back to the top once it would go below the
//     range's low end; Looping is ~makeLoopingPitchGen - starts at the
//     same root ~chordRootInRange gives, picks a random direction once,
//     then steps through ~scales[~chordSet] in that direction like
//     Rising/Falling do, but REVERSES direction at whichever bound it
//     reaches instead of wrapping, bouncing between lo and hi. Arp
//     Rising/Arp Falling/Arp Looping, per feedback, are the exact same
//     three generator functions again, just fed ~chordArpIntervals.(chord)
//     (CT8harmonySelect.scd - the current chord's own tones, not its
//     parent scale's degrees) instead of ~scales[~chordSet] - "same basic
//     idea," just a different list of offsets to step through. Both
//     instruments also just take a plain
//     \amp key for their output level, so there's no per-instrument
//     amp-arg-name dispatch needed either (unlike pitch/amp-arg dispatch
//     being two separate concerns for baseD/cym/hat/kick).
//   - ~monoVolumeLevels[name] is a [lo, hi] pair (one dual-handle
//     RangeSlider in the GUI) - Fixed reads its high end; Alternate uses
//     the whole span, same idea as percussion's ~percVolumeLevels.
//   - Pattern has no \firstBeat option (per feedback, not a useful choice
//     for a Note track part) - otherwise the exact same twelve choices
//     PT1-4 have.
// ~btTrackNames stays [\BT1, \BT2] - CT8guiPercGenerator.scd still uses
// it to decide which blocks render in ITS window, and MT1/MT2's blocks
// stay in the Harmony + Melody Generator window instead, per feedback
// ("I do not want to change ... the layouts"). ~monoTrackNames is the
// broader list ("Note tracks") used below for filling in/
// resetting all four tracks' shared config, regardless of which window
// each one's own GUI block actually lives in.
~btTrackNames = [\BT1, \BT2];
~monoTrackNames = [\BT1, \BT2, \MT1, \MT2];
~monoSource = ~monoSource ? ();
~monoInstrument = ~monoInstrument ? ();
~monoPattern = ~monoPattern ? ();
~monoPitchMode = ~monoPitchMode ? ();
~monoVolumeMode = ~monoVolumeMode ? ();
~monoVolumeLevels = ~monoVolumeLevels ? ();
~monoWet = ~monoWet ? ();
~monoLevel = ~monoLevel ? ();
~monoSplitPercent = ~monoSplitPercent ? ();
// BT1/MT1 default to Row, BT2/MT2 to Col - per feedback, MT1/MT2 flip
// their own default from the old bespoke ~buildMelodyPattern's hardcoded
// Col-only behavior, so MT1/MT2 now mirror BT1/BT2's own Row/Col split
// exactly rather than defaulting to the same scan.
~monoSourceDefaults = (BT1: \row, BT2: \col, MT1: \row, MT2: \col);
~monoInstrumentDefaults = (BT1: \fm, BT2: \plucking, MT1: \fm, MT2: \fm);
// Each instrument's own default amp, straight off its SynthDef
// (CT8synths.scd) - same idea as ~percInstrumentVolumeDefaults, above.
~monoInstrumentVolumeDefaults = (fm: 0.2, plucking: 0.2);
// Each track's own default ~currentRange[name] (CT8harmonySelect.scd) -
// BT1/BT2 keep their historical "below middle C" register; MT1/MT2 keep
// their own historical higher one, even though both pairs are otherwise
// identical in structure now - nothing about "Note track" forces
// every one of them into the same register.
~monoRangeDefaults = (BT1: [12, 59], BT2: [12, 59], MT1: [60, 96], MT2: [60, 96]);
~monoTrackNames.do { |name|
    ~monoSource[name] = ~monoSource[name] ? ~monoSourceDefaults[name];
    ~monoInstrument[name] = ~monoInstrument[name] ? ~monoInstrumentDefaults[name];
    ~monoPattern[name] = ~monoPattern[name] ? \everyBeat;
    ~monoPitchMode[name] = ~monoPitchMode[name] ? \fixed;
    ~monoVolumeMode[name] = ~monoVolumeMode[name] ? \fixed;
    ~monoVolumeLevels[name] = ~monoVolumeLevels[name] ? {
        var d = ~monoInstrumentVolumeDefaults[~monoInstrumentDefaults[name]];
        [d, d]
    }.value;
    ~monoWet[name] = ~monoWet[name] ? 0;
    ~monoLevel[name] = ~monoLevel[name] ? 1;
    ~monoSplitPercent[name] = ~monoSplitPercent[name] ? 33;
};

// Forcibly resets one track's whole Bass Generator config back to these same
// original defaults - mirrors ~resetPercConfig exactly, same reason (see its
// comment, above).
~resetMonoConfig = { |name|
    var volD;
    ~monoSource[name] = ~monoSourceDefaults[name];
    ~monoInstrument[name] = ~monoInstrumentDefaults[name];
    ~monoPattern[name] = \everyBeat;
    ~monoPitchMode[name] = \fixed;
    ~monoVolumeMode[name] = \fixed;
    volD = ~monoInstrumentVolumeDefaults[~monoInstrumentDefaults[name]];
    ~monoVolumeLevels[name] = [volD, volD];
    ~monoWet[name] = 0;
    ~monoLevel[name] = 1;
    ~monoSplitPercent[name] = 33;
// Also resets ~currentRange[name] (CT8harmonySelect.scd) back to its own
// per-track default (~monoRangeDefaults, above) - previously missed here,
// which meant this button couldn't recover a track whose Pitch
// RangeSlider had left it holding a bad value.
    ~currentRange[name] = ~monoRangeDefaults[name];
};


// ---------------------------------------------------------------------------
// FX GENERATOR CONFIG (FXT1/FXT2)
// ---------------------------------------------------------------------------
// FXT1/FXT2 replace HT3/HT4 (~trackNames, below) - a new track family, per
// feedback ("going to take HT3 and HT4 and rename them FXT1 and FXT2"), not
// a mere rename. Each track is actually TWO Synths working together, per
// feedback ("treating the pulse as a separate event. the bar long note
// gets triggered, but is sent to the input of a second event that is the
// pulse envelope"): a "carrier" (\noiseCarrier/\rumbleCarrier,
// CT8synths.scd) plays continuously for the whole bar into a private bus,
// and a separate "pulse" Synth (\fxPulse, shared by both instruments)
// reads from that bus and is the ONLY thing that decides what's actually
// heard - see ~buildFxPattern's own comment, below, for the full
// two-synth/bus/Group design (this replaces an earlier single-SynthDef,
// additive-envelope design that turned out to always leave an audible
// floor, making the pulse barely noticeable regardless of Pulse %).
//   ~fxSource[name] - \row or \col, same meaning/defaults convention as
//     every other family's own Source (PT1/PT3 default \row, PT2/PT4
//     default \col, etc.) - FXT1 defaults \row, FXT2 \col. Only matters
//     for \startOnly (below); \firstBeat/\everyBeat ignore it entirely,
//     same as every other family's own Source/pattern interaction.
//   ~fxInstrument[name] - \rumble or \noise, per feedback ("to hard to
//     hear with noise... lets do it with rumble. add rumble to both FX
//     tracks") - both FXT1/FXT2 now default to \rumble. \seq/\lead are
//     still a planned follow-up, each needing their own carrier SynthDef
//     variant the way \noiseCarrier/\rumbleCarrier wrap \noise/\rumble's
//     own sound. ~fxSynthNames maps the friendly menu symbol to the actual
//     carrier SynthDef, same role CT8guiSynthLab.scd's own `synthNames`
//     plays there.
//   ~fxPattern[name] - \firstBeat (one pulse per bar), \startOnly (one
//     pulse per row/column span), or \everyBeat (one pulse per beat) - all
//     three real, per feedback ("have the dur pat choices be first beat
//     only, first of row/col, every beat... this should make the envelope
//     that follows the row or every beat more obvious"). Row/column spans
//     are IRREGULAR (different rows/columns have different widths),
//     unlike firstBeat/everyBeat's own uniform spacing - unlike the
//     earlier single-Synth design, this is no longer a problem: each pulse
//     is now its own independent Pbind event (same multi-event-per-bar
//     technique every other family's own builder already uses), so an
//     irregular span is exactly as easy to schedule as a uniform one.
//   ~fxPulsePercent[name] - what fraction (0-100) of THIS SPECIFIC span's
//     own length each pulse's own "on" portion occupies - converted to
//     pulsedur/releaseDur (real seconds) by ~buildFxPattern, fresh per
//     trigger.
//   ~fxWet[name]/~fxLevel[name] - this track's own tiny built-in
//     ~allpassWash tail (now living on \fxPulse, not the carrier - the
//     reverb send should colour the actual audible bursts, not a signal
//     nothing ever hears on its own), same role/convention as
//     ~percWet/~percLevel - doubles as FXT1/FXT2's only overall volume
//     control (no separate amp slider - ~allpassWash's own `level` arg
//     already scales the whole mix), read live via Pfunc same as
//     everywhere else.
~fxTrackNames = [\FXT1, \FXT2];
~fxSynthNames = (noise: \noiseCarrier, rumble: \rumbleCarrier);
~fxSourceDefaults = (FXT1: \row, FXT2: \col);
~fxSource = ~fxSource ? ();
~fxInstrument = ~fxInstrument ? ();
~fxPattern = ~fxPattern ? ();
~fxPulsePercent = ~fxPulsePercent ? ();
~fxWet = ~fxWet ? ();
~fxLevel = ~fxLevel ? ();
~fxTrackNames.do { |name|
    ~fxSource[name] = ~fxSource[name] ? ~fxSourceDefaults[name];
    ~fxInstrument[name] = ~fxInstrument[name] ? \rumble;
    ~fxPattern[name] = ~fxPattern[name] ? \firstBeat;
    ~fxPulsePercent[name] = ~fxPulsePercent[name] ? 20;
    ~fxWet[name] = ~fxWet[name] ? 0;
    ~fxLevel[name] = ~fxLevel[name] ? 1;
};

// Forcibly resets one FX track's whole config back to these same original
// defaults - mirrors ~resetPercConfig/~resetMonoConfig/~resetPolyConfig,
// same reason (see any one's own comment).
~resetFxConfig = { |name|
    ~fxSource[name] = ~fxSourceDefaults[name];
    ~fxInstrument[name] = \rumble;
    ~fxPattern[name] = \firstBeat;
    ~fxPulsePercent[name] = 20;
    ~fxWet[name] = 0;
    ~fxLevel[name] = 1;
};

// ---------------------------------------------------------------------------
// FXT1/FXT2: TWO-SYNTH PULSING TEXTURE, FROM FX GENERATOR CONFIG
// ---------------------------------------------------------------------------
// Builds TWO Pbinds running concurrently as one Ppar (fully compatible
// with the existing ~trackPatterns[name]/.play(t, quant:1)/~syncTrackPlayer
// machinery - a Ppar is just another Pattern, no changes needed there):
//
// carrierPattern - one event per bar (\dur, events.size - same
// bar-length-in-beats every other builder's own one-trigger-per-bar
// patterns use), playing \noiseCarrier/\rumbleCarrier into this track's
// own private audio bus (~fxCarrierBus[name]) rather than hardware
// output - it just needs to keep sounding continuously for the bar;
// ~fxPulsePercent/Dur Pat have no bearing on it at all.
//
// pulsePattern - one event PER PULSE (\dur, Pseq(pulseDurs, inf) - however
// many times a bar, per ~fxPattern[name]'s own Dur Pat choice), each a
// short-lived \fxPulse synth that reads FROM that same bus and is the
// ONLY thing that actually reaches real output - between pulses, nothing
// else is writing to `out` for this track, so it's genuine silence, not a
// quieter hum (the problem with the earlier single-Synth, additive-
// envelope design). pulseDurs (plural) is the actual list of per-pulse
// span lengths, IN BEATS - computed once per rebuild (structure only
// changes when the clock scan itself changes), via the exact same
// nextIdx-idx gap technique every other builder in this file already
// uses: \firstBeat is one span, the whole bar; \everyBeat is one span,
// one beat (Pseq's own infinite repeat cycles it); \startOnly is one span
// PER ROW/COLUMN, each one that span's own real (irregular) width - since
// each pulse is its own independent Pbind event now, an irregular span is
// exactly as easy to schedule as a uniform one, no buffer/demand-rate
// trickery needed. pulsedur/releaseDur are sized from THIS SPECIFIC
// pulse's own span length every time (ev[\dur], read back after Pseq
// resolves it) - exact per-pulse shaping, not a bar-wide average.
//
// ~fxCarrierBus[name] (a private 2-channel audio Bus) and
// ~fxSourceGroup[name]/~fxPulseGroup[name] (persistent Groups, the pulse
// group created immediately AFTER the source group via Group.after - so
// the carrier's own node always executes before the pulse's regardless of
// which actually got its Synth triggered first that instant, guaranteeing
// the pulse always reads this block's freshly-written carrier signal, not
// stale/empty data) are each allocated once, lazily, and reused across
// rebuilds - same "allocate once, keep forever" convention as every other
// persistent server resource in this project (~revBus, Groups, etc.).
//
// Deliberately does NOT splice in ~labOverrideArgs (unlike every other
// builder) - \noiseCarrier/\rumbleCarrier/\fxPulse are different SynthDefs
// from the Synth Lab's own plain \noise/\rumble entries, and \noise's own
// `dur` key (seconds) would collide with Pbind's reserved \dur (beats) if
// the Synth Lab ever live-tracked it, silently breaking this track's own
// bar-length scheduling - not worth the risk for a feature that wouldn't
// even apply cleanly here given how different these SynthDefs' own param
// sets are.
~fxCarrierBus = ~fxCarrierBus ? ();
~fxSourceGroup = ~fxSourceGroup ? ();
~fxPulseGroup = ~fxPulseGroup ? ();
~buildFxPattern = { |name|
    var instrument = ~fxInstrument[name];
    var carrierSynthName = ~fxSynthNames[instrument];
    var pattern = ~fxPattern[name];
    var fromRow = (~fxSource[name] == \row);
    var events = if(fromRow) { ~rowPattern ? [] } { ~colPattern ? [] };
    var startRole = if(fromRow) { \rowStart } { \columnStart };
    var startIdx = [];
    var pulseDurs;
    var carrierPattern, pulsePattern;

    if(events.isEmpty) {
        ("No active clock cells to play (" ++ name ++ ").").warn;
        ~trackPatterns[name] = Pbind(\dur, 1, \type, \rest);
    } {
        events.do { |ev, i| if(ev[\role] == startRole) { startIdx = startIdx.add(i) } };

        pulseDurs = switch(pattern,
            \firstBeat, { [events.size] },
            \everyBeat, { [1] },
            { startIdx.collect { |idx, i|
                var nextIdx = if((i + 1) < startIdx.size) { startIdx[i + 1] } { events.size + startIdx[0] };
                nextIdx - idx
            } }
        );

        if(~fxCarrierBus[name].isNil) {
            ~fxCarrierBus[name] = Bus.audio(s, 2);
            ~fxSourceGroup[name] = Group.new(s);
            ~fxPulseGroup[name] = Group.after(~fxSourceGroup[name]);
        };

        carrierPattern = Pbind(
            \instrument, carrierSynthName,
            \dur, Pfunc { events.size },
            \masterDur, Pfunc { |ev| ev[\dur] / t.tempo },
            \out, Pfunc { ~fxCarrierBus[name].index },
            \group, Pfunc { ~fxSourceGroup[name] },
            \type, Pfunc { if(~trackEnabled[name]) { \note } { \rest } }
        );

        pulsePattern = Pbind(*([
            \instrument, \fxPulse,
            \dur, Pseq(pulseDurs, inf),
            \pulsedur, Pfunc { |ev| (ev[\dur] / t.tempo) * (~fxPulsePercent[name] / 100) },
            \releaseDur, Pfunc { |ev| ((ev[\dur] / t.tempo) - ev[\pulsedur]).max(0.01) },
            \in, Pfunc { ~fxCarrierBus[name].index },
            \out, 0,
            \wet, Pfunc { ~fxWet[name] },
            \level, Pfunc { ~fxLevel[name] },
            \group, Pfunc { ~fxPulseGroup[name] },
            \type, Pfunc { if(~trackEnabled[name]) { \note } { \rest } }
        ] ++ ~auxSendPbindArgs.(name)));

        ~trackPatterns[name] = Ppar([carrierPattern, pulsePattern]);
    };
};


~trackNames = [
    \PT1, \PT2, \PT3, \PT4,   // percussion
    \BT1,  \BT2,                    // bass
    \HT1, \HT2, \FXT1, \FXT2, // rhythm/harmony + fx (FXT1/FXT2 replace the
                              // old HT3/HT4 slots - a new family, not a
                              // mere rename, per feedback)
    \MT1, \MT2, \MT3, \MT4    // melody
];
~trackPatterns = ~trackPatterns ? ();
~trackPlayers = ~trackPlayers ? ();
~trackEnabled = ~trackEnabled ? ();
~trackBuilders = ();
// ~trackPatterns/~trackPlayers need no initialization here - a Dictionary
// already returns nil for a key that isn't set, which is exactly what an
// unbuilt/not-playing track should read as. Only ~trackEnabled (the user's
// on/off choice) needs a real default, so it survives re-evaluation sanely.
~trackNames.do { |name|
// Every track defaults off now, per feedback ("set things to start with
// all tracks off") - previously PT1/PT2/PT3 defaulted on here, and
// CT8main.scd separately forced HT1/MT1/BT1/MT2 on too, every run; both of
// those are gone now (see CT8main.scd's own RUNTIME PARAMETERS comment).
// All thirteen tracks can still be switched on by hand, either in the
// Percussion Generator window (PT1-4/BT1-2) or the Harmony + Melody
// Generator/Clock Toy Adjust windows (everything else).
    ~trackEnabled[name] = ~trackEnabled[name] ? false;
};

// ---------------------------------------------------------------------------
// AUX SENDS ("mixer phase") - every track's own Send A/Send B
// ---------------------------------------------------------------------------
// Per feedback: every track (any family - perc/mono/poly all share this,
// keyed by plain track name rather than living inside any one family's own
// ~percX/~monoX/~polyX config) gets two independently-assignable aux
// sends, each a (which registered effect, how much) pair -
// ~sendAEffect[name]/~sendBEffect[name] are indices into
// ~auxEffectNames/~auxEffectBuses (CT8synths.scd's own bullet - built
// once ~revBus exists, so these default to index 0, "ELI Reverb", safely
// even though that array doesn't exist yet at THIS point in file-load
// order); ~sendAAmt[name]/~sendBAmt[name] are the actual send amount,
// 0-1, defaulting to 0 (silent) - the same "no-op until deliberately
// raised" convention every other Wet/Level-style control already uses.
~sendAEffect = ~sendAEffect ? ();
~sendAAmt = ~sendAAmt ? ();
~sendBEffect = ~sendBEffect ? ();
~sendBAmt = ~sendBAmt ? ();
~trackNames.do { |name|
    ~sendAEffect[name] = ~sendAEffect[name] ? 0;
    ~sendAAmt[name] = ~sendAAmt[name] ? 0;
    ~sendBEffect[name] = ~sendBEffect[name] ? 0;
    ~sendBAmt[name] = ~sendBAmt[name] ? 0;
};

// ~auxSendPbindArgs.(name) - the four extra Pbind keys every builder below
// appends (via ++) to its own Pbind argument array, so every track's two
// aux sends work regardless of which family builds it. Wrapped in Pfunc,
// not read as bare values - same reasoning as \fm's own \fx key (a live
// Bus reference sitting directly in a Pbind pair is suspect) - and all
// four are read fresh every event, so dragging either Send slider or
// re-assigning its target effect takes effect immediately, no rebuild
// needed, exactly like Wet/Level.
~auxSendPbindArgs = { |name|
    [
        \auxBusA, Pfunc { ~auxEffectBuses[~sendAEffect[name]] },
        \auxAmtA, Pfunc { ~sendAAmt[name] },
        \auxBusB, Pfunc { ~auxEffectBuses[~sendBEffect[name]] },
        \auxAmtB, Pfunc { ~sendBAmt[name] }
    ];
};

// ---------------------------------------------------------------------------
// SYNTH LAB LIVE OVERRIDES - tuning presets against the running composition
// ---------------------------------------------------------------------------
// Per feedback ("I need a way to tune the presets so lets connect the lab
// to the running synths"): ~labLiveOverrides[instrumentSym] is an Event of
// {param: value} for whichever ONE instrument is currently selected in the
// Synth Lab (CT8guiSynthLab.scd's own `menu.action` populates it fresh -
// every OTHER instrument's entry gets cleared at the same time, since the
// intended workflow is "run only one track with that synth in it, tune it
// live" - not several at once). Deliberately excludes \wet/\level and any
// \noteN key - those already have their own, separate live controls
// (each track's own Wet/Level slider; chord-aware pitch picking) that
// this is not meant to second-guess. ~labOverrideArgs.(instrumentSym),
// below, is what every builder calls to splice these in, generically,
// without needing to know any instrument's own param names in advance.
~labLiveOverrides = ~labLiveOverrides ? ();

// ~labOverrideArgs.(instrumentSym) - a flat array of [key, Pfunc {...},
// ...] pairs, one per currently-live-tuned param for that instrument (none
// at all, most of the time - only populated while the Synth Lab has that
// exact instrument selected). Read fresh every event, like every other
// Pfunc-driven control here, so a Synth Lab slider drag is audible on
// whichever live track is currently using that instrument without any
// rebuild. The SET of keys is only resolved at BUILD time, same as
// everything else a Pbind's own argument array decides once - a param the
// Synth Lab hasn't started tracking yet for this instrument won't appear
// until the next rebuild, same "structure fixed at rebuild, values can be
// live" rule the rest of this file already follows.
~labOverrideArgs = { |instrumentSym|
    var overrides = ~labLiveOverrides[instrumentSym];
    var args = [];
    if(overrides.notNil) {
        overrides.keysValuesDo { |k, v|
            args = args ++ [k, Pfunc { ~labLiveOverrides[instrumentSym][k] }];
        };
    };
    args;
};

// ---------------------------------------------------------------------------
// PLAYER LIFECYCLE HELPERS
// ---------------------------------------------------------------------------
// Stop a track's current player (if any), then restart it if it's enabled
// and has a built pattern. Shared by every track's on/off button so each
// resyncs the same way, regardless of which window it lives in: HT1-4/
// MT1-4's buttons are in CT8guiAdjust.scd, while PT1-4/BT1-2's are in
// CT8guiPercGenerator.scd instead (beside each track's name there, not in
// the Adjust window at all).
~syncTrackPlayer = { |name|
    if(~trackPlayers[name].notNil) { ~trackPlayers[name].stop; ~trackPlayers[name] = nil };
    if(~trackEnabled[name] and: { ~trackPatterns[name].notNil } and: { t.notNil }) {
        ~trackPlayers[name] = ~trackPatterns[name].play(t, quant: 1);
    };
};


// ---------------------------------------------------------------------------
// PT1-PT4: GENERIC PERCUSSION TRACK, FROM PERCUSSION GENERATOR CONFIG
// ---------------------------------------------------------------------------
// Replaces the old ~buildRowPattern (PT1-only)/~buildColumnPattern (PT2's
// fixed two-synth-role system)/~buildSnarePattern (PT3's hand-tuned
// ~snareTemplate) - all four percussion tracks now read the same per-track
// config (~percSource/~percInstrument/~percPattern/~percPitchMode/
// ~percBasePitch/~percVolumeMode/~percVolumeLevels/~percWet/~percLevel/
// ~percSplitPercent - see PERCUSSION GENERATOR CONFIG, above) through this
// one parameterized builder, registered per track name below.
// Pre-resolves the whole bar into flat dur/pitch arrays - same technique
// validated in CT8guiTracksLab.scd's prototype - rather than a live
// per-event Pfunc, since ~percPattern[name] needs to change how many slots
// the Pbind actually has (every beat, starts only, or just one per bar),
// not just what plays on a fixed-size stream.
~buildPercPattern = { |name|
    var fromRow = (~percSource[name] == \row);
    var events = if(fromRow) { ~rowPattern ? [] } { ~colPattern ? [] };
    var startRole = if(fromRow) { \rowStart } { \columnStart };

    if(events.isEmpty) {
        ("No active clock cells to play (" ++ name ++ ").").warn;
        ~trackPatterns[name] = Pbind(\dur, 1, \type, \rest);
    } {
        var startIdx = [];
        var baseSlotIdx, basePitches, pitchOffset = 0, fallSteps = 0;
        var loopDir = 1, loopPitch = 0;
        var durs = [], pitches = [], restFlags = [], amps = [];
        var beatIndex = 0, ampIndex = 0, nextAmp;
        var instrument = ~percInstrument[name];
        var pattern = ~percPattern[name];
        var splitCount, splitVariant, lastOfGroupIdx;
        var isMergePattern, mergeVariant, mergeStart;
// The arg name a pitch value actually needs to go in differs by instrument -
// baseD/cym use \basefreq, hat uses \freq, kick uses \drumFreq (its own
// pitch-sweep's settled frequency - see CT8guiTracksLab.scd's header for
// more on how that sweep works). Picked once per rebuild, from whichever
// instrument is currently selected for this track. Every other \kick arg
// (drumHarmonic/drumSweep/drumAtt/etc.) just stays at its SynthDef default
// here, same as every other instrument's own non-pitch/amp/wet/level params
// (baseD's rq/overdrive, cym's len, hat's noiseFreq) - the Percussion
// Generator only ever exposes Pitch/Volume/Wet/Level generically, not
// per-instrument extras.
        var pitchArgName = switch(instrument,
            \baseD, { \basefreq },
            \cym, { \basefreq },
            \hat, { \freq },
            \kick, { \drumFreq }
        );

// By construction (the scan that builds ~rowPattern/~colPattern always marks
// a row/column's first lit cell with its start role) there is always at
// least one, since the empty-events case above already handled the only way
// there could be zero.
        events.do { |ev, i| if(ev[\role] == startRole) { startIdx = startIdx.add(i) } };

// Which beats make up the baseline grid, per ~percPattern[name] - every
// pattern except \firstBeat/\startOnly starts from the full every-beat grid
// (\everyBeat itself, \randomSkip, and all six split patterns below, which
// then split/silence some of it rather than changing this baseline).
        baseSlotIdx = if(pattern == \firstBeat) { [0] } {
            if(pattern == \startOnly) { startIdx } { (0..events.size - 1) }
        };

// ~percBasePitch[name] is [lo, hi] IN MIDI NOTES now, not Hz (one
// dual-handle RangeSlider in the GUI, CT8guiPercGenerator.scd, mapped
// 0-127 - "same as piano keyboard" for every instrument for now, per
// feedback, though each one will get its own range eventually) - every
// mode below still works entirely in this MIDI-note space; the one and
// only place this ever gets converted to the Hz each instrument's own
// pitch arg actually needs is a single `.midicps` on the whole resolved
// `pitches` array, right before the Pbind gets built, below. \fixed
// always just reads hi; \random picks
// anywhere in [lo, hi]; \rising climbs from lo toward hi over the course of
// a row/column span, in 8 fixed steps (an arbitrary subdivision, not
// derived from how many slots the span actually has - a span shorter than
// 8 slots just doesn't reach hi before the next reset), resetting to lo at
// every genuine start, then CLAMPING at hi once reached (stays there for
// the rest of the span) - this is the ONLY place pitchOffset changes.
// \falling is Rising's mirror, per feedback - starts at hi and steps DOWN
// toward lo in the same 8 fixed steps, but WRAPS back to hi (not clamping)
// once it would go below lo, so a span longer than 8 slots hears the
// descent repeat rather than sitting at lo for the remainder; fallSteps
// (separate from pitchOffset, which \rising still owns alone) tracks steps
// taken since the last reset/wrap - reset to 0 at every genuine start,
// same as pitchOffset, and reset to 1 (not 0) on a wrap, so the following
// hit continues from the SECOND step rather than repeating hi twice in a
// row. \looping is a third variant, per feedback - no "chord root" to
// start from here (percussion has no chord concept), so it starts at the
// midpoint of [lo, hi] instead, picks a random direction (up or down)
// fresh at every genuine start (same reset cadence as \rising/\falling),
// then steps by the same (hi-lo)/8 size in that direction - but instead of
// wrapping back to the start once it would cross a bound, it REVERSES
// direction right there and immediately recomputes this same hit's pitch
// one step in the new direction (rather than re-emitting the turning-point
// note, which would otherwise repeat it twice in a row), so it bounces
// back and forth between lo and hi instead of restarting or wrapping.
// Computed once per baseline slot, before any random splitting below
// - a slot split into a double hit or triplet gives every one of those
// hits the same pitch, rather than advancing mid-split.
        basePitches = baseSlotIdx.collect { |idx|
            var isStart = startIdx.includes(idx);
            var lo = ~percBasePitch[name][0];
            var hi = ~percBasePitch[name][1];
            if(isStart) {
                pitchOffset = 0;
                fallSteps = 0;
                loopDir = [1, -1].choose;
                loopPitch = (lo + hi) / 2;
            } {
                if(~percPitchMode[name] == \rising) {
                    pitchOffset = pitchOffset + ((hi - lo) / 8);
                };
            };
            switch(~percPitchMode[name],
                \fixed, { hi },
                \rising, { (lo + pitchOffset).min(hi) },
                \falling, {
                    var candidate = hi - (fallSteps * ((hi - lo) / 8));
                    if(candidate < lo) {
                        fallSteps = 1;
                        hi;
                    } {
                        fallSteps = fallSteps + 1;
                        candidate;
                    }
                },
                \looping, {
                    if(isStart) {
                        loopPitch;
                    } {
                        var step = (hi - lo) / 8;
                        var candidate = loopPitch + (loopDir * step);
                        var outOfBounds = if(loopDir > 0) { candidate > hi } { candidate < lo };
                        if(outOfBounds) {
                            loopDir = loopDir * -1;
                            candidate = loopPitch + (loopDir * step);
                        };
                        loopPitch = candidate;
                        candidate;
                    }
                },
                \random, { rrand(lo, hi) }
            )
        };

// Next hit's \amp, per ~percVolumeMode[name] - \fixed always reads
// ~percVolumeLevels[name]'s high end (the loudest/"normal" value, per
// feedback); \alternate flips between its two
// ends every actual sounding hit (ampIndex counts hits, not baseline
// slots, so a slot split into a double hit/triplet below still alternates
// hit to hit, not just slot to slot), high end (loud) first, then the low
// end (softer) - checked against feedback describing this exact
// behavior as the intended design; found it already matches, so left
// unchanged here. \random, new per feedback, picks anywhere in [lo, hi]
// fresh every hit (not just every baseline slot), same "whole span,
// re-rolled every time" idea \percPitchMode[name]'s own \random already
// uses for pitch.
        nextAmp = {
            var lo = ~percVolumeLevels[name][0];
            var hi = ~percVolumeLevels[name][1];
            var v = switch(~percVolumeMode[name],
                \alternate, { if(ampIndex % 2 == 0) { hi } { lo } },
                \random, { rrand(lo, hi) },
                { hi }
            );
            ampIndex = ampIndex + 1;
            v;
        };

// Every split pattern decomposes into (splitCount, splitVariant): how many
// sub-hits it produces, and which beats get them. splitCount stays 1 for
// every non-split pattern, where shouldSplit (below) is always false anyway
// so splitVariant is never actually read.
        splitCount = switch(pattern,
            \random8thPercent, { 2 }, \random8thLastBar, { 2 }, \random8thLastRowCol, { 2 },
            \random3rdPercent, { 3 }, \random3rdLastBar, { 3 }, \random3rdLastRowCol, { 3 },
            { 1 }
        );
        splitVariant = switch(pattern,
            \random8thPercent, { \random }, \random3rdPercent, { \random },
            \random8thLastBar, { \lastOfBar }, \random3rdLastBar, { \lastOfBar },
            \random8thLastRowCol, { \lastOfRowCol }, \random3rdLastRowCol, { \lastOfRowCol },
            { \random }
        );
// Last beat of every row/column span, for splitVariant == \lastOfRowCol:
// group k (0-based) ends right before group (k+1) starts, so its last beat
// is startIdx[k+1]-1, except the FINAL group, which has no "next start" to
// subtract from and instead just ends at events.size-1. startIdx.drop(1)
// skips group 0's own start (irrelevant here - we want where groups END,
// not where they begin) and lines each remaining start index up with the
// group immediately before it.
        lastOfGroupIdx = startIdx.drop(1).collect(_ - 1) ++ [events.size - 1];

// The three \random4to3* patterns are a separate mechanism from the six
// splitCount ones above - those EXPAND one baseline slot into 2/3 sub-hits;
// these MERGE a run of 4 consecutive baseline slots into 3 equal-length
// hits spanning the same total time instead (see this function's own header
// comment, PERCUSSION GENERATOR CONFIG section above, for the full
// explanation of each variant). mergeStart[i] (i an index into baseSlotIdx,
// not a raw event index - baseSlotIdx is always the full 0..events.size-1
// grid whenever a merge pattern is selected, same as every split/skip
// pattern, so the two index spaces coincide here) marks the start of a
// 4-slot group that should merge; any bar/span shorter than 4 slots just
// never gets marked, so it's left as individual beats - the "ignore the
// problem" case this pattern's own description calls out.
        isMergePattern = #[\random4to3Percent, \random4to3LastBar, \random4to3LastRowCol].includes(pattern);
        mergeVariant = switch(pattern,
            \random4to3LastBar, { \lastOfBar },
            \random4to3LastRowCol, { \lastOfRowCol },
            { \random }
        );
        mergeStart = Array.fill(baseSlotIdx.size, { false });
        if(isMergePattern) {
            switch(mergeVariant,
// Non-overlapping groups of 4, scanning from the bar's start - group k
// covers slots [4k, 4k+3]; a group with fewer than 4 slots left before the
// bar ends just isn't offered a roll at all.
                \random, {
                    var groupStart = 0;
                    while ({ (groupStart + 3) < baseSlotIdx.size }) {
                        if(100.0.rand < ~percSplitPercent[name]) { mergeStart[groupStart] = true };
                        groupStart = groupStart + 4;
                    };
                },
// Deterministic: only the bar's final 4 slots, every bar.
                \lastOfBar, {
                    if(baseSlotIdx.size >= 4) { mergeStart[baseSlotIdx.size - 4] = true };
                },
// Deterministic: the final 4 slots of every row/column span (startIdx[k] ..
// lastOfGroupIdx[k]) - skipped for any span shorter than 4 slots.
                \lastOfRowCol, {
                    startIdx.do { |spanStart, k|
                        var spanEnd = lastOfGroupIdx[k];
                        if((spanEnd - spanStart + 1) >= 4) { mergeStart[spanEnd - 3] = true };
                    };
                }
            );
        };

// Expand each baseline slot into its final hit(s). A slot's span is the gap
// to the next baseline slot, or to the end of the bar for the last one -
// the same row/column-span technique HT1/MT1/BT1 use. The six splitCount
// patterns subdivide a slot's own span into splitCount equal hits instead
// of changing that span, for whichever beats shouldSplit picks (per
// splitVariant - \random re-rolls fresh per slot here at rebuild time, same
// as ~percPitchMode's own \random option; \lastOfBar/\lastOfRowCol are
// deterministic, no rolling involved); the three \random4to3* patterns
// instead consume 4 slots at once wherever mergeStart marks a group, ahead
// of all of that; \randomSkip keeps one hit per slot but may mark it a rest
// instead. A manual while loop, not .do, since a merged group advances the
// index by 4 instead of 1.
        {
            var slotI = 0;
            while ({ slotI < baseSlotIdx.size }) {
                if(mergeStart[slotI]) {
                    var groupSpan = 0;
                    var pitch = basePitches[slotI];
                    4.do { |k|
                        var kk = slotI + k;
                        var kIdx = baseSlotIdx[kk];
                        var kNextIdx = if((kk + 1) < baseSlotIdx.size) { baseSlotIdx[kk + 1] } { events.size };
                        groupSpan = groupSpan + (kNextIdx - kIdx);
                    };
                    durs = durs.addAll(Array.fill(3, { groupSpan / 3 }));
                    pitches = pitches.addAll(Array.fill(3, { pitch }));
                    restFlags = restFlags.addAll(Array.fill(3, { false }));
                    amps = amps.addAll(Array.fill(3, { nextAmp.value }));
                    slotI = slotI + 4;
                } {
                    var idx = baseSlotIdx[slotI];
                    var nextIdx = if((slotI + 1) < baseSlotIdx.size) { baseSlotIdx[slotI + 1] } { events.size };
                    var span = nextIdx - idx;
                    var pitch = basePitches[slotI];
                    var shouldSplit = (splitCount > 1) and: {
                        switch(splitVariant,
                            \random, { 100.0.rand < ~percSplitPercent[name] },
                            \lastOfBar, { idx == (events.size - 1) },
                            \lastOfRowCol, { lastOfGroupIdx.includes(idx) }
                        )
                    };
                    if(shouldSplit) {
                        durs = durs.addAll(Array.fill(splitCount, { span / splitCount }));
                        pitches = pitches.addAll(Array.fill(splitCount, { pitch }));
                        restFlags = restFlags.addAll(Array.fill(splitCount, { false }));
                        amps = amps.addAll(Array.fill(splitCount, { nextAmp.value }));
                    } {
                        var isSkip = (pattern == \randomSkip) and: { 100.0.rand < ~percSplitPercent[name] };
                        durs = durs.add(span);
                        pitches = pitches.add(pitch);
                        restFlags = restFlags.add(isSkip);
                        amps = amps.add(nextAmp.value);
                    };
                    slotI = slotI + 1;
                };
            };
        }.value;

        ~trackPatterns[name] = Pbind(*([
            \instrument, instrument,
            \dur, Pseq(durs, inf),
// pitches itself is resolved entirely in MIDI note space (~percBasePitch's
// own units now, per feedback) by the basePitches block above - .midicps
// converts the WHOLE array to Hz here, once, rather than touching every
// individual \fixed/\rising/\falling/\looping/\random branch (or the
// split/merge points that copy a slot's pitch across several hits) -
// baseD/cym/hat/kick all still want a plain Hz value in their own pitch
// arg, same as before this change.
            pitchArgName, Pseq(pitches.midicps, inf),
// Replaces the old Synth Controls window's per-synth amp slider (that
// window is gone - see CLAUDE.md); ~percVolumeMode[name]/~percVolumeLevels[name]
// (Percussion Generator, this track's own Volume row) are the only amp
// source now.
            \amp, Pseq(amps, inf),
// Wrapped in Pfunc rather than passed as a bare value - a Bus object sitting
// directly in a Pbind pair can get walked/expanded like any other Pattern
// value instead of being read as a single opaque value, so every \fx use in
// this file goes through Pfunc instead. Harmlessly ignored by baseD/cym/hat/
// kick, none of which declare an \fx arg - unlike \fm (HT1/MT1/BT1/BT2),
// these four were never reaching ~clockRev through this key, which is
// exactly why ~percWet[name]/~percLevel[name] below exist: it's the only
// reverb PT1-4 can actually have.
            \fx, Pfunc { ~revBus },
// Each instrument's own tiny built-in ~allpassWash tail (see CT8synths.scd's
// \hat \wet/\level comment) - read fresh every note via Pfunc, not baked
// into the pre-resolved arrays above, so both are the only Percussion
// Generator controls that update live with no rebuild/Apply now needed.
            \wet, Pfunc { ~percWet[name] },
            \level, Pfunc { ~percLevel[name] },
// \type going to \rest is the standard Event mechanism for "build this
// event's other keys as normal, but don't actually spawn a synth for it" -
// happens either when the track is switched off, or when this specific hit
// was chosen as a \randomSkip rest. restFlags is read in lockstep with
// \dur/pitchArgName's own Pseq via beatIndex, tracked here separately since
// a Pfunc has no access to another key's Pseq position (mirrors the old
// PT2 beatIndex/isCycleStart tracking this builder replaced). This no
// longer drives any flash/GUI side effect either way; PT1/PT2's row/column
// flash are their own independent players
// (~buildRowFlashPattern/~buildColFlashPattern, CT8guiClock.scd), unrelated
// to whether this track is enabled. PT3/PT4 have no flash at all.
            \type, Pfunc {
                var isRest = (~trackEnabled[name].not) or: { restFlags[beatIndex] };
                beatIndex = (beatIndex + 1) % restFlags.size;
                if(isRest) { \rest } { \note }
            }
// ~auxSendPbindArgs/~labOverrideArgs (the AUX SENDS/SYNTH LAB LIVE
// OVERRIDES sections, above) splice in every track's two aux sends plus
// whatever the Synth Lab currently has live-tuned for this instrument -
// every builder in this file appends both the same way.
        ] ++ ~auxSendPbindArgs.(name) ++ ~labOverrideArgs.(instrument)));
    };
};


// ---------------------------------------------------------------------------
// HT1/HT2: CHORD-PAD HARMONY TRACK, FROM CHORD-PAD GENERATOR CONFIG
// ---------------------------------------------------------------------------
// Per feedback ("going to change the rules for HT1 and HT2... HT3 and HT4
// should be ignored for now"): HT1/HT2 now share one parameterized builder,
// replacing HT1's old bespoke one (a fixed \fm chord patch brought in from a
// different app/tempo context) and giving HT2 a real builder for the first
// time. Both are now restricted to instruments that actually play a chord
// as one managed voicing (\droneChord/\shimmerPad - \fm's own "chord" was
// really 4 independently-triggered Synths via array expansion, and
// \plucking has no chord concept at all, so neither fits this redesign);
// HT3/HT4 are untouched - still no builder, still the original ~fm-based
// skeleton (see makePolyTrackSection's own isRestricted branch,
// CT8guiHarmonyMelodyGenerator.scd, for the GUI side of this split).
//
// Dur Pat narrows to exactly three choices (~polyPattern[name]): \firstBeat
// (one trigger per bar, beat 0 - unchanged meaning), \halfway (one trigger
// per bar, at beat (~numBeats/2).floor - new), \startOnly (one trigger per
// row/column span, same as every other track's "start of row/col"). Pit Pat
// narrows to \fixed/\random (unchanged meaning - an independently-random,
// sorted voicing) plus two new ones, \rising/\falling (see
// ~makeChordVoiceGen's own comment, CT8harmonySelect.scd, for exactly how
// those evolve the voicing note to note). Accents (Volume) is gone
// entirely, per feedback - no \amp key at all below, so every chord just
// plays at its instrument's own SynthDef-default amp.
//
// THE BIG CHANGE, per feedback: the envelope is recalculated fresh for
// every chord played, from the number of beats until the NEXT chord -
// computed the same nextIdx-idx way every other builder in this file
// already computes a span, generalized here to wrap to the FIRST trigger of
// the NEXT bar (baseSlotIdx[0] beats into it) rather than just the end of
// the array, since \halfway's one trigger isn't at index 0 the way every
// other pattern's first trigger always is. Total envelope time is that gap
// plus 2 beats - deliberately longer than the gap itself, so consecutive
// chords' envelopes always overlap somewhat - converted to real seconds via
// t.tempo (both SynthDefs' own envelopes are wall-clock, same conversion
// every other builder here already uses). attack/sustain/release split
// 15%/45%/40% of that total (sums to 100%, per feedback correcting the
// originally-stated 15/45/15); both SynthDefs' own envelope curve
// (CT8synths.scd) is exponential now, to match. \droneChord takes this as
// \attack/\sustain/\release, \shimmerPad as \atk/\sus/\rel (its own
// hardcoded-local-vars-turned-control-args - see CT8synths.scd) - excluded
// from this lab's own live-override tracking for exactly this reason (see
// CT8guiSynthLab.scd's populateLiveOverrides).
//
// `\halfway`'s one trigger needs a `leadIn`-beat rest inserted before the
// repeating cycle (see `leadIn`'s own comment, below) - a Pbind's `\dur`
// sequence only encodes gaps between triggers, not which absolute beat
// playback started on, so without this `\halfway` fired at whatever beat
// the stream happened to start (indistinguishable from `\firstBeat`) -
// found per feedback ("i don't hear droneChord change at half way - it
// only seems to change at first of beat... confirmed by postln"). Also
// gained a `\type`/`~trackEnabled[name]` check (missing entirely before,
// so HT1/HT2's own on/off toggle never silenced them) while fixing that,
// since both touch the same event structure.
~buildPolyPattern = { |name|
    var fromRow = (~polySource[name] == \row);
    var events = if(fromRow) { ~rowPattern ? [] } { ~colPattern ? [] };
    var startRole = if(fromRow) { \rowStart } { \columnStart };

    if(events.isEmpty) {
        ("No active clock cells to play (" ++ name ++ ").").warn;
        ~trackPatterns[name] = Pbind(\dur, 1, \type, \rest);
    } {
        var startIdx = [];
        var baseSlotIdx, durs, leadIn, isLeadInEvent;
        var instrument = ~polyInstrument[name];
        var pattern = ~polyPattern[name];
        var pitchMode = ~polyPitchMode[name];
        var numVoices = if(instrument == \shimmerPad) { 5 } { 4 };
        var lo = ~currentRange[name][0];
        var hi = ~currentRange[name][1];
        var fixedVoicing, voiceGen, voicingFor, currentVoicing, noteArgs;
        var envKeys = if(instrument == \shimmerPad) { [\atk, \sus, \rel] } { [\attack, \sustain, \release] };

// By construction (same as every other builder here) there is always at
// least one start event, since the empty-events case above already handled
// the only way there could be zero.
        events.do { |ev, i| if(ev[\role] == startRole) { startIdx = startIdx.add(i) } };

// \halfway triggers TWICE a bar - once at beat 0 (same as \firstBeat) AND
// once at beat (events.size/2).floor - per feedback correcting an earlier
// version that only fired at the halfway point alone (once a bar, same
// cadence as \firstBeat, just offset - not what "plays twice a bar" means).
        baseSlotIdx = switch(pattern,
            \firstBeat, { [0] },
            \halfway, { [0, (events.size / 2).floor] },
            { startIdx }
        );

// Generalizes every other builder's own nextIdx-idx gap computation: the
// LAST trigger's gap wraps to the FIRST trigger of the NEXT cycle
// (baseSlotIdx[0] beats into that next bar), not just to the end of this
// bar's array - the two only coincide when baseSlotIdx[0] is 0, true for
// every one of these three patterns now (including \halfway, now that its
// own first trigger is beat 0 too) - kept general rather than special-cased
// away, in case a future Dur Pat choice ever starts mid-bar again.
        durs = baseSlotIdx.collect { |idx, i|
            var nextIdx = if((i + 1) < baseSlotIdx.size) {
                baseSlotIdx[i + 1]
            } {
                events.size + baseSlotIdx[0]
            };
            nextIdx - idx
        };

// A Pbind's own \dur sequence only encodes the GAP between triggers - it
// has no idea what absolute beat the stream actually started on (that's
// set by .play's own quant, CT8tracks.scd's ~syncTrackPlayer), so `durs`
// alone would just repeat starting from WHATEVER beat playback happened to
// begin, not from baseSlotIdx[0] specifically. For \firstBeat/\startOnly
// that's a no-op (their own first trigger is always beat 0 - the same
// baseSlotIdx[0]==0 case ~auxSendPbindArgs's own comment, above, already
// relies on), but \halfway's one trigger sits mid-bar, so without a
// leading offset it fires at whatever beat the stream started (typically
// bar-start, i.e. indistinguishable from \firstBeat) instead - confirmed
// by feedback ("i don't hear droneChord change at half way - it only
// seems to change at first of beat... confirmed by postln"). `leadIn`
// beats of silence, inserted once before the repeating cycle, fixes this;
// `isLeadInEvent` (consumed by \type, below) marks that one extra event as
// a rest so it doesn't also spawn a synth.
        leadIn = baseSlotIdx[0];
        isLeadInEvent = (leadIn > 0);

// Pitch generator setup, once per rebuild - same "stateful generator built
// once, called once per trigger" convention as ~makeRisingPitchGen/
// ~makeFallingPitchGen (CT8harmonySelect.scd) elsewhere in this file.
// \fixed resolves its one voicing right here (deterministic for the whole
// bar, recomputing it per trigger would just waste a random pick for the
// same answer); \random re-rolls a fresh independent voicing every
// trigger instead, inside voicingFor below.
        if(pitchMode == \fixed) {
            fixedVoicing = Array.fill(numVoices, { ~chordNoteInRange.(~currentChord, lo, hi) }).sort;
        };
        if(pitchMode == \rising) {
            voiceGen = ~makeChordVoiceGen.(~currentChord, ~currentKey, numVoices, lo, hi, 1);
        };
        if(pitchMode == \falling) {
            voiceGen = ~makeChordVoiceGen.(~currentChord, ~currentKey, numVoices, lo, hi, -1);
        };
        voicingFor = {
            switch(pitchMode,
                \fixed, { fixedVoicing },
                \rising, { voiceGen.value },
                \falling, { voiceGen.value },
                { Array.fill(numVoices, { ~chordNoteInRange.(~currentChord, lo, hi) }).sort }
            )
        };

// \note1's Pfunc computes (or advances) the WHOLE voicing once per trigger
// and caches it in currentVoicing; \note2 onward just index into that same
// cached array rather than each calling voicingFor independently (which
// would advance/re-roll it once per note instead of once per trigger) -
// safe because Pbind evaluates one event's keys in the order they're given
// here, so \note1 always runs first for a given event, before \note2 etc
// for that SAME event. Still computed on the lead-in rest event too,
// rather than skipped - that event's own \note1-N values never actually
// sound (\type below marks it \rest), and skipping it would leave
// currentVoicing nil for \note2-N's own Pfuncs to index into. A temporary
// console postln lived here briefly as a debugging aid (per feedback,
// "please post the notes in its chord each time they change") - removed
// again once it had served its purpose (per feedback, "turn off the
// chord postln").
        noteArgs = [\note1, Pfunc { currentVoicing = voicingFor.value; currentVoicing[0] }]
            ++ (2..numVoices).collect { |n|
                [("note" ++ n).asSymbol, Pfunc { currentVoicing[n - 1] }]
            }.flatten;

        ~trackPatterns[name] = Pbind(*([
            \instrument, instrument,
// Leading `leadIn`-beat rest before the repeating cycle, only when needed
// (see `leadIn`'s own comment, above) - \firstBeat/\startOnly have
// leadIn==0, so this is unchanged from a plain Pseq(durs, inf) for them.
            \dur, if(leadIn > 0) { Pseq([leadIn], 1) ++ Pseq(durs, inf) } { Pseq(durs, inf) }
        ] ++ noteArgs ++ [
            envKeys[0], Pfunc { |ev| ((ev[\dur] + 2) / t.tempo) * 0.15 },
            envKeys[1], Pfunc { |ev| ((ev[\dur] + 2) / t.tempo) * 0.45 },
            envKeys[2], Pfunc { |ev| ((ev[\dur] + 2) / t.tempo) * 0.40 },
            \out, 0,
// \type goes to \rest for the one-off lead-in event above (consumed here,
// not re-fired on later cycles - isLeadInEvent flips false right after) or
// whenever ~trackEnabled[name] is off - the standard Event mechanism for
// "build this event's other keys as normal, but don't spawn a synth for
// it," same convention ~buildPercPattern/~buildMonoTrackPattern already
// use. Previously missing entirely here, so HT1/HT2's own on/off toggle
// never actually silenced them - found and fixed alongside the lead-in
// bug above since both touch this same event structure.
            \type, Pfunc {
                var isRest = isLeadInEvent or: { ~trackEnabled[name].not };
                isLeadInEvent = false;
                if(isRest) { \rest } { \note }
            }
        ] ++ ~auxSendPbindArgs.(name) ++ ~labOverrideArgs.(instrument)));
    };
};


// MT1/MT2 used to have their own bespoke builder here (~buildMelodyPattern -
// one slot per \columnStart, hand-tuned FM voicing, a 4-note chord stab
// before that) - per feedback, BT1/BT2/MT1/MT2 are now four
// interchangeable "Note tracks" differing only in which options
// they're set to, so MT1/MT2 are registered below with the exact same
// ~buildMonoTrackPattern every one of the four now shares (see the MONO
// TRACK CONFIG section's own comment, above, for the full
// explanation) rather than a separate builder of their own.


// ---------------------------------------------------------------------------
// TRACK COPY ("Copy T") - BT1/BT2/MT1-4 ONLY
// ---------------------------------------------------------------------------
// Lets one Note track quote another (or itself)'s recent output
// verbatim: ~copyTStartRecord.(sourceName, beats) tapes that track's actual
// sounding (dur, midinote) pairs for the next `beats` TempoClock beats;
// ~copyTStartPlayback.(destName) then has `destName` play that taped buffer
// back in place of its own normal pattern - same instrument/amp/wet/pan/
// everything else about it, just borrowed timing+pitch. Restricted to
// BT1/BT2/MT1-4 (per feedback), not HT1-4/PT1-4 -
// Note tracks are all single-note-per-event (see the MONO TRACK CONFIG
// section's own comment, above), so a (dur, midinote) pair means the same
// thing on either side of a copy; HT1-4 plays chords (an Array, not a
// scalar, \midinote) and PT1-4's pitch is Hz, not MIDI - neither fits
// this scheme without a redesign this feature doesn't attempt.
//
// Now has a real GUI - ONE shared, dual-purpose button per
// ~copyGuiTracks track (reads "Copy Track" or "Play Copy" depending on
// role - ~copyButtonLabelFor, below), plus a Playback timing menu and a
// Stop Playback button, in each track's own block
// (CT8guiPercGenerator.scd/CT8guiHarmonyMelodyGenerator.scd - see
// ~copyTrackButtonPressed/~copyPlayButtonPressed/~copyPlaybackMenuAction/
// ~copyStopPlaybackPressed, below, for what each does), on top of the
// original GUI-less ~copyTStartRecord/~copyTStartPlayback pair, which
// those four build on rather than replace. Per feedback, several
// behaviors changed along with the GUI's arrival, on both the recording
// and playback sides: (1) a GUI-triggered recording always starts on the
// source's own next bar boundary, never immediately on click, and always
// tapes exactly one bar (~numBeats beats) - ~copyTStartRecord itself is
// unchanged and still starts immediately for any `beats` count if called
// directly; (2) GUI-triggered playback is a two-step arm-then-choose
// flow, per feedback correcting an earlier one-step design: clicking the
// button (now showing "Play Copy" for this role) just arms the track and
// waits - it's the SEPARATE Playback dropdown choice, made afterward,
// that actually computes a delay and schedules the start, on the
// destination's next bar, next row/col start, or next beat; (3)
// GUI-triggered playback LOOPS the copied bar indefinitely rather than
// playing it once - Stop Playback ends the loop, but only once the
// CURRENT pass finishes, never mid-buffer. Still one
// active recorder/one active copy-SOURCE at a time (per feedback, "I will
// want to be able to copy only 1 track at a time") - ~copySourceTrack,
// below, is what the GUI enforces that through - but any number of
// simultaneous playback consumers, same as before: each one snapshots
// ~copyBuffer (the last COMPLETED recording) into its own
// ~copyPlayBuffer[name] the moment ITS playback starts, then drains that
// private copy at its own pace via its own ~copyPlayIdx[name], so a LATER
// recording finishing and replacing the shared ~copyBuffer can never
// disturb a playback already under way elsewhere.
//
// Rests are deliberately NOT captured (per feedback) - the tap only fires
// for an actual sounding hit (ev[\type] != \rest), so a recording's own
// internal timing is denser than the real elapsed time it was captured
// over; `beats` only bounds how long the RECORDER listens, not how many
// beats the resulting buffer takes to play back.
//
// Note-cutoffs are the one thing explicitly asked to be handled carefully
// here: recording never truncates a note mid-flight to land exactly on
// the `beats` boundary - the countdown is only checked AFTER a hit's own
// duration has already been subtracted, so the last note captured always
// finishes naturally. Playback never interrupts a note mid-flight either -
// each override swaps in a COMPLETE (dur, midinote) pair at an event
// boundary (a Pbind only ever asks for \dur/\midinote once per event, not
// mid-event), so handing control back to the normal pattern once a
// stopped loop's current pass finishes always happens cleanly between
// notes, never inside one.
~copyEligibleTracks = [\BT1, \BT2, \MT1, \MT2, \MT3, \MT4];
// The subset of ~copyEligibleTracks that actually has Copy Track UI
// (Percussion + Bass Generator/Harmony + Melody Generator windows) - per
// feedback, MT3/MT4 are unused now (melody reduced to MT1/MT2 only), so
// they stay copy-eligible at the data-model level (harmless) but never get
// a button, menu, or Stop control of their own.
~copyGuiTracks = [\BT1, \BT2, \MT1, \MT2];

~copyRecording = false;        // true while ~copyRecordSource is being taped
~copyRecordSource = nil;       // track name currently being recorded
~copyRecordBeatsLeft = 0;      // counts down by each captured hit's own \dur
~copyRecordingBuffer = [];     // being built live, while ~copyRecording
~copyBuffer = [];              // last COMPLETED recording - what playback reads

// ~copySourceTrack - the ~copyGuiTracks name currently selected as the
// Copy Track source (its button shows orange or green), or nil if none.
// Per feedback ("I will want to be able to copy only 1 track at a time"),
// only one of the four buttons is ever selected - ~copyTrackButtonPressed,
// below, is what enforces that by reassigning this on every click rather
// than each button tracking its own independent state.
~copySourceTrack = nil;
// ~copyArmedSource - non-nil from the moment a Copy Track button is
// clicked until the scheduled "next bar" callback actually starts the
// tape (~copyTStartRecord) - per feedback, recording never starts the
// instant you click; it waits for the source's own next bar boundary,
// THEN tapes exactly one full bar. Both ~copyArmedSource and an in-progress
// ~copyRecording display as the same orange "copying" button state (see
// ~copyButtonStateFor, below) - there's no separate visual for "waiting to
// start" vs. "actively taping," only "not yet ready."
~copyArmedSource = nil;
// name -> true while that destination's own loop-playback has been asked
// to stop - checked only at the moment one full pass through
// ~copyPlayBuffer[name] completes (~makeCopyAwarePair, below), so the
// CURRENT loop always finishes cleanly rather than cutting off mid-buffer,
// per feedback ("finishes the current loop and goes back to what it was
// doing").
~copyStopRequested = ~copyStopRequested ? ();
// name -> true while a playback start has been scheduled (one of the
// Next Bar/Next Row-Col/Next Beat menu choices) but hasn't fired yet -
// lets Stop Playback cancel a pending start, not just an already-looping
// one, and lets the GUI show the Stop button as live the instant the menu
// is used rather than only once sound actually begins.
~copyPlayStartArmed = ~copyPlayStartArmed ? ();
// name -> a zero-arg function that redraws that track's own Copy Track
// button/menu/Stop button from the current global state - registered by
// whichever window last built that track's block (BT1/BT2 in
// CT8guiPercGenerator.scd, MT1/MT2 in CT8guiHarmonyMelodyGenerator.scd),
// so ~refreshAllCopyButtons (below) can update every track's widgets from
// ONE call regardless of which of the two windows/files actually owns
// each one - the cross-window coordination this feature needs, since
// clicking BT1's button must also visually reset MT1/MT2's buttons even
// though they live in a different window entirely.
~copyButtonRefreshers = ~copyButtonRefreshers ? ();

~copyPlaying = ~copyPlaying ? ();   // name -> true while draining its ~copyPlayBuffer
// name -> the buffer THIS track is currently draining - snapshotted from
// ~copyBuffer at the moment its playback starts (~copyTStartPlayback,
// below), not read live from ~copyBuffer - so a LATER recording finishing
// and replacing ~copyBuffer can never corrupt a playback already in
// progress elsewhere.
~copyPlayBuffer = ~copyPlayBuffer ? ();
// name -> this track's own position in ~copyPlayBuffer[name] - a GLOBAL,
// not a Pbind-local var, so a rebuild mid-playback (minute change, Apply
// now) resumes where it left off rather than restarting from scratch.
~copyPlayIdx = ~copyPlayIdx ? ();
~copyEligibleTracks.do { |name|
    ~copyPlaying[name] = ~copyPlaying[name] ? false;
    ~copyPlayBuffer[name] = ~copyPlayBuffer[name] ? [];
    ~copyPlayIdx[name] = ~copyPlayIdx[name] ? 0;
    ~copyStopRequested[name] = ~copyStopRequested[name] ? false;
    ~copyPlayStartArmed[name] = ~copyPlayStartArmed[name] ? false;
};

// ~refreshAllCopyButtons - calls every registered ~copyButtonRefreshers
// closure, so a change to the shared Copy Track state (a click, a
// scheduled start/stop firing) redraws every track's widgets at once,
// across both windows. Safe to call from any thread (each refresher
// itself is responsible for `.defer`ring its own GUI writes - see
// makeMonoTrackSection's own copy of it, CT8guiPercGenerator.scd/
// CT8guiHarmonyMelodyGenerator.scd), so callers inside a Pbind's Pfunc
// (the audio/pattern thread, not the GUI thread) can call this directly
// without wrapping it themselves.
~refreshAllCopyButtons = {
    ~copyButtonRefreshers.keysValuesDo { |name, fn| if(fn.notNil) { fn.value } };
};

// ~copyButtonLabelFor.(name) - the ONE shared button each ~copyGuiTracks
// track has is dual-purpose, per feedback: it reads "Copy Track" for
// whichever track either IS the current source, or could become one (no
// completed recording exists yet at all, so every track is still a
// candidate); it switches to "Play Copy" for every OTHER track, but only
// once a completed ~copyBuffer actually exists to play - before that,
// every track still reads "Copy Track," since there's nothing yet for
// anyone to play. This is what the button's own .action_ (both
// ~copyTrackButtonPressed and ~copyPlayButtonPressed, below) dispatches
// on, and what refreshCopyUi (CT8guiPercGenerator.scd/
// CT8guiHarmonyMelodyGenerator.scd) rebuilds the button's .states_ text
// from every time.
~copyButtonLabelFor = { |name|
    if(name == ~copySourceTrack) {
        "Copy Track";
    } {
        if(~copyBuffer.notEmpty) { "Play Copy" } { "Copy Track" };
    };
};

// ~copyButtonStateFor.(name) - the button's COLOR, which depends on
// whichever of the two roles ~copyButtonLabelFor says is currently active:
// for the "Copy Track" role, \idle (not the selected source), \copying
// (selected, but either still waiting for the next bar or actively taping
// it - both look the same, orange), or \ready (selected, and the one-bar
// recording has completed - green); for the "Play Copy" role, \idle (not
// yet armed), \copying (armed via ~copyPlayButtonPressed, waiting on a
// Playback menu choice, or that choice made and a start scheduled but not
// yet arrived - again, both look the same, orange), or \ready (actually
// looping - green). Pure function of the shared globals above; called by
// each track's own refresher to decide its button color.
~copyButtonStateFor = { |name|
    if(~copyButtonLabelFor.(name) == "Copy Track") {
        if(~copySourceTrack != name) {
            \idle;
        } {
            if(~copyArmedSource == name or: { ~copyRecording and: { ~copyRecordSource == name } }) {
                \copying;
            } {
                \ready;
            };
        };
    } {
        if(~copyPlaying[name]) {
            \ready;
        } {
            if(~copyPlayStartArmed[name]) { \copying } { \idle };
        };
    };
};

// ~copyBeatsUntilNextBar - how many TempoClock beats from right now until
// the next bar boundary (the same ~numBeats-long cycle ~checkForNewChordBar,
// CT8harmonySelect.scd, already advances ~currentChord on - reused here
// rather than tracking a second, separate bar counter). 0 if we happen to
// already be exactly on one.
~copyBeatsUntilNextBar = {
    var n = (~numBeats ? 1).max(1);
    (n - (~chordBarBeatCount ? 0)) % n;
};

// ~copyBeatsUntilNextRowCol.(source) - how many beats from right now until
// the next \rowStart (source == \row) or \columnStart (source == \col)
// event in ~rowPattern/~colPattern (CT8guiClock.scd) - wrapping into the
// FOLLOWING bar's first start if the current bar has no more left. Each
// event in those arrays is exactly one beat (its array index IS its beat
// offset within the bar - the same convention ~buildPercPattern/
// ~buildMonoTrackPattern's own `startIdx` already relies on), so no \dur
// summing is needed, just the index.
~copyBeatsUntilNextRowCol = { |source|
    var pattern = if(source == \row) { ~rowPattern ? [] } { ~colPattern ? [] };
    var startRole = if(source == \row) { \rowStart } { \columnStart };
    var n = (~numBeats ? 1).max(1);
    var cur = ~chordBarBeatCount ? 0;
    var startOffsets = [];
    pattern.do { |ev, i| if(ev[\role] == startRole) { startOffsets = startOffsets.add(i) } };
    if(startOffsets.isEmpty) {
        n;
    } {
        var future = startOffsets.select { |o| o > cur };
        if(future.notEmpty) { future.minItem - cur } { (n - cur) + startOffsets.minItem };
    };
};

// ~copyTrackButtonPressed.(name) - the Copy Track button's own .action_,
// shared by all four ~copyGuiTracks. Per feedback: clicking any one of the
// four (even the already-selected one, to re-arm a fresh recording)
// immediately claims the source role and cancels whatever the PREVIOUS
// source was doing - an in-progress recording is simply abandoned (never
// written to ~copyBuffer, so the last COMPLETED recording survives
// untouched), and a stale ~copyArmedSource for a different name will just
// fail its own `~copyArmedSource == name` check, below, once its own
// scheduled callback eventually fires, so there's nothing to explicitly
// cancel there either.
~copyTrackButtonPressed = { |name|
    var delay;
    if(~copyRecording and: { ~copyRecordSource != name }) { ~copyRecording = false };
    ~copySourceTrack = name;
    ~copyArmedSource = name;
    ~refreshAllCopyButtons.value;
    delay = ~copyBeatsUntilNextBar.value;
    t.sched(delay, {
        if(~copyArmedSource == name) {
            ~copyArmedSource = nil;
            ~copyTStartRecord.(name, ~numBeats ? 1);
            { ~refreshAllCopyButtons.value }.defer;
        };
        nil;
    });
};

// ~copyPlayButtonPressed.(name) - the SAME shared button's .action_ when
// it's currently showing "Play Copy" (~copyButtonLabelFor, above) rather
// than "Copy Track." Per feedback: clicking it just arms this track
// (orange) and waits for a choice from the Playback dropdown - it doesn't
// schedule anything by itself. ~copyPlaybackMenuAction, below, is what
// actually computes the delay and calls t.sched, and only does so once
// this flag is already true.
~copyPlayButtonPressed = { |name|
    ~copyPlayStartArmed[name] = true;
    ~refreshAllCopyButtons.value;
};

// ~copyPlaybackMenuAction.(destName, source, choice) - the Playback timing
// dropdown's own .action_ for one of the three non-source tracks; `source`
// is that track's OWN current ~monoSource[destName] (\row or \col),
// snapshotted at selection time, not re-read later, so the delay computed
// now and whatever ~copyBeatsUntilNextRowCol actually waits for always
// agree even if the Source menu is changed again before the scheduled
// moment arrives. `choice` is \nextBar/\nextRowCol/\nextBeat. Per
// feedback, correcting an earlier design where selecting a menu item was
// itself the start trigger: the dropdown only does anything once
// ~copyPlayStartArmed[destName] is ALREADY true, i.e. ~copyPlayButtonPressed
// (the "Play Copy" button, above) has already been clicked first - picking
// a menu item before that is a no-op (just a warning in the post window),
// since there's nothing yet to schedule a start for.
~copyPlaybackMenuAction = { |destName, source, choice|
    if(~copyPlayStartArmed[destName].not) {
        ("Copy: click Play Copy on % first, then pick a timing.".format(destName)).warn;
    } {
        var delay = switch(choice,
            \nextBar, { ~copyBeatsUntilNextBar.value },
            \nextRowCol, { ~copyBeatsUntilNextRowCol.(source) },
            \nextBeat, { 1 }
        );
        t.sched(delay, {
            if(~copyPlayStartArmed[destName]) {
                ~copyPlayStartArmed[destName] = false;
                ~copyTStartPlayback.(destName);
                { ~refreshAllCopyButtons.value }.defer;
            };
            nil;
        });
    };
};

// ~copyStopPlaybackPressed.(name) - the Stop Playback button's own
// .action_. If already looping, just raises the flag ~makeCopyAwarePair
// checks at the next loop-wrap (below) so the CURRENT pass finishes
// cleanly; if only ARMED (waiting for its scheduled start, never actually
// sounded yet), there's no loop in progress to let finish, so this cancels
// the pending start outright instead.
~copyStopPlaybackPressed = { |name|
    if(~copyPlaying[name]) {
        ~copyStopRequested[name] = true;
    } {
        ~copyPlayStartArmed[name] = false;
    };
    ~refreshAllCopyButtons.value;
};

~copyTStartRecord = { |sourceName, beats|
    if(~copyEligibleTracks.includes(sourceName).not) {
        ("Copy: % is not a Note track - ignoring record request.".format(sourceName)).warn;
    } {
        ~copyRecording = true;
        ~copyRecordSource = sourceName;
        ~copyRecordBeatsLeft = beats;
        ~copyRecordingBuffer = [];
        ("Copy: recording % for % beats.".format(sourceName, beats)).postln;
    };
};

// ~copyOctaveShiftFor.(note, range) - per feedback, the source and
// destination tracks' own Pitch ranges (~currentRange[name]) are likely
// different, so playing a recorded buffer back verbatim could land it far
// outside the destination's intended register. Rather than touching every
// note individually (which would also distort the recorded phrase's own
// internal intervals), this finds the single octave transposition (a
// multiple of 12 semitones, up or down) that brings `note` - always the
// buffer's own FIRST note, in practice - nearest the CENTER of `range`
// ([lo, hi]), then that one shift gets applied to every note in the
// buffer, below, preserving the phrase's shape exactly. Per feedback,
// this deliberately does NOT clamp or re-check any of the OTHER notes
// against `range` afterward - a recorded phrase spanning more than an
// octave can still land partly outside it; only the first note's own
// octave placement is considered.
~copyOctaveShiftFor = { |note, range|
    var mid = (range[0] + range[1]) / 2;
    ((mid - note) / 12).round * 12;
};

~copyTStartPlayback = { |destName|
    if(~copyEligibleTracks.includes(destName).not) {
        ("Copy: % is not a Note track - ignoring playback request.".format(destName)).warn;
    } {
        if(~copyBuffer.isEmpty) {
            ("Copy: no completed recording yet - ignoring playback request for %.".format(destName)).warn;
        } {
            var shift = ~copyOctaveShiftFor.(~copyBuffer[0][1], ~currentRange[destName] ? [0, 127]);
            ~copyPlayBuffer[destName] = ~copyBuffer.collect { |pair| [pair[0], pair[1] + shift] };
            ~copyPlayIdx[destName] = 0;
            ~copyPlaying[destName] = true;
// Guards against a stale true left over from some earlier, unrelated
// stop - a fresh playback should never inherit a pending stop it never
// asked for.
            ~copyStopRequested[destName] = false;
            ("Copy: % now playing back the % recorded notes, shifted % semitones to fit its own pitch range.".format(destName, ~copyBuffer.size, shift)).postln;
        };
    };
};

// Shared by every eligible track's builder - returns [durPfunc, midinotePfunc]
// that transparently splice that track's own ~copyPlayBuffer in whenever
// ~copyPlaying[name] is true, falling back to that track's own normal
// generation (normalDurFunc/normalMidinoteFunc, each a zero-arg function
// returning the next value) otherwise. \dur decides, per event, whether
// this event is an override or not (remembered in usingOverride,
// closure-local since it's recomputed fresh every single event anyway,
// never carried across rebuilds); \midinote reads that same decision a
// moment later, so the two keys never disagree about which source a given
// event came from.
~makeCopyAwarePair = { |name, normalDurFunc, normalMidinoteFunc|
    var usingOverride = false;
    var durFn = {
        if(~copyPlaying[name] and: { ~copyPlayIdx[name] < ~copyPlayBuffer[name].size }) {
            usingOverride = true;
            ~copyPlayBuffer[name][~copyPlayIdx[name]][0];
        } {
            usingOverride = false;
            normalDurFunc.value;
        }
    };
    var midinoteFn = {
        var v;
        if(usingOverride) {
            v = ~copyPlayBuffer[name][~copyPlayIdx[name]][1];
            ~copyPlayIdx[name] = ~copyPlayIdx[name] + 1;
            if(~copyPlayIdx[name] >= ~copyPlayBuffer[name].size) {
                ~copyPlayIdx[name] = 0;
// Per feedback, playback LOOPS indefinitely rather than playing the
// buffer through once - only actually stop (and fall back to this
// track's own normal pattern) once Stop Playback has raised
// ~copyStopRequested[name], and only check that flag right here, at a
// loop-wrap boundary, so the CURRENT pass always finishes cleanly rather
// than cutting off mid-buffer ("finishes the current loop").
                if(~copyStopRequested[name]) {
                    ~copyPlaying[name] = false;
                    ~copyStopRequested[name] = false;
                    ("Copy: % finished its loop and stopped - back to its own pattern.".format(name)).postln;
                    { ~refreshAllCopyButtons.value }.defer;
                };
            };
        } {
            v = normalMidinoteFunc.value;
        };
        v;
    };
    [Pfunc(durFn), Pfunc(midinoteFn)];
};

// The tap every eligible track's Pbind ends with - records the FINAL
// resolved \dur/\midinote for this event (after ~makeCopyAwarePair's own
// override, above, has already had its say - this key is always last), but
// only while THIS track is the one ~copyTStartRecord named, and only for
// an actual sounding hit (rests aren't captured - see this section's own
// header comment). MT1 has no \type key of its own at all (it has no
// per-event rest concept - CT8guiAdjust.scd's on/off button just
// stops/starts its player directly), so ev[\type] there is always Event's
// own default of \note - every MT1 event is "sounding" by construction,
// which is exactly right here too.
~copyTapFor = { |name|
    Pfunc { |ev|
        if(~copyRecording and: { ~copyRecordSource == name } and: { ev[\type] != \rest }) {
            ~copyRecordingBuffer = ~copyRecordingBuffer.add([ev[\dur], ev[\midinote]]);
            ~copyRecordBeatsLeft = ~copyRecordBeatsLeft - ev[\dur];
            if(~copyRecordBeatsLeft <= 0) {
                ~copyRecording = false;
                ~copyBuffer = ~copyRecordingBuffer;
                ("Copy: finished recording % notes from %.".format(~copyBuffer.size, name)).postln;
                { ~refreshAllCopyButtons.value }.defer;
            };
        };
// Never return nil - a Pattern/Stream returning nil means "exhausted," and
// a Pbind stops producing events the moment ANY ONE of its key-patterns
// goes nil. The if above has no else branch, so without this it returns
// nil whenever not actively recording - the normal case - silently ending
// the WHOLE Pbind's stream right after it starts (no error, since a
// stream ending isn't one - this is exactly what broke BT1/BT2/MT1-4 the
// first time this shipped).
        0;
    };
};


// BT1/BT2: the two bass tracks, now driven by the same generic per-track
// Bass Generator config (see that section, above) and the same single-
// source-scan/pre-resolve-the-bar technique ~buildPercPattern uses for
// PT1-4 - replacing BT1's old bespoke builder (a fixed Ppar of row-start AND
// column-start sub-patterns, chord-aware via ~currentChord/
// ~chordNoteInRange) and giving BT2 a real builder for the first time.
// ~monoSource[name] picks ONE scan (row or col), same as PT1-4, rather than
// always running both simultaneously the way the old BT1 did - a track that
// wants both can still be approximated by running BT1 on \row and BT2 on
// \col (their defaults), same net effect as the old single BT1.
//
// No pitchArgName dispatch is needed here the way ~buildPercPattern needs
// one (\baseD/\cym/\hat/\kick each take their pitch in a different Hz-named
// arg) - both \fm/\plucking take a plain \midinote key, which Pbind/Event's
// standard pitch handling converts to \freq for us. No amp-arg-name
// dispatch needed either - both instruments just take a plain \amp key.
~buildMonoTrackPattern = { |name|
    var fromRow = (~monoSource[name] == \row);
    var events = if(fromRow) { ~rowPattern ? [] } { ~colPattern ? [] };
    var startRole = if(fromRow) { \rowStart } { \columnStart };

    if(events.isEmpty) {
        ("No active clock cells to play (" ++ name ++ ").").warn;
        ~trackPatterns[name] = Pbind(\dur, 1, \type, \rest);
    } {
        var startIdx = [];
        var baseSlotIdx;
        var durs = [], pitches = [], restFlags = [], amps = [];
        var beatIndex = 0, ampIndex = 0, nextAmp;
        var instrument = ~monoInstrument[name];
        var pattern = ~monoPattern[name];
        var splitCount, splitVariant, lastOfGroupIdx;
        var isMergePattern, mergeVariant, mergeStart;
        var normalDurStream, normalMidinoteStream, copyPair;

// By construction (same as ~buildPercPattern) there is always at least one
// start event, since the empty-events case above already handled the only
// way there could be zero.
        events.do { |ev, i| if(ev[\role] == startRole) { startIdx = startIdx.add(i) } };

// No \firstBeat option here (per feedback, not a useful choice for a bass
// part) - every pattern except \startOnly starts from the full every-beat
// grid, same as ~buildPercPattern.
        baseSlotIdx = if(pattern == \startOnly) { startIdx } { (0..events.size - 1) };

// ~monoVolumeLevels[name] is [lo, hi] (one dual-handle RangeSlider in the
// GUI, same convention as ~percVolumeLevels) - \fixed reads hi; \alternate
// alternates hi, lo every hit, high end first, same as percussion.
        nextAmp = {
            var lo = ~monoVolumeLevels[name][0];
            var hi = ~monoVolumeLevels[name][1];
            var v = if(~monoVolumeMode[name] == \alternate) {
                if(ampIndex % 2 == 0) { hi } { lo }
            } {
                hi
            };
            ampIndex = ampIndex + 1;
            v;
        };

// Split-type/variant decomposition - identical to ~buildPercPattern's own
// (see its comments for the full explanation of each of these six).
        splitCount = switch(pattern,
            \random8thPercent, { 2 }, \random8thLastBar, { 2 }, \random8thLastRowCol, { 2 },
            \random3rdPercent, { 3 }, \random3rdLastBar, { 3 }, \random3rdLastRowCol, { 3 },
            { 1 }
        );
        splitVariant = switch(pattern,
            \random8thPercent, { \random }, \random3rdPercent, { \random },
            \random8thLastBar, { \lastOfBar }, \random3rdLastBar, { \lastOfBar },
            \random8thLastRowCol, { \lastOfRowCol }, \random3rdLastRowCol, { \lastOfRowCol },
            { \random }
        );
        lastOfGroupIdx = startIdx.drop(1).collect(_ - 1) ++ [events.size - 1];

// The three \random4to3* patterns merge a run of 4 consecutive baseline
// slots into 3 equal-length hits instead of expanding one slot into 2/3 -
// see ~buildPercPattern's own comment (identical mechanism, mirrored here)
// for the full explanation of each variant and why a bar/span shorter than
// 4 slots is simply left unmerged.
        isMergePattern = #[\random4to3Percent, \random4to3LastBar, \random4to3LastRowCol].includes(pattern);
        mergeVariant = switch(pattern,
            \random4to3LastBar, { \lastOfBar },
            \random4to3LastRowCol, { \lastOfRowCol },
            { \random }
        );
        mergeStart = Array.fill(baseSlotIdx.size, { false });
        if(isMergePattern) {
            switch(mergeVariant,
                \random, {
                    var groupStart = 0;
                    while ({ (groupStart + 3) < baseSlotIdx.size }) {
                        if(100.0.rand < ~monoSplitPercent[name]) { mergeStart[groupStart] = true };
                        groupStart = groupStart + 4;
                    };
                },
                \lastOfBar, {
                    if(baseSlotIdx.size >= 4) { mergeStart[baseSlotIdx.size - 4] = true };
                },
                \lastOfRowCol, {
                    startIdx.do { |spanStart, k|
                        var spanEnd = lastOfGroupIdx[k];
                        if((spanEnd - spanStart + 1) >= 4) { mergeStart[spanEnd - 3] = true };
                    };
                }
            );
        };

// Pitch: all three modes read ~currentRange[name] (CT8harmonySelect.scd,
// one dual-handle RangeSlider in the GUI, keyed by this track's own name
// so BT1/BT2 can end up with different ranges) rather than a separate
// ~bassBasePitch. \fixed and \rising are resolved ONCE here, before the
// main loop below, not per-slot inside pitchFor - \fixed because
// ~chordRootInRange is deterministic (recomputing it per slot would just
// give the same answer every time); \rising because ~makeRisingPitchGen
// is a stateful generator that has to keep climbing across the WHOLE bar,
// not restart fresh at every slot. \random still re-picks a chord tone
// via ~chordNoteInRange per slot, same as always - read once per baseline
// slot at rebuild time rather than live per-hit via Pfunc
// (~buildPercPattern's own \random pitch mode works the same way -
// re-rolled fresh each rebuild, not per-hit), so a mid-bar chord change
// (~checkForNewChordBar) isn't heard here until this track's next
// rebuild. pitchFor stays the one thing the main loop below calls either
// way, since a merged group needs its pitch computed just once at the
// group's start slot and reused for all 3 merged hits, same "same pitch
// throughout the group" rule the splits/merges above already use - and,
// per feedback, \rising advances once per BASELINE SLOT this way too
// (every hit in one split/merge group shares its one climb step), not
// once per individual sub-hit; that's a placeholder default pending a
// separate, later pass specifically on how pitch should treat split/merge
// groups.
        {
            var pitchFor, slotI = 0;
            var fixedNote, risingGen, fallingGen, loopingGen;
            if(~monoPitchMode[name] == \fixed) {
                fixedNote = ~chordRootInRange.(~currentChord, ~currentRange[name][0], ~currentRange[name][1]);
            };
            if(~monoPitchMode[name] == \rising) {
                risingGen = ~makeRisingPitchGen.(
                    ~currentChord, ~scales[~chordSet], ~currentRange[name][0], ~currentRange[name][1]
                );
            };
            if(#[
                \arpRising, \arpRisingUp, \arpRisingDown, \arpRisingRan,
                \arpRising3rdRepeat, \arpRising3rdUp, \arpRising3rdDown, \arpRising3rdLop
            ].includes(~monoPitchMode[name])) {
                risingGen = ~makeRisingPitchGen.(
                    ~currentChord, ~chordArpIntervals.(~currentChord),
                    ~currentRange[name][0], ~currentRange[name][1]
                );
            };
            if(~monoPitchMode[name] == \falling) {
                fallingGen = ~makeFallingPitchGen.(
                    ~currentChord, ~scales[~chordSet], ~currentRange[name][0], ~currentRange[name][1]
                );
            };
            if(#[
                \arpFalling, \arpFallingUp, \arpFallingDown, \arpFallingRan,
                \arpFalling3rdRepeat, \arpFalling3rdUp, \arpFalling3rdDown, \arpFalling3rdLop
            ].includes(~monoPitchMode[name])) {
                fallingGen = ~makeFallingPitchGen.(
                    ~currentChord, ~chordArpIntervals.(~currentChord),
                    ~currentRange[name][0], ~currentRange[name][1]
                );
            };
            if(~monoPitchMode[name] == \looping) {
                loopingGen = ~makeLoopingPitchGen.(
                    ~currentChord, ~scales[~chordSet], ~currentRange[name][0], ~currentRange[name][1]
                );
            };
            if(#[
                \arpLooping, \arpLoopingUp, \arpLoopingDown, \arpLoopingRan,
                \arpLooping3rdRepeat, \arpLooping3rdUp, \arpLooping3rdDown, \arpLooping3rdLop
            ].includes(~monoPitchMode[name])) {
                loopingGen = ~makeLoopingPitchGen.(
                    ~currentChord, ~chordArpIntervals.(~currentChord),
                    ~currentRange[name][0], ~currentRange[name][1]
                );
            };
// \arpRising/\arpFalling/\arpLooping share risingGen/fallingGen/loopingGen
// with their plain counterparts - same generator function either way (see
// ~makeRisingPitchGen's own comment, CT8harmonySelect.scd), just built
// above with ~chordArpIntervals.(~currentChord) (the current chord's own
// tones) instead of ~scales[~chordSet] (the current chord's parent
// scale) as the list of offsets to step through. Their own Up/Down/Ran
// sub-variants (1/8th patterns only) and Repeat/Up/Down/Lop sub-variants
// (1/3 patterns only - see the splitPitches comment below for both) all
// resolve this SAME generator call for the first note of a split; the
// sub-variant suffix only matters once the remaining note(s) get derived
// from it, further down.
            pitchFor = { |idx|
                switch(~monoPitchMode[name],
                    \fixed, { fixedNote },
                    \random, { ~chordNoteInRange.(~currentChord, ~currentRange[name][0], ~currentRange[name][1]) },
                    \rising, { risingGen.value },
                    \arpRising, { risingGen.value },
                    \arpRisingUp, { risingGen.value },
                    \arpRisingDown, { risingGen.value },
                    \arpRisingRan, { risingGen.value },
                    \arpRising3rdRepeat, { risingGen.value },
                    \arpRising3rdUp, { risingGen.value },
                    \arpRising3rdDown, { risingGen.value },
                    \arpRising3rdLop, { risingGen.value },
                    \falling, { fallingGen.value },
                    \arpFalling, { fallingGen.value },
                    \arpFallingUp, { fallingGen.value },
                    \arpFallingDown, { fallingGen.value },
                    \arpFallingRan, { fallingGen.value },
                    \arpFalling3rdRepeat, { fallingGen.value },
                    \arpFalling3rdUp, { fallingGen.value },
                    \arpFalling3rdDown, { fallingGen.value },
                    \arpFalling3rdLop, { fallingGen.value },
                    \looping, { loopingGen.value },
                    \arpLooping, { loopingGen.value },
                    \arpLoopingUp, { loopingGen.value },
                    \arpLoopingDown, { loopingGen.value },
                    \arpLoopingRan, { loopingGen.value },
                    \arpLooping3rdRepeat, { loopingGen.value },
                    \arpLooping3rdUp, { loopingGen.value },
                    \arpLooping3rdDown, { loopingGen.value },
                    \arpLooping3rdLop, { loopingGen.value }
                )
            };
            while ({ slotI < baseSlotIdx.size }) {
                if(mergeStart[slotI]) {
                    var groupSpan = 0;
                    var pitch = pitchFor.(baseSlotIdx[slotI]);
                    4.do { |k|
                        var kk = slotI + k;
                        var kIdx = baseSlotIdx[kk];
                        var kNextIdx = if((kk + 1) < baseSlotIdx.size) { baseSlotIdx[kk + 1] } { events.size };
                        groupSpan = groupSpan + (kNextIdx - kIdx);
                    };
                    durs = durs.addAll(Array.fill(3, { groupSpan / 3 }));
                    pitches = pitches.addAll(Array.fill(3, { pitch }));
                    restFlags = restFlags.addAll(Array.fill(3, { false }));
                    amps = amps.addAll(Array.fill(3, { nextAmp.value }));
                    slotI = slotI + 4;
                } {
                    var idx = baseSlotIdx[slotI];
                    var nextIdx = if((slotI + 1) < baseSlotIdx.size) { baseSlotIdx[slotI + 1] } { events.size };
                    var span = nextIdx - idx;
                    var pitch = pitchFor.(idx);
                    var shouldSplit = (splitCount > 1) and: {
                        switch(splitVariant,
                            \random, { 100.0.rand < ~monoSplitPercent[name] },
                            \lastOfBar, { idx == (events.size - 1) },
                            \lastOfRowCol, { lastOfGroupIdx.includes(idx) }
                        )
                    };
                    if(shouldSplit) {
// Per feedback: when the Dur Pat is one of the three 1/8th patterns
// (splitCount == 2) AND the Pit Pat is one of the Arp Rising/Falling/
// Looping Up/Down/Ran sub-variants, the SECOND of the split pair's two
// notes isn't just a repeat of the first - it's derived from it via
// ~chordStepTone (CT8harmonySelect.scd): a tone (2 semitones) in the
// given direction if the current chord has a tone there, else a
// semitone, else the same note repeated after all. Up/Down always step
// that one fixed direction; Ran rerolls a fresh random direction for
// every split pair.
                        var splitDir = switch(~monoPitchMode[name],
                            \arpRisingUp, { 1 }, \arpFallingUp, { 1 }, \arpLoopingUp, { 1 },
                            \arpRisingDown, { -1 }, \arpFallingDown, { -1 }, \arpLoopingDown, { -1 },
                            \arpRisingRan, { [1, -1].choose },
                            \arpFallingRan, { [1, -1].choose },
                            \arpLoopingRan, { [1, -1].choose },
                            { nil }
                        );
// The three 1/3rd patterns (splitCount == 3) get their own four
// sub-variants instead - Repeat/Up/Down/Lop, "very similar to 1/8 BUT"
// (per feedback, correcting an earlier misreading of this same feedback)
// 1/8th moves by a TONE where possible (falling back to a semitone, then
// a repeat - ~chordStepTone), while 1/3rd moves by a SEMITONE where
// possible (falling straight back to a repeat - ~chordSemitoneStep, no
// tone attempt at all; see that function's own bullet, CT8harmonySelect.scd).
// Repeat is an explicit choice that always just repeats the first note
// across all 3 (the plain behavior every Pit Pat had before this whole
// feature), rather than only falling back to a repeat when a step isn't
// available the way Up/Down/Lop do. Up walks UP the triplet two semitone
// steps in a row (note2 from note1, note3 from note2); Down mirrors it
// walking down; Lop arcs up then back down (note2 up from note1, note3
// down from note2) - a little loop/arch shape across the triplet,
// distinct from a straight Up or Down run.
                        var third = switch(~monoPitchMode[name],
                            \arpRising3rdRepeat, { \repeat }, \arpFalling3rdRepeat, { \repeat }, \arpLooping3rdRepeat, { \repeat },
                            \arpRising3rdUp, { \up }, \arpFalling3rdUp, { \up }, \arpLooping3rdUp, { \up },
                            \arpRising3rdDown, { \down }, \arpFalling3rdDown, { \down }, \arpLooping3rdDown, { \down },
                            \arpRising3rdLop, { \lop }, \arpFalling3rdLop, { \lop }, \arpLooping3rdLop, { \lop },
                            { nil }
                        );
// Every other Pit Pat (including the bare, un-suffixed \arpRising/
// \arpFalling/\arpLooping, and every non-Arp mode) falls through to the
// plain "same pitch for every sub-hit" behavior unchanged.
                        var splitPitches = if((splitCount == 2) and: { splitDir.notNil }) {
                            [pitch, ~chordStepTone.(~currentChord, ~currentKey, pitch, splitDir)];
                        } {
                            if((splitCount == 3) and: { third.notNil }) {
                                switch(third,
                                    \repeat, { [pitch, pitch, pitch] },
                                    \up, {
                                        var n2 = ~chordSemitoneStep.(~currentChord, ~currentKey, pitch, 1);
                                        var n3 = ~chordSemitoneStep.(~currentChord, ~currentKey, n2, 1);
                                        [pitch, n2, n3];
                                    },
                                    \down, {
                                        var n2 = ~chordSemitoneStep.(~currentChord, ~currentKey, pitch, -1);
                                        var n3 = ~chordSemitoneStep.(~currentChord, ~currentKey, n2, -1);
                                        [pitch, n2, n3];
                                    },
                                    \lop, {
                                        var n2 = ~chordSemitoneStep.(~currentChord, ~currentKey, pitch, 1);
                                        var n3 = ~chordSemitoneStep.(~currentChord, ~currentKey, n2, -1);
                                        [pitch, n2, n3];
                                    }
                                );
                            } {
                                Array.fill(splitCount, { pitch });
                            };
                        };
                        durs = durs.addAll(Array.fill(splitCount, { span / splitCount }));
                        pitches = pitches.addAll(splitPitches);
                        restFlags = restFlags.addAll(Array.fill(splitCount, { false }));
                        amps = amps.addAll(Array.fill(splitCount, { nextAmp.value }));
                    } {
                        var isSkip = (pattern == \randomSkip) and: { 100.0.rand < ~monoSplitPercent[name] };
                        durs = durs.add(span);
                        pitches = pitches.add(pitch);
                        restFlags = restFlags.add(isSkip);
                        amps = amps.add(nextAmp.value);
                    };
                    slotI = slotI + 1;
                };
            };
        }.value;

// \dur/\midinote go through ~makeCopyAwarePair (TRACK COPY section, above)
// rather than a plain Pseq, so a Copy T playback in progress on this track
// can transparently splice in - the two retained manual streams (not
// re-derived each call) mean pausing them mid-cycle to serve a copy and
// resuming afterward picks up exactly where they left off, same as this
// bar's own normal looping already did before Copy T existed.
        normalDurStream = Pseq(durs, inf).asStream;
        normalMidinoteStream = Pseq(pitches, inf).asStream;
        copyPair = ~makeCopyAwarePair.(name,
            { normalDurStream.next }, { normalMidinoteStream.next }
        );

        ~trackPatterns[name] = Pbind(*([
            \instrument, instrument,
            \dur, copyPair[0],
            \midinote, copyPair[1],
            \amp, Pseq(amps, inf),
// \fx reaches ~clockRev through \fm's real fx/fxsend send (ignored by
// \plucking, which has no \fx arg - its own hardcoded ~revBus send is
// separate and untouched either way); \wet/\level are each instrument's own
// tiny built-in ~allpassWash tail (CT8synths.scd), read live via Pfunc, same
// as ~percWet[name]/~percLevel[name] - the only two Bass Generator controls
// that update immediately with no rebuild/Apply now needed.
            \fx, Pfunc { ~revBus },
            \wet, Pfunc { ~monoWet[name] },
            \level, Pfunc { ~monoLevel[name] },
            \type, Pfunc {
                var isRest = (~trackEnabled[name].not) or: { restFlags[beatIndex] };
                beatIndex = (beatIndex + 1) % restFlags.size;
                if(isRest) { \rest } { \note }
            },
// See the TRACK COPY section, above, for ~copyTapFor.
            \copyTap, ~copyTapFor.(name)
// ~auxSendPbindArgs/~labOverrideArgs (AUX SENDS/SYNTH LAB LIVE OVERRIDES
// sections, above) - every builder in this file appends both the same way.
        ] ++ ~auxSendPbindArgs.(name) ++ ~labOverrideArgs.(instrument)));
    };
};


// Register every track's builder. Adding track N's builder here is the only
// step needed to bring it under the same start/stop/rebuild machinery below.
// PT1-PT4 all share ~buildPercPattern; BT1/BT2/MT1/MT2 all share
// ~buildMonoTrackPattern - the four "Note tracks" (per feedback -
// see that section's own comment, above) - each parameterized per track
// name, each getting its own small wrapper closure so ~trackBuilders
// keeps its existing "one zero-arg function per track name" shape.
~trackBuilders[\PT1] = { ~buildPercPattern.(\PT1) };
~trackBuilders[\PT2] = { ~buildPercPattern.(\PT2) };
~trackBuilders[\PT3] = { ~buildPercPattern.(\PT3) };
~trackBuilders[\PT4] = { ~buildPercPattern.(\PT4) };
~trackBuilders[\HT1] = { ~buildPolyPattern.(\HT1) };
~trackBuilders[\HT2] = { ~buildPolyPattern.(\HT2) };
~trackBuilders[\FXT1] = { ~buildFxPattern.(\FXT1) };
~trackBuilders[\FXT2] = { ~buildFxPattern.(\FXT2) };
~trackBuilders[\BT1] = { ~buildMonoTrackPattern.(\BT1) };
~trackBuilders[\BT2] = { ~buildMonoTrackPattern.(\BT2) };
~trackBuilders[\MT1] = { ~buildMonoTrackPattern.(\MT1) };
~trackBuilders[\MT2] = { ~buildMonoTrackPattern.(\MT2) };

// ---------------------------------------------------------------------------
// START PATTERN
// ---------------------------------------------------------------------------
// Ensure the reverb exists, (re)build every registered track's pattern, and
// start playback for whichever tracks are enabled.
~setStartPbinds = {
    if(~clockRev.isNil or: { ~clockRev.isRunning.not }) {
        ~clockRev = Synth(
            \ELIreverb,
            [\in, ~revBus, \out, 0, \dec, ~reverbDec, \lpf, ~reverbLpf, \mix, ~reverbMix]
        );
    };

    ~trackBuilders.keysValuesDo { |name, builder| builder.value };

    ~trackNames.do { |name|
        if(~trackEnabled[name] and: { ~trackPatterns[name].notNil }) {
            ~trackPlayers[name] = ~trackPatterns[name].play(t, quant: 1);
        };
    };
};


// ---------------------------------------------------------------------------
// STOP PATTERN
// ---------------------------------------------------------------------------
// Stop every track's active EventStreamPlayer and clear its reference.
~stopPbinds = {
    ~trackNames.do { |name|
        if(~trackPlayers[name].notNil) {
            ~trackPlayers[name].stop;
            ~trackPlayers[name] = nil;
        };
    };
};


// ---------------------------------------------------------------------------
// REBUILD PATTERN OBJECTS
// ---------------------------------------------------------------------------
// Rebuild every registered track's Pbind from current input data, without
// starting playback.
~updatePbinds = {
    ~trackBuilders.keysValuesDo { |name, builder| builder.value };
};


// ---------------------------------------------------------------------------
// RESTART CURRENT PATTERNS
// ---------------------------------------------------------------------------
// Defensive stop, then play whichever tracks are enabled.
~restartPbinds = {
    ~stopPbinds.value;

    ~trackNames.do { |name|
        if(~trackEnabled[name] and: { ~trackPatterns[name].notNil }) {
            ~trackPlayers[name] = ~trackPatterns[name].play(t, quant: 1);
        };
    };
};


// ---------------------------------------------------------------------------
// GRADUAL TEMPO CHANGE
// ---------------------------------------------------------------------------
// Move a TempoClock gradually from its current tempo to newTempo BPM.
~tempoChange = { |clock, newTempo, numBeats = 4|
    var i = 0;
// Generate evenly spaced beats/second values between current and target tempos.
    var tempoArray = Array.interpolation(numBeats, clock.tempo, newTempo / 60);

// Apply one interpolation value per beat until the requested number of steps is complete.
    clock.sched(1, {
        clock.tempo = tempoArray[i];
        i = i + 1;
        if(i < numBeats) { 1 } { nil };
    });
};


// ---------------------------------------------------------------------------
// COMPLETE PROJECT CLEANUP
// ---------------------------------------------------------------------------
// Dispose of ClockToy playback, reverb/bus resources, and remaining server nodes.
~stopAll = {
    ~stopPbinds.value;
// Flashing is independent of the track registry now - stop it too.
    if(~stopFlashPlayers.notNil) { ~stopFlashPlayers.value };
// Remove scheduled callbacks from the TempoClock.
    if(t.notNil) { t.clear };
// Free the persistent reverb Synth and clear its interpreter reference.
    if(~clockRev.notNil) { ~clockRev.free; ~clockRev = nil };
// Free the private audio bus used by the reverb path.
    if(~revBus.notNil) { ~revBus.free; ~revBus = nil };
// If scsynth is alive, free all remaining nodes and reset its bus allocators.
    if(s.serverRunning) {
        s.freeAll;
        s.newAllocators;
    };
    "ClockToy engine stopped.".postln;
};

"CT8 track functions loaded.".postln;
)
