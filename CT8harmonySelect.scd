// ============================================================================
// CT8harmonySelect.scd
// CLOCKTOY - HARMONY/CHORD SELECTION (new, in progress)
// ============================================================================
//
// Owns the shared harmonic concept the rhythm/harmony tracks (HT1-4) are
// meant to generate around: a "current chord" those tracks pick notes
// from, rather than each inventing their own pitch material
// independently. BT1/BT2/MT1/MT2 (the four "Note" tracks - per feedback,
// no longer thought of as separate "bass"/"melody" families) are on the
// generic Mono Track config instead (~buildMonoTrackPattern,
// CT8tracks.scd), the same source/instrument/pattern/pitch/volume scheme
// PT1-4 already use - but still read ~currentChord/~chordNoteInRange/
// ~chordRootInRange/~makeRisingPitchGen from here for their own
// pitch modes, just once per rebuild rather than live per-hit the
// way HT1 does. Not yet wired into every one of HT1-4 - HT1 is the
// only live, per-hit consumer so far.
//
// ~chords[set][chordIndex] is one 3- or 4-note chord, written as real MIDI
// note numbers already in one specific octave (not abstract 0-11 pitch
// classes) - e.g. ~chords[1][1] is [62, 65, 68] (Ddim). Since tracks will
// want notes across a much wider keyboard range than that single octave,
// not just the exact MIDI values stored here, ~chordNoteInRange (below)
// reduces a chosen tone to its pitch class (% 12) first, then picks among
// every octave of that pitch class that falls within the requested range -
// so "which note" and "which octave" are two separate random choices, not
// one. ~currentKey transposes that pitch-class step (every ~chords entry is
// written in the key of C) - a plain semitone offset added before the % 12,
// not multiplied, so the requested range still means exactly what it says
// after transposition. ~currentRange[name] is that requested range itself,
// one [lo, hi] pair per track rather than a literal baked into each
// builder's own ~chordNoteInRange call - see both globals' own comments,
// below, for more.
//

(

~chords = [
    // 1. C Major - 3 note chords
    [
        [60, 64, 67],       // C
        [62, 65, 69],       // Dm
        [64, 67, 71],       // Em
        [65, 69, 72],       // F
        [67, 71, 74],       // G
        [69, 72, 76],       // Am
        [71, 74, 77]        // Bdim
    ],
    // 2. C Minor - 3 note chords
    [
        [60, 63, 67],       // Cm
        [62, 65, 68],       // Ddim
        [63, 67, 70],       // Eb
        [65, 68, 72],       // Fm
        [67, 70, 74],       // Gm
        [68, 72, 75],       // Ab
        [70, 74, 77]        // Bb
    ],
    // 3. C Major - 4 note chords
    [
        [60, 64, 67, 71],   // Cmaj7
        [62, 65, 69, 72],   // Dm7
        [64, 67, 71, 74],   // Em7
        [65, 69, 72, 76],   // Fmaj7
        [67, 71, 74, 77],   // G7
        [69, 72, 76, 79],   // Am7
        [71, 74, 77, 81]    // Bm7b5
    ],
    // 4. C Minor - 4 note chords
    [
        [60, 63, 67, 70],   // Cm7
        [62, 65, 68, 72],   // Dm7b5
        [63, 67, 70, 74],   // Ebmaj7
        [65, 68, 72, 75],   // Fm7
        [67, 70, 74, 77],   // Gm7
        [68, 72, 75, 79],   // Abmaj7
        [70, 74, 77, 80]    // Bb7
    ],
    // 5. C Harmonic Minor - 4 note chords
    [
        [60, 63, 67, 71],   // Cm(maj7)
        [62, 65, 68, 72],   // Dm7b5
        [63, 67, 71, 74],   // Ebmaj7#5
        [65, 68, 72, 75],   // Fm7
        [67, 71, 74, 77],   // G7
        [68, 72, 75, 79],   // Abmaj7
        [71, 74, 77, 80]    // Bdim7
    ],
    // 6. C Melodic Minor - 4 note chords
    [
        [60, 63, 67, 71],   // Cm(maj7)
        [62, 65, 69, 72],   // Dm7
        [63, 67, 71, 74],   // Ebmaj7#5
        [65, 69, 72, 75],   // F7
        [67, 71, 74, 77],   // G7
        [69, 72, 75, 79],   // Am7b5
        [71, 74, 77, 81]    // Bm7b5
    ],
    // 7. C Major - 5 note chords (9ths)
    [
        [60, 64, 67, 71, 74], // Cmaj9
        [62, 65, 69, 72, 76], // Dm9
        [64, 67, 71, 74, 75], // Em7(b9)
        [65, 69, 72, 76, 80], // Fmaj9
        [67, 71, 74, 77, 81], // G9
        [69, 72, 76, 79, 83], // Am9
        [71, 74, 77, 81, 82]  // Bm7b5(b9)
    ],
 
    // 8. C Harmonic Minor - 5 note chords (9ths)
    [
        [60, 63, 67, 71, 74], // Cm(maj9)
        [62, 65, 68, 72, 75], // Dm7b5(b9)
        [63, 67, 71, 74, 77], // Ebmaj7#5(#9)
        [65, 68, 72, 75, 79], // Fm9
        [67, 71, 74, 77, 80], // G9(b9)
        [68, 72, 75, 79, 83], // Abmaj9(#11)
        [71, 74, 77, 80, 84]  // Bdim7(b9)
    ],

    // 9. C Melodic Minor - 5 note chords (9ths)
    [
        [60, 63, 67, 71, 74], // Cm(maj9)
        [62, 65, 69, 72, 76], // Dm9
        [63, 67, 71, 74, 77], // Ebmaj7#5(#9)
        [65, 69, 72, 75, 79], // F9
        [67, 71, 74, 77, 81], // G9
        [69, 72, 75, 79, 83], // Am9b5
        [71, 74, 77, 81, 84]  // Bm7b5(9)
    ]
];

~scales = [
    // 1. C Major - 3 note chords
    [0, 2, 4, 5, 7, 9, 11],

    // 2. C Natural Minor - 3 note chords
    [0, 2, 3, 5, 7, 8, 10],

    // 3. C Major - 4 note chords
    [0, 2, 4, 5, 7, 9, 11],

    // 4. C Natural Minor - 4 note chords
    [0, 2, 3, 5, 7, 8, 10],

    // 5. C Harmonic Minor - 4 note chords
    [0, 2, 3, 5, 7, 8, 11],

    // 6. C Melodic Minor - 4 note chords
    [0, 2, 3, 5, 7, 9, 11],

    // 7. C Major - 5 note chords
    [0, 2, 4, 5, 7, 9, 11],

    // 8. C Harmonic Minor - 5 note chords
    [0, 2, 3, 5, 7, 8, 11],

    // 9. C Melodic Minor - 5 note chords
    [0, 2, 3, 5, 7, 9, 11]
];

// Same [set][chordIndex] shape as ~chords, holding the chord-name strings
// that live as trailing comments next to each ~chords entry above - purely
// for readable logging (~checkForNewChordBar, below), since a comment
// isn't something code can read back at runtime; these two tables have to
// be kept in sync by hand if ~chords ever changes.
~chordNames = [
    // 1. C Major - 3 note chords
    ["C", "Dm", "Em", "F", "G", "Am", "Bdim"],
    // 2. C Minor - 3 note chords
    ["Cm", "Ddim", "Eb", "Fm", "Gm", "Ab", "Bb"],
    // 3. C Major - 4 note chords
    ["Cmaj7", "Dm7", "Em7", "Fmaj7", "G7", "Am7", "Bm7b5"],
    // 4. C Minor - 4 note chords
    ["Cm7", "Dm7b5", "Ebmaj7", "Fm7", "Gm7", "Abmaj7", "Bb7"],
    // 5. C Harmonic Minor - 4 note chords
    ["Cm(maj7)", "Dm7b5", "Ebmaj7#5", "Fm7", "G7", "Abmaj7", "Bdim7"],
    // 6. C Melodic Minor - 4 note chords
    ["Cm(maj7)", "Dm7", "Ebmaj7#5", "F7", "G7", "Am7b5", "Bm7b5"],
    // 7. C Major - 5 note chords (9ths)
    ["Cmaj9", "Dm9", "Em7(b9)", "Fmaj9", "G9", "Am9", "Bm7b5(b9)"],
    // 8. C Harmonic Minor - 5 note chords (9ths)
    ["Cm(maj9)", "Dm7b5(b9)", "Ebmaj7#5(#9)", "Fm9", "G9(b9)", "Abmaj9(#11)", "Bdim7(b9)"],
    // 9. C Melodic Minor - 5 note chords (9ths)
    ["Cm(maj9)", "Dm9", "Ebmaj7#5(#9)", "F9", "G9", "Am9b5", "Bm7b5(9)"]
];

// ~currentKey transposes every ~chords entry (all written in the key of C)
// up by this many semitones; ~keys is purely a name table for logging, the
// same role ~chordNames plays for ~chords - ~keys[~currentKey] is always
// the readable name for whatever ~currentKey currently is, and ~currentKey
// doubles as both the array index into ~keys AND the actual semitone
// offset (~keys[0] = "C" = 0 semitones, ~keys[1] = "C#" = 1 semitone, etc.,
// so no separate offset table is needed). Picking ~currentKey from the last
// two keys via its own Markov chain (mirroring ~chordMarkov) is a planned
// future step - for now it just sits at 0 (C), a complete no-op.
~keys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
~currentKey = 0;

// ~currentRange[name] is the [lo, hi] MIDI bounds ~chordNoteInRange (below)
// picks within, for whichever track `name` is currently rebuilding -
// previously a literal baked directly into each chord-aware track's own
// ~chordNoteInRange call (HT1/MT1: 60-96; BT1/BT2: 12-59, as
// ~bassRandomPitchLo/~bassRandomPitchHi, CT8tracks.scd) - now a live global
// instead, starting at those exact same values, so a future per-bar-varying
// range (some tracks' ranges narrow and fixed, others recalculated every
// bar - not yet designed) only has to reassign this, not touch any
// builder. A `name -> [lo, hi]` dictionary, same convention as every other
// per-track config table in this project (~percX/~monoX, CT8tracks.scd).
~currentRange = ~currentRange ? ();
~currentRange[\HT1] = ~currentRange[\HT1] ? [60, 96];
~currentRange[\HT2] = ~currentRange[\HT2] ? [60, 96];
~currentRange[\HT3] = ~currentRange[\HT3] ? [60, 96];
~currentRange[\HT4] = ~currentRange[\HT4] ? [60, 96];
~currentRange[\MT1] = ~currentRange[\MT1] ? [60, 96];
~currentRange[\MT2] = ~currentRange[\MT2] ? [60, 96];
~currentRange[\MT3] = ~currentRange[\MT3] ? [60, 96];
~currentRange[\MT4] = ~currentRange[\MT4] ? [60, 96];
~currentRange[\BT1] = ~currentRange[\BT1] ? [12, 59];
~currentRange[\BT2] = ~currentRange[\BT2] ? [12, 59];

// Picks one tone from `chord` at random, transposes it by ~currentKey
// semitones, then picks at random again among every octave of that same
// (transposed) pitch class ((tone + ~currentKey) % 12) that falls within
// [lo, hi] inclusive - e.g. chordNoteInRange.([62,65,68], 12, 48) can return
// 14, 26, 38, or 50... clipped to the range, so only 14/26/38 here (50 is
// outside) - with ~currentKey still 0 (C, a no-op) in that example.
// Transposing the pitch class BEFORE picking candidates, rather than adding
// ~currentKey to the final result afterward, is what keeps the result
// genuinely inside [lo, hi] - adding it after could push a result that was
// already at the edge of the range outside it. Called fresh per note (wrap
// the call in a Pfunc inside a Pbind, don't precompute once), so which tone
// AND which octave both re-roll every hit rather than staying fixed for a
// whole bar.
~chordNoteInRange = { |chord, lo, hi|
    var pitchClass = (chord.choose + ~currentKey) % 12;
// lo/hi must be whole numbers for (lo..hi)'s mod-12 matching below to work -
// a non-integer lo (e.g. straight off a RangeSlider's raw linlin output,
// with no .round) shifts every candidate by that same fraction, so `n % 12`
// never exactly equals the integer pitchClass and candidates comes back
// empty every single time, silently (candidates.choose on an empty array
// just returns nil, which then kills the Pbind reading it as \midinote).
// .ceil/.floor here, not .round, so the usable range never extends beyond
// what [lo, hi] actually asked for.
    var loI = lo.ceil.asInteger;
    var hiI = hi.floor.asInteger;
    var candidates = (loI..hiI).select { |n| (n % 12) == pitchClass };
    candidates.choose;
};

// Deterministic sibling of ~chordNoteInRange, for the Fixed and Rising
// pitch modes (~buildMonoTrackPattern, CT8tracks.scd - shared by all four
// Note tracks, BT1/BT2/MT1/MT2) -
// always the chord's own FIRST written note (chord[0], its root in every
// ~chords entry here), transposed by ~currentKey, mapped to the LOWEST
// octave of that pitch class inside [lo, hi] - not a random pick among
// every octave the way ~chordNoteInRange is. Fixed reads this once per
// rebuild and holds it for the whole bar; ~makeRisingPitchGen (below) uses
// it as the climb's own starting point.
~chordRootInRange = { |chord, lo, hi|
    var pitchClass = (chord[0] + ~currentKey) % 12;
    var loI = lo.ceil.asInteger;
    var hiI = hi.floor.asInteger;
    var candidates = (loI..hiI).select { |n| (n % 12) == pitchClass };
    candidates.first;
};

// Returns a stateful zero-arg generator for the Rising pitch mode: call it
// once per hit, in order, across one whole bar - a fresh generator is made
// each rebuild, same as the plain dur/pitch arrays every chord-aware track
// already pre-resolves once per bar. Starts at ~chordRootInRange's own
// note, then each later call climbs one degree further up `intervals` -
// the semitone offsets to step through, extending into higher octaves
// once they're exhausted. The CALLER decides what `intervals` actually is
// - ~scales[~chordSet] (the parent scale for the current chord's own set
// - see ~scales' own header comment, below) for the plain Rising mode;
// ~chordArpIntervals.(chord) (below) for Arp Rising, so this one function
// serves both - the climb mechanics themselves don't care which list of
// offsets they're walking. Once the next degree would
// land above `hi`, the climb wraps back to the start note and begins
// again - "the whole thing starts over," per feedback - rather than
// clamping and staying there the way the OLD (percussion-only) Rising
// pitch mode does. Resets ONLY at the next full bar (a fresh call to this
// function from that track's next rebuild), per feedback - NOT at every
// row/column-start within the bar the way percussion's own Rising does; a
// row/column-boundary-aware version is a planned, separate, future step.
~makeRisingPitchGen = { |chord, intervals, lo, hi|
    var scale = intervals;
    var startNote = ~chordRootInRange.(chord, lo, hi);
    var stepIdx = 0;
    {
        var octave = stepIdx div: scale.size;
        var degree = stepIdx mod: scale.size;
        var candidate = startNote + scale[degree] + (octave * 12);
        if(candidate > hi) {
// Wrap: re-emit the start note and resume climbing from the SECOND degree
// next call, not the first again - otherwise the start note would sound
// twice in a row right at the wrap point.
            candidate = startNote;
            stepIdx = 1;
        } {
            stepIdx = stepIdx + 1;
        };
        candidate;
    };
};

// Falling's own deterministic starting point - the mirror of
// ~chordRootInRange: same chord[0] pitch class, transposed by
// ~currentKey, but the HIGHEST matching octave inside [lo, hi] instead of
// the lowest, since Falling starts at the top of the range and descends.
~chordTopInRange = { |chord, lo, hi|
    var pitchClass = (chord[0] + ~currentKey) % 12;
    var loI = lo.ceil.asInteger;
    var hiI = hi.floor.asInteger;
    var candidates = (loI..hiI).select { |n| (n % 12) == pitchClass };
    candidates.last;
};

// The mirror of ~makeRisingPitchGen, for the Falling pitch mode (Note
// tracks - BT1/BT2/MT1/MT2): starts at ~chordTopInRange's own note (the
// TOP of the range, not the bottom), then each later call descends one
// degree further down `intervals` (~scales[~chordSet] for plain Falling,
// ~chordArpIntervals.(chord) for Arp Falling - same caller-decides
// convention ~makeRisingPitchGen uses), extending into lower octaves
// once they're exhausted. Once the next degree would
// land below `lo`, the descent wraps back to the start note and begins
// again - same "starts over" rule ~makeRisingPitchGen uses, just upside
// down. Same reset rule too: only at the next full bar, never at a
// row/column-start within it.
~makeFallingPitchGen = { |chord, intervals, lo, hi|
    var scale = intervals;
    var startNote = ~chordTopInRange.(chord, lo, hi);
    var stepIdx = 0;
    {
        var octave = stepIdx div: scale.size;
        var degree = stepIdx mod: scale.size;
        var candidate = startNote - scale[degree] - (octave * 12);
        if(candidate < lo) {
            candidate = startNote;
            stepIdx = 1;
        } {
            stepIdx = stepIdx + 1;
        };
        candidate;
    };
};

// Returns a stateful zero-arg generator for the Looping pitch mode (Note
// tracks - BT1/BT2/MT1/MT2), per feedback: starts at ~chordRootInRange's
// own note (same starting point Rising uses), picks a random direction
// (up or down) once, then steps through `intervals` in that direction
// like Rising/Falling do (~scales[~chordSet] for plain Looping,
// ~chordArpIntervals.(chord) for Arp Looping - same caller-decides
// convention the other two generators use) - but instead of wrapping back
// to the
// start once it would go past a bound, it REVERSES direction at whichever
// bound it reaches and continues stepping from there, bouncing back and
// forth between `lo` and `hi` indefinitely. The reversing hit itself
// immediately computes its OWN step in the new direction (rather than
// re-emitting the turning-point note, which would otherwise repeat it
// twice in a row) - `phaseStart`/`stepIdx` get reset to that turning
// point/1 respectively, same "resume from the SECOND step" convention
// ~makeRisingPitchGen/~makeFallingPitchGen use when THEY reset, just
// reversing instead of restarting from the top/bottom. Same reset rule as
// both: only at the next full bar, never at a row/column-start within it.
~makeLoopingPitchGen = { |chord, intervals, lo, hi|
    var scale = intervals;
    var phaseStart = ~chordRootInRange.(chord, lo, hi);
    var dir = [1, -1].choose;
    var stepIdx = 0;
    var lastValue = phaseStart;
    {
        var degree = stepIdx mod: scale.size;
        var octave = stepIdx div: scale.size;
        var candidate = phaseStart + (dir * (scale[degree] + (octave * 12)));
        var outOfBounds = if(dir > 0) { candidate > hi } { candidate < lo };
        if(outOfBounds) {
            dir = dir * -1;
            phaseStart = lastValue;
            stepIdx = 1;
            degree = stepIdx mod: scale.size;
            octave = stepIdx div: scale.size;
            candidate = phaseStart + (dir * (scale[degree] + (octave * 12)));
        };
        stepIdx = stepIdx + 1;
        lastValue = candidate;
        candidate;
    };
};

// The intervals list for the Arp Rising/Arp Falling/Arp Looping pitch
// modes, per feedback - fed into ~makeRisingPitchGen/~makeFallingPitchGen/
// ~makeLoopingPitchGen in place of ~scales[~chordSet], so those three
// generators step through the CURRENT CHORD'S OWN TONES instead of a
// scale's degrees - "same basic idea" as Rising/Falling/Looping, just a
// different list of offsets to walk. Each tone's offset from the chord's
// own root (chord[0]) - e.g. [60, 64, 67] (a major triad) gives
// [0, 4, 7] - deliberately NOT re-transposed by ~currentKey here, since
// ~chordRootInRange/~chordTopInRange (the generators' own starting-point
// functions) already transpose the ROOT itself; adding these untransposed
// relative offsets on top of that already-transposed root still lands on
// the correctly-transposed chord tones, because a fixed interval
// structure (e.g. "major triad = root/major third/fifth") doesn't change
// under transposition. For exactly a 3-note chord, per feedback, the
// root an octave up is appended to the end, turning the 3-note shape into
// a 4-note arpeggio (e.g. [0, 4, 7] -> [0, 4, 7, 12]) - 4- and 5-note
// chords are left as-is, already enough notes on their own.
~chordArpIntervals = { |chord|
    var intervals = chord.collect { |note| note - chord[0] };
    if(chord.size == 3) { intervals = intervals ++ [12] };
    intervals;
};

// ~chordStepTone.(chord, key, note, dir) - the mono Arp pitch modes' own
// "Up"/"Down"/"Ran" sub-variants (CT8tracks.scd's ~buildMonoTrackPattern,
// CT8guiPercGenerator.scd/CT8guiHarmonyMelodyGenerator.scd's pitchMenu) use
// this to derive the SECOND note of a 1/8th-split pair from the first, per
// feedback: try a whole tone (2 semitones) in `dir` (1 up, -1 down) first;
// if the current chord (transposed by `key`, same convention as
// ~chordRootInRange) has no tone at that exact pitch class, fall back to a
// semitone in the same direction; if the chord has no tone there either,
// give up and repeat `note` unchanged, rather than landing on a pitch
// outside the current chord's own structure.
~chordStepTone = { |chord, key, note, dir|
    var chordPitchClasses = chord.collect { |n| (n + key) % 12 };
    var toneCandidate = note + (dir * 2);
    var semitoneCandidate = note + dir;
    if(chordPitchClasses.includes(toneCandidate % 12)) {
        toneCandidate;
    } {
        if(chordPitchClasses.includes(semitoneCandidate % 12)) {
            semitoneCandidate;
        } {
            note;
        };
    };
};

// ~chordSemitoneStep.(chord, key, note, dir) - the mono Arp pitch modes'
// own 1/3rd Up/Down/Lop sub-variants (CT8tracks.scd's
// ~buildMonoTrackPattern) use this instead of ~chordStepTone, per
// feedback correcting an earlier misreading: 1/8th moves by a TONE where
// possible, falling back to a semitone, then a repeat; 1/3rd moves by a
// SEMITONE where possible (no tone attempt at all), falling straight back
// to a repeat if even that isn't a chord tone - "it should play the first
// note, go up a semitone, then another semitone," not a tone followed by
// a semitone. Chaining two calls of this (Up: dir 1 then 1 again from the
// result; Down: -1 then -1 again; Lop: 1 then -1) is what gives a 1/3rd
// triplet its second and third notes.
~chordSemitoneStep = { |chord, key, note, dir|
    var chordPitchClasses = chord.collect { |n| (n + key) % 12 };
    var semitoneCandidate = note + dir;
    if(chordPitchClasses.includes(semitoneCandidate % 12)) {
        semitoneCandidate;
    } {
        note;
    };
};

// ~currentChord is the one shared "current chord". Read LIVE (not
// snapshotted into a local var, so a change is heard on the very next
// note) by ~buildPolyPattern (HT1), CT8tracks.scd; ~buildMonoTrackPattern
// (BT1/BT2/MT1/MT2 - the four Note tracks) also reads it, but only
// once per rebuild - see this
// file's header. Its actual initial value is set below, in INITIAL STATE/
// PIECE START, alongside ~chordSet/~secondLastChord/~lastChord (all four
// need to agree with each other, so they're set together in one place
// rather than this one living separately up here).


// ------------------------------------------------------------
// SECOND ORDER MARKOV TABLE
//
// key = [secondLastChord, lastChord]
//
// value = [
//     possible next chords,
//     corresponding weights
// ]
//
// Chords are numbered 1-7 here.
// ------------------------------------------------------------

~chordMarkov = Dictionary.new;


// ---------- FROM I ----------

~chordMarkov[[1,2]] = [[4,5,6,7], [1,3,1,0.2]];
~chordMarkov[[1,3]] = [[4,6,2,5], [2,3,1,1]];
~chordMarkov[[1,4]] = [[5,2,6,1], [4,1,1,0.5]];
~chordMarkov[[1,5]] = [[1,6,4,3], [5,1,1,0.3]];
~chordMarkov[[1,6]] = [[2,4,5,3], [3,2,2,0.5]];
~chordMarkov[[1,7]] = [[1,3,6],   [4,1,1]];


// ---------- FROM II ----------

~chordMarkov[[2,1]] = [[4,6,5,3], [2,2,1,0.5]];
~chordMarkov[[2,3]] = [[6,4,5],   [3,2,1]];
~chordMarkov[[2,4]] = [[5,1,7],   [4,1,0.5]];
~chordMarkov[[2,5]] = [[1,6,3],   [6,1,0.3]];
~chordMarkov[[2,6]] = [[5,4,2],   [4,2,0.5]];
~chordMarkov[[2,7]] = [[1,5,3],   [3,2,0.5]];


// ---------- FROM III ----------

~chordMarkov[[3,1]] = [[4,6,2,5], [2,2,1,1]];
~chordMarkov[[3,2]] = [[5,4,6],   [3,1,1]];
~chordMarkov[[3,4]] = [[5,1,2],   [4,2,0.5]];
~chordMarkov[[3,5]] = [[1,6,4],   [4,2,1]];
~chordMarkov[[3,6]] = [[2,4,5],   [3,2,1]];
~chordMarkov[[3,7]] = [[1,6,5],   [4,1,1]];


// ---------- FROM IV ----------

~chordMarkov[[4,1]] = [[5,6,2,3], [3,2,1,0.5]];
~chordMarkov[[4,2]] = [[5,7,1],   [4,1,1]];
~chordMarkov[[4,3]] = [[6,2,5],   [3,1,1]];
~chordMarkov[[4,5]] = [[1,6,3],   [7,2,0.3]];
~chordMarkov[[4,6]] = [[2,5,4],   [3,2,1]];
~chordMarkov[[4,7]] = [[1,5,3],   [5,2,0.5]];


// ---------- FROM V ----------

~chordMarkov[[5,1]] = [[4,6,2,3], [3,2,1,0.5]];
~chordMarkov[[5,2]] = [[5,4,7],   [4,1,0.5]];
~chordMarkov[[5,3]] = [[6,4,1],   [3,2,1]];
~chordMarkov[[5,4]] = [[5,1,2],   [4,2,1]];
~chordMarkov[[5,6]] = [[2,4,5],   [3,2,1]];
~chordMarkov[[5,7]] = [[1,6,3],   [5,1,0.5]];


// ---------- FROM VI ----------

~chordMarkov[[6,1]] = [[4,2,5,3], [3,2,1,0.5]];
~chordMarkov[[6,2]] = [[5,4,7],   [5,1,0.5]];
~chordMarkov[[6,3]] = [[4,2,5],   [3,2,1]];
~chordMarkov[[6,4]] = [[5,2,1],   [4,2,1]];
~chordMarkov[[6,5]] = [[1,3,6],   [6,1,0.5]];
~chordMarkov[[6,7]] = [[1,5,3],   [4,2,0.5]];


// ---------- FROM VII ----------

~chordMarkov[[7,1]] = [[4,6,2,5], [3,2,1,1]];
~chordMarkov[[7,2]] = [[5,4,1],   [4,2,1]];
~chordMarkov[[7,3]] = [[6,4,2],   [3,2,1]];
~chordMarkov[[7,4]] = [[5,1,2],   [5,2,1]];
~chordMarkov[[7,5]] = [[1,6,3],   [6,1,0.5]];
~chordMarkov[[7,6]] = [[2,4,5],   [3,2,1]];


// ------------------------------------------------------------
// GET NEXT CHORD
// ------------------------------------------------------------
// Pure Markov step: given the current [~secondLastChord, ~lastChord]
// history, picks and returns the next chord's actual MIDI notes (from
// ~chordSet), and advances the history ready for the call after this one.
// Renamed from ~nextChord (its old name is now the lookahead VARIABLE,
// below, that holds this function's most recent return value ahead of
// time - the two couldn't both be called ~nextChord).
~computeNextChord = {

    var entry;
    var choices;
    var weights;
    var currentChord;

    entry = ~chordMarkov[
        [~secondLastChord, ~lastChord]
    ];

    // fallback if that particular pair isn't in the table
    if(entry.isNil) {
        choices = [1,2,3,4,5,6,7];
        weights = [3,1,1,2,3,2,0.5];
    } {
        choices = entry[0];
        weights = entry[1];
    };

// Global, not local - ~checkForNewChordBar's own postln (below) reports
// this alongside ~chordSet, so a global ~chords[~chordSet][~currentChordNumber - 1]
// lookup can be read back and verified from the post window.
    ~currentChordNumber = choices.wchoose(weights.normalizeSum);

    // move history forward
    ~secondLastChord = ~lastChord;
    ~lastChord = ~currentChordNumber;

    // get actual MIDI notes
    currentChord = ~chords[~chordSet][~currentChordNumber - 1];

    currentChord;
};


// ------------------------------------------------------------
// INITIAL STATE / PIECE START
// ------------------------------------------------------------
// Picks one of the (now 9) chord sets at random (for now - a real "Daily
// Piece" start trigger, ~startPiece, is a planned future step; until it
// exists, this just runs once whenever this file is evaluated, same as
// every other plain-assignment global here) and starts right on that
// set's "I" chord (index 0) - ~secondLastChord/~lastChord are seeded as
// though we'd just arrived at I from IV, the same fixed history this file
// always used to hardcode, just now applied to whichever set got picked
// rather than a hardcoded set 2. ~computeNextChord is then called once
// immediately, to pre-compute the lookahead chord (~nextChord, below)
// that ~checkForNewChordBar will need at the very first bar boundary -
// without this, the first ~numBeats beats would have no ~nextChord ready
// yet. (0..~chords.size - 1), not a hardcoded upper bound, so adding or
// removing a chord set here never needs a matching edit there.
~chordSet = (0..~chords.size - 1).choose;
~secondLastChord = 1;
~lastChord = 4;
~currentChord = ~chords[~chordSet][0];
// Matches index 0 above - kept in sync the same way ~computeNextChord
// keeps it in sync with whatever chord IT picks, so a postln logged before
// the first bar boundary (there isn't one yet, but just in case) would
// still read correctly.
~currentChordNumber = 1;

// The lookahead chord - whatever ~currentChord will become at the NEXT bar
// boundary, already computed ahead of time rather than computed in the
// moment ~checkForNewChordBar needs it. ~computeNextChord's side effects
// (advancing ~secondLastChord/~lastChord, writing ~currentChordNumber) are
// exactly what both setting this up front AND refreshing it every bar
// need, so the same function serves both without any special-casing.
~nextChord = ~computeNextChord.value;


// ------------------------------------------------------------
// ADVANCE THE CHORD, ONCE PER BAR - INDEPENDENT OF ANY TRACK
// ------------------------------------------------------------
// Used to be called from inside ~buildMelodyPattern's own \midinote Pfunc
// (CT8tracks.scd) - but ~currentChord is read by nearly every
// chord-aware track (HT1/MT1 so far), so tying the advance to one
// particular track's own beat-counter was an arbitrary, awkward coupling.
// This instead tracks elapsed beats on its own, completely outside any
// track's Pbind, and advances every ~numBeats beats - the same row-scan
// bar length HT1/PT1 play on (CT8guiClock.scd) - re-read fresh every call
// rather than cached, so it stays correct if the bar length itself changes
// between chord changes (e.g. the displayed time's digit widths changing).
// Scheduled from CT8main.scd's boot sequence via t.sched(0, {...; 1}),
// the same repeating-check idiom ~checkForNewMinute already uses.
~chordBarBeatCount = 0;
// ~chordHeld - set from the Clock Toy Adjust window's "Hold Chord" button
// (CT8guiAdjust.scd) - when true, the bar-boundary check below still
// resets ~chordBarBeatCount every bar (so releasing it lands cleanly on
// the next natural boundary rather than firing an overdue advance
// immediately), it just skips actually moving ~currentChord/~nextChord
// forward. Lets a test run hold on one hand-picked chord (that same
// window's Set/Chord boxes, which write ~currentChord directly) for as
// long as wanted, rather than only ever a Markov-chosen one.
~chordHeld = ~chordHeld ? false;
~checkForNewChordBar = {
    ~chordBarBeatCount = ~chordBarBeatCount + 1;
    if(~chordBarBeatCount >= (~numBeats ? 1).max(1)) {
        ~chordBarBeatCount = 0;
        if(~chordHeld.not) {
// The lookahead chord becomes current, and ~currentChordNumber (last set
// by whichever ~computeNextChord call produced THIS ~nextChord) already
// correctly describes it - so update the GUI readout before computing the
// FOLLOWING lookahead below, which will overwrite ~currentChordNumber
// again, this time to describe next bar's chord instead of this one.
            ~currentChord = ~nextChord;
// ~onChordChanged (CT8guiAdjust.scd) updates that window's chord-name
// readout - guarded with .notNil since this can in principle fire before
// that window exists (or if ClockToy is ever run without it). Same
// ordering reason as above: ~currentChordNumber still describes THIS
// chord here, not yet overwritten by ~computeNextChord below.
            if(~onChordChanged.notNil) { ~onChordChanged.value };
            ~nextChord = ~computeNextChord.value;
        };
    };
};

"CT8 harmony-select functions loaded.".postln;

)
