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
// shared "current chord" concept HT1/MT1 read live every hit; BT1/BT2 also
// read it, but only for their Random pitch mode, and only once per rebuild
// rather than live - see the Bass Generator config below) to already be
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
//     All ten choices are one flat list in the Percussion Generator (no
//     mode-within-mode submenu) - the split/variant combinations used to be
//     a single \random8th/\random3rd choice plus a separate
//     ~percSplitVariant[name], but that hid five of the six actual
//     behaviors behind an extra menu, so each combination now gets its own
//     top-level entry instead:
//     \firstBeat  - one hit per bar, at the very first beat.
//     \everyBeat  - one hit per beat, no skipping.
//     \startOnly  - one hit at every row/column-start (skips plain cells).
//     \random8thPercent/\random3rdPercent - every beat, but
//       ~percSplitPercent[name]% of them (chosen fresh each rebuild,
//       independently per beat) are replaced by a double hit/triplet - the
//       beat's own span split evenly in two/three, same pitch throughout.
//       The only one of these ten where ~percSplitPercent[name] matters
//       (and the only one the Percussion Generator shows a Percent box
//       for).
//     \random8thLastBar/\random3rdLastBar - same double-hit/triplet split,
//       but deterministic: only the bar's very last beat, always, every
//       bar - no randomness, no percent.
//     \random8thLastRowCol/\random3rdLastRowCol - same split, deterministic,
//       but on the last beat of every row/column span instead - one split
//       per row/col, not just one per bar.
//     \randomSkip - every beat, but ~1/4 of beats (chosen fresh each
//       rebuild) are silent - the beat's span is unchanged, it just doesn't
//       sound. Not affected by ~percSplitPercent - that only applies to the
//       six split patterns above, not to skipping.
//   ~percPitchMode[name]  - how the pitch arg varies hit to hit, and which
//     controls the Percussion Generator window shows for it (only the
//     relevant ones - see CT8guiPercGenerator.scd):
//     \fixed  - always ~percBasePitch[name]. Shows one pitch box.
//     \rising - resets to ~percBasePitch[name] at every start, then adds
//       ~percPitchStep[name] per hit after that. Shows Base pitch/Pitch
//       step, unchanged from before.
//     \random - one of ~percRandomPitches[name]'s 4 values, chosen
//       independently each hit. Shows all 4 pitch boxes, each hand-set -
//       no chord-aware selection yet, that's a planned future step.
//   PITCH/VOLUME REWORK (planned, not started): both ~percPitchMode and
//   ~percVolumeMode above are considered placeholders - something about
//   the Pitch row is currently broken (per feedback, not yet investigated,
//   deliberately deferred) and both are due to be redesigned once the
//   non-percussion tracks (HT1-4/MT1-4) get real chord-based pitch - PT1-4
//   will likely end up picking from a small set of hand-built "chords" per
//   instrument rather than these three modes. Until then, Volume's widgets
//   were updated to Sliders (CT8guiPercGenerator.scd) but the underlying
//   Fixed/Alternate model is unchanged.
//   ~percVolumeMode[name] - how amp varies hit to hit (replaces the old
//     Synth Controls window's per-synth amp slider, now removed - see
//     CLAUDE.md):
//     \fixed     - always ~percVolume[name]. Shows one volume Slider.
//     \alternate - alternates between ~percVolumeLevels[name]'s two values
//       every hit. Shows two volume Sliders.
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
~percPitchStep = ~percPitchStep ? ();
~percRandomPitches = ~percRandomPitches ? ();
~percVolumeMode = ~percVolumeMode ? ();
~percVolume = ~percVolume ? ();
~percVolumeLevels = ~percVolumeLevels ? ();
~percWet = ~percWet ? ();
~percLevel = ~percLevel ? ();
~percSplitPercent = ~percSplitPercent ? ();
~percSourceDefaults = (PT1: \row, PT2: \col, PT3: \row, PT4: \col);
~percInstrumentDefaults = (PT1: \kick, PT2: \baseD, PT3: \hat, PT4: \cym);
// Each instrument's own default pitch-arg value and amp, straight off its
// SynthDef (CT8synths.scd)/Synth Lab specs table (CT8guiSynthLab.scd) -
// baseD/cym's \basefreq, hat's \freq, kick's \drumFreq, all at their
// SynthDef's own default, and amp likewise. Keyed by instrument rather than
// by track so ~percBasePitch/~percVolume's defaults, below, stay correct
// even if ~percInstrumentDefaults is changed later.
~percInstrumentPitchDefaults = (baseD: 55, cym: 300, hat: 4200, kick: 50);
~percInstrumentVolumeDefaults = (baseD: 1, cym: 1, hat: 0.2, kick: 0.5);
~percTrackNames.do { |name|
    ~percSource[name] = ~percSource[name] ? ~percSourceDefaults[name];
    ~percInstrument[name] = ~percInstrument[name] ? ~percInstrumentDefaults[name];
    ~percPattern[name] = ~percPattern[name] ? \everyBeat;
    ~percPitchMode[name] = ~percPitchMode[name] ? \fixed;
    ~percBasePitch[name] = ~percBasePitch[name] ? ~percInstrumentPitchDefaults[~percInstrumentDefaults[name]];
    ~percPitchStep[name] = ~percPitchStep[name] ? 50;
    ~percRandomPitches[name] = ~percRandomPitches[name] ? Array.fill(4, { rrand(100, 600) });
    ~percVolumeMode[name] = ~percVolumeMode[name] ? \fixed;
    ~percVolume[name] = ~percVolume[name] ? ~percInstrumentVolumeDefaults[~percInstrumentDefaults[name]];
    ~percVolumeLevels[name] = ~percVolumeLevels[name] ? [0.5, 0.15];
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
    ~percSource[name] = ~percSourceDefaults[name];
    ~percInstrument[name] = ~percInstrumentDefaults[name];
    ~percPattern[name] = \everyBeat;
    ~percPitchMode[name] = \fixed;
    ~percBasePitch[name] = ~percInstrumentPitchDefaults[~percInstrumentDefaults[name]];
    ~percPitchStep[name] = 50;
    ~percRandomPitches[name] = Array.fill(4, { rrand(100, 600) });
    ~percVolumeMode[name] = \fixed;
    ~percVolume[name] = ~percInstrumentVolumeDefaults[~percInstrumentDefaults[name]];
    ~percVolumeLevels[name] = [0.5, 0.15];
    ~percWet[name] = 0;
    ~percLevel[name] = 1;
    ~percSplitPercent[name] = 33;
};


// ---------------------------------------------------------------------------
// BASS GENERATOR CONFIG (BT1-BT2)
// ---------------------------------------------------------------------------
// Set live by the same "Percussion Generator" window (CT8guiPercGenerator.scd
// - it covers BT1/BT2 too now, at the bottom, below PT1-4). Same idea as the
// Percussion Generator config above - per-track dictionaries keyed by track
// name symbol, read fresh on every rebuild by ~buildBassTrackPattern, below
// - but a few shapes differ, since bass's two instruments (\fm/\plucking)
// aren't percussion's four:
//   - Both \fm/\plucking take a \midinote key directly (Pbind/Event's
//     standard pitch-key handling converts it to \freq for us), so there's
//     no per-instrument pitch-ARG-name dispatch the way baseD/cym/hat/kick
//     need (~buildPercPattern's pitchArgName switch) - ~bassBasePitch/the
//     Random pitch mode's range (below) are both plain MIDI note numbers,
//     not Hz. Both also just take a plain \amp key for their output level,
//     so there's no per-instrument amp-arg-name dispatch needed either
//     (unlike pitch/amp-arg dispatch being two separate concerns for
//     baseD/cym/hat/kick).
//   - Pitch only has two modes (Fixed/Random), not three - no "Rising".
//     Random IS chord-aware (~chordNoteInRange.(~currentChord, ...) - same
//     helper/global HT1/MT1 use, CT8harmonySelect.scd), read once per
//     baseline slot at rebuild time rather than live per-hit; Fixed is a
//     plain MIDI note, not chord-aware. Both Pitch and Volume here are
//     otherwise still placeholders, same status as percussion's own
//     Pitch/Volume, pending the planned rework once chord-based pitch/
//     volume exist generally.
//   - Pattern has no \firstBeat option (per feedback, not a useful choice
//     for a bass part) - otherwise the exact same nine choices PT1-4 have.
~bassTrackNames = [\BT1, \BT2];
~bassSource = ~bassSource ? ();
~bassInstrument = ~bassInstrument ? ();
~bassPattern = ~bassPattern ? ();
~bassPitchMode = ~bassPitchMode ? ();
~bassBasePitch = ~bassBasePitch ? ();
~bassVolumeMode = ~bassVolumeMode ? ();
~bassVolume = ~bassVolume ? ();
~bassVolumeLevels = ~bassVolumeLevels ? ();
~bassWet = ~bassWet ? ();
~bassLevel = ~bassLevel ? ();
~bassSplitPercent = ~bassSplitPercent ? ();
~bassSourceDefaults = (BT1: \row, BT2: \col);
~bassInstrumentDefaults = (BT1: \fm, BT2: \plucking);
// Each instrument's own default amp, straight off its SynthDef
// (CT8synths.scd) - same idea as ~percInstrumentVolumeDefaults, above.
~bassInstrumentVolumeDefaults = (fm: 0.2, plucking: 0.2);
// Random pitch mode's range - anything "below middle C" per feedback (MIDI
// 60), floored at MIDI 12 (the same low end BT1's old chord-aware range
// used) - not user-adjustable yet, unlike percussion's 4 hand-set random
// pitch boxes, since this is explicitly a placeholder (see above).
~bassRandomPitchLo = 12;
~bassRandomPitchHi = 59;
~bassTrackNames.do { |name|
    ~bassSource[name] = ~bassSource[name] ? ~bassSourceDefaults[name];
    ~bassInstrument[name] = ~bassInstrument[name] ? ~bassInstrumentDefaults[name];
    ~bassPattern[name] = ~bassPattern[name] ? \everyBeat;
    ~bassPitchMode[name] = ~bassPitchMode[name] ? \fixed;
    ~bassBasePitch[name] = ~bassBasePitch[name] ? 36;
    ~bassVolumeMode[name] = ~bassVolumeMode[name] ? \fixed;
    ~bassVolume[name] = ~bassVolume[name] ? ~bassInstrumentVolumeDefaults[~bassInstrumentDefaults[name]];
    ~bassVolumeLevels[name] = ~bassVolumeLevels[name] ? [0.2, 0.08];
    ~bassWet[name] = ~bassWet[name] ? 0;
    ~bassLevel[name] = ~bassLevel[name] ? 1;
    ~bassSplitPercent[name] = ~bassSplitPercent[name] ? 33;
};

// Forcibly resets one track's whole Bass Generator config back to these same
// original defaults - mirrors ~resetPercConfig exactly, same reason (see its
// comment, above).
~resetBassConfig = { |name|
    ~bassSource[name] = ~bassSourceDefaults[name];
    ~bassInstrument[name] = ~bassInstrumentDefaults[name];
    ~bassPattern[name] = \everyBeat;
    ~bassPitchMode[name] = \fixed;
    ~bassBasePitch[name] = 36;
    ~bassVolumeMode[name] = \fixed;
    ~bassVolume[name] = ~bassInstrumentVolumeDefaults[~bassInstrumentDefaults[name]];
    ~bassVolumeLevels[name] = [0.2, 0.08];
    ~bassWet[name] = 0;
    ~bassLevel[name] = 1;
    ~bassSplitPercent[name] = 33;
};



~trackNames = [
    \PT1, \PT2, \PT3, \PT4,   // percussion
    \BT1,  \BT2,                    // bass
    \HT1, \HT2, \HT3, \HT4,   // rhythm/harmony
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
// Only PT1/PT2/PT3 default on. PT4/BT1/BT2/HT1/MT1 all have real builders
// too (~buildPercPattern/~buildBassTrackPattern/~buildHarmonyPattern/
// ~buildMelodyPattern) but default off regardless - kept as optional slots
// rather than because they don't exist. Everything else not listed here
// (HT2-4/MT2-4, which genuinely have no builder yet) defaults off for that
// reason instead. All can still be switched on by hand, either in the
// Percussion Generator window (PT1-4/BT1-2) or the Clock Toy Adjust window
// (everything else).
    ~trackEnabled[name] = ~trackEnabled[name] ? (
        (name == \PT1) or: { name == \PT2 } or: { name == \PT3 }
    );
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
// ~percBasePitch/~percPitchStep/~percRandomPitches/~percVolumeMode/
// ~percVolume/~percVolumeLevels/~percWet/~percLevel/~percSplitPercent - see
// PERCUSSION GENERATOR CONFIG, above) through this one parameterized
// builder, registered per track name below.
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
        var baseSlotIdx, basePitches, pitchOffset = 0;
        var durs = [], pitches = [], restFlags = [], amps = [];
        var beatIndex = 0, ampIndex = 0, nextAmp;
        var instrument = ~percInstrument[name];
        var pattern = ~percPattern[name];
        var splitCount, splitVariant, lastOfGroupIdx;
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

// This is the ONLY place pitchOffset changes - resets to 0 whenever a
// baseline slot IS a genuine start, otherwise grows by
// ~percPitchStep[name] when ~percPitchMode[name] is \rising. Computed once
// per baseline slot, before any random splitting below - a slot split into
// a double hit or triplet gives every one of those hits the same pitch,
// rather than advancing mid-split.
        basePitches = baseSlotIdx.collect { |idx|
            var isStart = startIdx.includes(idx);
            if(isStart) {
                pitchOffset = 0;
            } {
                if(~percPitchMode[name] == \rising) {
                    pitchOffset = pitchOffset + ~percPitchStep[name];
                };
            };
            switch(~percPitchMode[name],
                \fixed, { ~percBasePitch[name] },
                \rising, { ~percBasePitch[name] + pitchOffset },
// No chord-aware selection yet (planned) - for now, just one of the 4
// hand-set pitch boxes, picked independently each baseline slot.
                \random, { ~percRandomPitches[name].choose }
            )
        };

// Next hit's \amp, per ~percVolumeMode[name] - \fixed always the same
// value; \alternate flips between ~percVolumeLevels[name]'s two values
// every actual sounding hit (ampIndex counts hits, not baseline slots, so
// a slot split into a double hit/triplet below still alternates hit to
// hit, not just slot to slot).
        nextAmp = {
            var v = if(~percVolumeMode[name] == \alternate) {
                ~percVolumeLevels[name][ampIndex % 2]
            } {
                ~percVolume[name]
            };
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

// Expand each baseline slot into its final hit(s). A slot's span is the gap
// to the next baseline slot, or to the end of the bar for the last one -
// the same row/column-span technique HT1/MT1/BT1 use. The six split
// patterns subdivide a slot's own span into splitCount equal hits instead
// of changing that span, for whichever beats shouldSplit picks (per
// splitVariant - \random re-rolls fresh per slot here at rebuild time, same
// as ~percPitchMode's own \random option; \lastOfBar/\lastOfRowCol are
// deterministic, no rolling involved); \randomSkip keeps one hit per slot
// but may mark it a rest instead.
        baseSlotIdx.do { |idx, i|
            var nextIdx = if((i + 1) < baseSlotIdx.size) { baseSlotIdx[i + 1] } { events.size };
            var span = nextIdx - idx;
            var pitch = basePitches[i];
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
                var isSkip = (pattern == \randomSkip) and: { 1.0.rand < (1/4) };
                durs = durs.add(span);
                pitches = pitches.add(pitch);
                restFlags = restFlags.add(isSkip);
                amps = amps.add(nextAmp.value);
            };
        };

        ~trackPatterns[name] = Pbind(*[
            \instrument, instrument,
            \dur, Pseq(durs, inf),
            pitchArgName, Pseq(pitches, inf),
// Replaces the old Synth Controls window's per-synth amp slider (that
// window is gone - see CLAUDE.md); ~percVolumeMode[name]/~percVolume[name]/
// ~percVolumeLevels[name] (Percussion Generator, this track's own Volume
// row) are the only amp source now.
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
        ]);
    };
};


// HT1: the first harmony track, from an \fm chord patch the user brought in
// from a different app/tempo context. Fixed from the original: ~vbus (never
// defined anywhere in this project) -> ~revBus, wrapped in Pfunc like every
// other \fx use in this file; \dur/\atk/\rel were fixed 1/6-multiples from
// that other app's own tempo, meaningless on this project's TempoClock - now
// \dur is however many ~rowPattern beats the current row actually spans (so
// a new chord lands exactly on each row-start, same grid PT1 plays on), and
// \atk/\rel are computed per-event from that same beat count converted to
// real seconds via t.tempo, so the chord swells in and rings for roughly
// that row's duration rather than a fixed, tempo-unaware length.
//
// \midinote used to be a fixed 3-chord Pseq (chordGroups); now picks 4
// notes from ~currentChord (CT8harmonySelect.scd) instead, any note in the
// three octaves above middle C (MIDI 60-96) via ~chordNoteInRange - a
// Pfunc rather than a Pseq, but fires exactly once per row event either
// way, so the "one new chord at every row-start, held for that row's
// span" cadence is unchanged; only where the 4 notes come from differs.
~buildHarmonyPattern = {
    var events = ~rowPattern ? [];
    if(events.isEmpty) {
        "No active clock cells to play.".warn;
        ~trackPatterns[\HT1] = Pbind(\dur, 1, \type, \rest);
    } {
// Index of every \rowStart event in this cycle - by construction (the scan
// that builds ~rowPattern/~clockEvents always marks a row's first lit cell
// \rowStart) there is always at least one, since the empty-events case above
// already handled the only way there could be zero.
        var rowStartIdx, rowDurs;

        rowStartIdx = [];
        events.do { |ev, i| if(ev[\role] == \rowStart) { rowStartIdx = rowStartIdx.add(i) } };

// Each row's \dur is its span in ~rowPattern beats - the gap to the next
// row-start, or to the end of the array for the last row - so a new chord
// triggers exactly at every row boundary and holds for that row's length.
        rowDurs = rowStartIdx.collect { |idx, i|
            var nextIdx = if((i + 1) < rowStartIdx.size) { rowStartIdx[i + 1] } { events.size };
            nextIdx - idx
        };

        ~trackPatterns[\HT1] = Pbind(
            \instrument, \fm,
            \dur, Pseq(rowDurs, inf),
            \midinote, Pfunc { Array.fill(4, { ~chordNoteInRange.(~currentChord, 60, 96) }) },
            \mRatio, 1,
            \index, 1.5,
            \iScale, Pseq([2, 4], inf),
            \atk, 0.05,
// Real seconds, not beats - EnvGen's env times inside \fm are wall-clock
// seconds regardless of TempoClock tempo, so this converts this event's
// \dur (already resolved above, read back here) via t.tempo (beats/sec).
            \rel, Pfunc { |ev|
                var rowSecs = ev[\dur] / t.tempo;
                (rowSecs - 0.05).max(0.05)
            },
            \cAtk, 0,
            \cRel, 0,
            \amp, 0.027,
            \out, 0,
            \fx, Pfunc { ~revBus },
            \fxsend, -10
        );
    };
};


// MT1: the first melody track, from the by-column scan (mirrors HT1's
// by-row structure exactly, one slot per \columnStart instead of per
// \rowStart - each of the 3 columns per digit panel can have 1-3 lit
// segments ("entries"), but rather than one note per entry, this plays 4
// notes per column-slot, re-rolled live every time (not precomputed once
// per rebuild like HT1's old chordGroups - the melody varies bar to bar
// even when the column layout itself doesn't change this minute). Used to
// pick from a fixed white-keys scale; now picks all 4 from ~currentChord
// (the one shared "current chord" - CT8harmonySelect.scd, read fresh
// every call rather than snapshotted into a local var, so a chord change
// is heard on the very next note), constrained to MIDI 60-96 inclusive
// via ~chordNoteInRange. Doesn't advance ~currentChord itself -
// ~checkForNewChordBar (CT8harmonySelect.scd, scheduled from CT8main.scd)
// does that independently of any one track's Pbind, since nearly every
// track ends up reading ~currentChord and tying the advance to one
// particular track's own beat-counter was an awkward, arbitrary coupling.
~buildMelodyPattern = {
    var events = ~colPattern ? [];
    if(events.isEmpty) {
        "No active clock cells to play.".warn;
        ~trackPatterns[\MT1] = Pbind(\dur, 1, \type, \rest);
    } {
// Index of every \columnStart event in this cycle - mirrors HT1's
// rowStartIdx; always at least one, for the same reason (the empty-events
// case above already handled the only way there could be zero).
        var colStartIdx, colDurs;

        colStartIdx = [];
        events.do { |ev, i| if(ev[\role] == \columnStart) { colStartIdx = colStartIdx.add(i) } };

// Each column's \dur is its span in ~colPattern beats - the gap to the next
// column-start, or to the end of the array for the last column - mirrors
// HT1's rowDurs.
        colDurs = colStartIdx.collect { |idx, i|
            var nextIdx = if((i + 1) < colStartIdx.size) { colStartIdx[i + 1] } { events.size };
            nextIdx - idx
        };

        ~trackPatterns[\MT1] = Pbind(
            \instrument, \fm,
            \dur, Pseq(colDurs, inf),
// Array-valued \midinote (like HT1's \midinote) plays all its notes as one
// simultaneous chord - 4 independent ~chordNoteInRange picks, each its own
// tone-and-octave roll, fresh every time this key is read, rather than a
// fixed precomputed sequence.
            \midinote, Pfunc { Array.fill(4, { ~chordNoteInRange.(~currentChord, 60, 96) }) },
            \mRatio, 2,
            \cRatio, 1,
            \index, 2,
            \iScale, 3,
// Real seconds, not beats - see HT1's identical \rel comment.
            \atk, 0.005,
            \rel, Pfunc { |ev|
                var colSecs = ev[\dur] / t.tempo;
                (colSecs - 0.005).max(0.05)
            },
            \cAtk, 2,
            \cRel, -2,
            \amp, 0.15,
            \pan, 0,
            \out, 0,
            \fx, Pfunc { ~revBus },
            \fxsend, -15
        );
    };
};


// BT1/BT2: the two bass tracks, now driven by the same generic per-track
// Bass Generator config (see that section, above) and the same single-
// source-scan/pre-resolve-the-bar technique ~buildPercPattern uses for
// PT1-4 - replacing BT1's old bespoke builder (a fixed Ppar of row-start AND
// column-start sub-patterns, chord-aware via ~currentChord/
// ~chordNoteInRange) and giving BT2 a real builder for the first time.
// ~bassSource[name] picks ONE scan (row or col), same as PT1-4, rather than
// always running both simultaneously the way the old BT1 did - a track that
// wants both can still be approximated by running BT1 on \row and BT2 on
// \col (their defaults), same net effect as the old single BT1.
//
// No pitchArgName dispatch is needed here the way ~buildPercPattern needs
// one (\baseD/\cym/\hat/\kick each take their pitch in a different Hz-named
// arg) - both \fm/\plucking take a plain \midinote key, which Pbind/Event's
// standard pitch handling converts to \freq for us. No amp-arg-name
// dispatch needed either - both instruments just take a plain \amp key.
~buildBassTrackPattern = { |name|
    var fromRow = (~bassSource[name] == \row);
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
        var instrument = ~bassInstrument[name];
        var pattern = ~bassPattern[name];
        var splitCount, splitVariant, lastOfGroupIdx;

// By construction (same as ~buildPercPattern) there is always at least one
// start event, since the empty-events case above already handled the only
// way there could be zero.
        events.do { |ev, i| if(ev[\role] == startRole) { startIdx = startIdx.add(i) } };

// No \firstBeat option here (per feedback, not a useful choice for a bass
// part) - every pattern except \startOnly starts from the full every-beat
// grid, same as ~buildPercPattern.
        baseSlotIdx = if(pattern == \startOnly) { startIdx } { (0..events.size - 1) };

        nextAmp = {
            var v = if(~bassVolumeMode[name] == \alternate) {
                ~bassVolumeLevels[name][ampIndex % 2]
            } {
                ~bassVolume[name]
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

        baseSlotIdx.do { |idx, i|
            var nextIdx = if((i + 1) < baseSlotIdx.size) { baseSlotIdx[i + 1] } { events.size };
            var span = nextIdx - idx;
// Pitch: Fixed always ~bassBasePitch[name] (plain MIDI note, not
// chord-aware); Random instead picks a tone from ~currentChord
// (CT8harmonySelect.scd) via ~chordNoteInRange, constrained "below middle
// C" (~bassRandomPitchLo..~bassRandomPitchHi, above) - same helper/range
// every other chord-aware track uses, just read once per baseline slot at
// rebuild time rather than live per-hit via Pfunc (~buildPercPattern's own
// \random pitch mode works the same way - re-rolled fresh each rebuild,
// not per-hit), so a mid-bar chord change (~checkForNewChordBar) isn't
// heard here until this track's next rebuild. No \rising mode, so there's
// no pitchOffset bookkeeping to do here the way ~buildPercPattern needs.
            var pitch = if(~bassPitchMode[name] == \random) {
                ~chordNoteInRange.(~currentChord, ~bassRandomPitchLo, ~bassRandomPitchHi)
            } {
                ~bassBasePitch[name]
            };
            var shouldSplit = (splitCount > 1) and: {
                switch(splitVariant,
                    \random, { 100.0.rand < ~bassSplitPercent[name] },
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
                var isSkip = (pattern == \randomSkip) and: { 1.0.rand < (1/4) };
                durs = durs.add(span);
                pitches = pitches.add(pitch);
                restFlags = restFlags.add(isSkip);
                amps = amps.add(nextAmp.value);
            };
        };

        ~trackPatterns[name] = Pbind(*[
            \instrument, instrument,
            \dur, Pseq(durs, inf),
            \midinote, Pseq(pitches, inf),
            \amp, Pseq(amps, inf),
// \fx reaches ~clockRev through \fm's real fx/fxsend send (ignored by
// \plucking, which has no \fx arg - its own hardcoded ~revBus send is
// separate and untouched either way); \wet/\level are each instrument's own
// tiny built-in ~allpassWash tail (CT8synths.scd), read live via Pfunc, same
// as ~percWet[name]/~percLevel[name] - the only two Bass Generator controls
// that update immediately with no rebuild/Apply now needed.
            \fx, Pfunc { ~revBus },
            \wet, Pfunc { ~bassWet[name] },
            \level, Pfunc { ~bassLevel[name] },
            \type, Pfunc {
                var isRest = (~trackEnabled[name].not) or: { restFlags[beatIndex] };
                beatIndex = (beatIndex + 1) % restFlags.size;
                if(isRest) { \rest } { \note }
            }
        ]);
    };
};


// Register every track's builder. Adding track N's builder here is the only
// step needed to bring it under the same start/stop/rebuild machinery below.
// PT1-PT4 all share ~buildPercPattern, BT1-BT2 all share
// ~buildBassTrackPattern, each parameterized per track name - each gets its
// own small wrapper closure so ~trackBuilders keeps its existing "one
// zero-arg function per track name" shape.
~trackBuilders[\PT1] = { ~buildPercPattern.(\PT1) };
~trackBuilders[\PT2] = { ~buildPercPattern.(\PT2) };
~trackBuilders[\PT3] = { ~buildPercPattern.(\PT3) };
~trackBuilders[\PT4] = { ~buildPercPattern.(\PT4) };
~trackBuilders[\HT1] = ~buildHarmonyPattern;
~trackBuilders[\MT1] = ~buildMelodyPattern;
~trackBuilders[\BT1] = { ~buildBassTrackPattern.(\BT1) };
~trackBuilders[\BT2] = { ~buildBassTrackPattern.(\BT2) };

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
