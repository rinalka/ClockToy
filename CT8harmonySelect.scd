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
// one.
//

(

~chords = [
    // C Major - 3 note chords
    [
        [60, 64, 67],       // C
        [62, 65, 69],       // Dm
        [64, 67, 71],       // Em
        [65, 69, 72],       // F
        [67, 71, 74],       // G
        [69, 72, 76],       // Am
        [71, 74, 77]        // Bdim
    ],

    // C Minor - 3 note chords
    [
        [60, 63, 67],       // Cm
        [62, 65, 68],       // Ddim
        [63, 67, 70],       // Eb
        [65, 68, 72],       // Fm
        [67, 70, 74],       // Gm
        [68, 72, 75],       // Ab
        [70, 74, 77]        // Bb
    ],

    // C Major - 4 note chords
    [
        [60, 64, 67, 71],   // Cmaj7
        [62, 65, 69, 72],   // Dm7
        [64, 67, 71, 74],   // Em7
        [65, 69, 72, 76],   // Fmaj7
        [67, 71, 74, 77],   // G7
        [69, 72, 76, 79],   // Am7
        [71, 74, 77, 81]    // Bm7b5
    ],

    // C Minor - 4 note chords
    [
        [60, 63, 67, 70],   // Cm7
        [62, 65, 68, 72],   // Dm7b5
        [63, 67, 70, 74],   // Ebmaj7
        [65, 68, 72, 75],   // Fm7
        [67, 70, 74, 77],   // Gm7
        [68, 72, 75, 79],   // Abmaj7
        [70, 74, 77, 80]    // Bb7
    ]
];

// Same [set][chordIndex] shape as ~chords, holding the chord-name strings
// that live as trailing comments next to each ~chords entry above - purely
// for readable logging (~checkForNewChordBar, below), since a comment
// isn't something code can read back at runtime; these two tables have to
// be kept in sync by hand if ~chords ever changes.
~chordNames = [
    // C Major - 3 note chords
    ["C", "Dm", "Em", "F", "G", "Am", "Bdim"],
    // C Minor - 3 note chords
    ["Cm", "Ddim", "Eb", "Fm", "Gm", "Ab", "Bb"],
    // C Major - 4 note chords
    ["Cmaj7", "Dm7", "Em7", "Fmaj7", "G7", "Am7", "Bm7b5"],
    // C Minor - 4 note chords
    ["Cm7", "Dm7b5", "Ebmaj7", "Fm7", "Gm7", "Abmaj7", "Bb7"]
];

// Picks one tone from `chord` at random, then picks at random again among
// every octave of that same pitch class (tone % 12) that falls within
// [lo, hi] inclusive - e.g. chordNoteInRange.([62,65,68], 12, 48) can return
// 14, 26, 38, or 50... clipped to the range, so only 14/26/38 here (50 is
// outside). Called fresh per note (wrap the call in a Pfunc inside a Pbind,
// don't precompute once), so which tone AND which octave both re-roll every
// hit rather than staying fixed for a whole bar.
~chordNoteInRange = { |chord, lo, hi|
    var pitchClass = chord.choose % 12;
    var candidates = (lo..hi).select { |n| (n % 12) == pitchClass };
    candidates.choose;
};

// The one shared "current chord". Read LIVE (not snapshotted into a local
// var, so a change is heard on the very next note) by ~buildHarmonyPattern
// (HT1) and ~buildMelodyPattern (MT1), CT8tracks.scd; ~buildBassTrackPattern
// (BT1/BT2) also reads it, for their Random pitch mode specifically, but
// only once per rebuild - see this file's header. This initial value only
// matters until the first bar ends -
// MT1's own \midinote Pfunc calls ~nextChord.value and reassigns
// ~currentChord right as its bar wraps back to beat 0, so playback quickly
// moves onto the Markov progression instead of staying on one fixed chord.
// Plain assignment, not ?-guarded like the GUI-tunable ~percX globals -
// re-evaluating this file always resets to this exact chord again.
~currentChord = ~chords[2][1];


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
// INITIAL STATE
// ------------------------------------------------------------

// Set 2 = C major/minor 4-note chords - HT1/MT1 both play 4 notes at a
// time now (~buildHarmonyPattern/~buildMelodyPattern, CT8tracks.scd), so
// this is the set that actually has 4 distinct tones to draw from.
~chordSet = 2;

~secondLastChord = 1;
~lastChord = 4;


// ------------------------------------------------------------
// GET NEXT CHORD
// ------------------------------------------------------------

~nextChord = {

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
        ~currentChord = ~nextChord.value;
        ("New chord: " ++ ~chordNames[~chordSet][~currentChordNumber - 1]
            ++ "  " ++ ~currentChord ++ "  (set " ++ ~chordSet
            ++ ", index " ++ (~currentChordNumber - 1) ++ ")").postln;
    };
};

"CT8 harmony-select functions loaded.".postln;

)
