// ============================================================================
// CT8harmonySelect.scd
// CLOCKTOY - HARMONY/CHORD SELECTION (new, in progress)
// ============================================================================
//
// Owns the shared harmonic concept the rhythm/harmony and melody tracks
// (HT1-4, MT1-4) are meant to generate around: a "current chord" that those
// tracks each pick notes from, rather than each inventing their own pitch
// material independently. BT1/BT2 (the two bass tracks) moved onto the
// generic Bass Generator config instead (~buildBassTrackPattern,
// CT8tracks.scd), the same source/instrument/pattern/pitch/volume scheme
// PT1-4 already use - but still read ~currentChord/~chordNoteInRange from
// here for their own Random pitch mode specifically (Fixed stays a plain,
// non-chord-aware note), just once per rebuild rather than live per-hit the
// way HT1/MT1 do. Not yet wired into every one of HT1-4/MT1-4 - HT1/MT1 are
// the only two live, per-hit consumers so far.
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
// per-track config table in this project (~percX/~bassX, CT8tracks.scd).
~currentRange = ~currentRange ? ();
~currentRange[\HT1] = ~currentRange[\HT1] ? [60, 96];
~currentRange[\MT1] = ~currentRange[\MT1] ? [60, 96];
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
    var candidates = (lo..hi).select { |n| (n % 12) == pitchClass };
    candidates.choose;
};

// ~currentChord is the one shared "current chord". Read LIVE (not
// snapshotted into a local var, so a change is heard on the very next
// note) by ~buildHarmonyPattern (HT1) and ~buildMelodyPattern (MT1),
// CT8tracks.scd; ~buildBassTrackPattern (BT1/BT2) also reads it, for their
// Random pitch mode specifically, but only once per rebuild - see this
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
~checkForNewChordBar = {
    ~chordBarBeatCount = ~chordBarBeatCount + 1;
    if(~chordBarBeatCount >= (~numBeats ? 1).max(1)) {
        ~chordBarBeatCount = 0;
// The lookahead chord becomes current, and ~currentChordNumber (last set
// by whichever ~computeNextChord call produced THIS ~nextChord) already
// correctly describes it - so log before computing the FOLLOWING lookahead
// below, which will overwrite ~currentChordNumber again, this time to
// describe next bar's chord instead of this one.
        ~currentChord = ~nextChord;
        ("New chord: " ++ ~chordNames[~chordSet][~currentChordNumber - 1]
            ++ "  " ++ ~currentChord ++ "  (set " ++ ~chordSet
            ++ ", index " ++ (~currentChordNumber - 1) ++ ")").postln;
        ~nextChord = ~computeNextChord.value;
    };
};

"CT8 harmony-select functions loaded.".postln;

)
