// ============================================================================
// CT8tracks.scd
// CLOCKTOY - TRACK GENERATION AND PLAYBACK LIFECYCLE
// ============================================================================
//
// This file owns the musical-composition side of the project: the track
// registry (which tracks exist, whether each is enabled, what Pbind it's
// currently playing), the per-track builder functions that turn the clock
// scan's output (~rowPattern/~colPattern/~clockEvents/~columnEvents, from
// CT8guiClock.scd) and the installed synths (~availableSynths/
// ~getSynthParam, from CT8synths.scd) into actual Pbinds, and the
// start/stop/rebuild lifecycle CT8main.scd and the GUI windows call into.
//
// Split out of the original CT8syn.scd (which mixed this with synth
// definitions) so "how tracks are built" can be worked on without wading
// through SynthDef code. Globals (the track registry, role-assignment
// defaults, PT3's rhythm template) are declared up top, before any
// function, so the data this file works with is visible at a glance - this
// is expected to be the most actively-changing file as the planned
// generative "Daily Piece" hierarchy (Piece -> Phrase -> Bar -> Beat, see
// CT8main.scd's FUTURE DIRECTION note) gets designed and built out on top
// of what's here now.
//
// Requires CT8synths.scd (~availableSynths/~getSynthParam) and
// CT8guiClock.scd (~rowPattern/~colPattern/~clockEvents/~columnEvents) to
// already be loaded - CT8main.scd's ~loadAllCt8Files loads every file in
// the right order.
//


(

// ---------------------------------------------------------------------------
// ROW/COL TRACK -> SYNTH ASSIGNMENT DEFAULTS
// ---------------------------------------------------------------------------
// Which installed synth (from ~availableSynths, CT8synths.scd) plays each
// role on PT1/PT2. Moved here from ~makeSynthWindow (CT8guiSynth.scd) - that
// window is currently disabled (see CT8main.scd), pending a rewrite, but
// ~buildRowPattern/~buildColumnPattern still read these fresh every note, so
// they need a real default independent of whether that window ever runs.
~rowStartSynth = ~rowStartSynth ? \plucking;
~rowCellSynth = ~rowCellSynth ? \hat;
~colStartSynth = ~colStartSynth ? \baseD;
~colCellSynth = ~colCellSynth ? \cym;


// ---------------------------------------------------------------------------
// TRACK REGISTRY (planned "Daily Piece" multi-track structure)
// ---------------------------------------------------------------------------
// All 13 planned tracks, by name: 4 percussion, 1 bass, 4 rhythm/harmony,
// 4 melody (see CT8main.scd's FUTURE DIRECTION note). PT1/PT2/PT3/HT1/MT1/
// BT1 actually exist right now; the rest are registered but inert until a
// builder is added for them.
//
// Rather than one-off globals per track, state for every track lives in
// parallel per-track dictionaries, keyed by track name - keeps the global
// count from growing one-per-track as more come online:
//   ~trackPatterns[name]      - that track's built Pbind (or nil if unbuilt)
//   ~trackPlayers[name]       - that track's playing EventStreamPlayer (or nil)
//   ~trackEnabled[name]       - whether the user wants that track's sound
//                               playing
//   ~trackFlashEnabled[name]  - PT1/PT2 only: whether that track's clock-face
//                               flash/background color is wanted, independent
//                               of ~trackEnabled's sound switch (see
//                               ~buildRowPattern/~buildColumnPattern's
//                               \type/\updateGUI keys, below, and
//                               ~trackShouldPlay/~syncTrackPlayer, which keep
//                               the shared player running as long as either
//                               one is wanted)
//   ~trackBuilders[name]      - the function that (re)builds
//                               ~trackPatterns[name] from current input data;
//                               the lifecycle functions below just call
//                               whatever's registered here, so adding a new
//                               track's builder is the only change needed to
//                               bring it under this same start/stop/rebuild
//                               machinery - see ~buildRowPattern/
//                               ~buildColumnPattern for the pattern to follow
~trackNames = [
    \PT1, \PT2, \PT3, \PT4,   // percussion
    \BT1,                      // bass
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
// PT1/PT2/PT3/HT1/MT1/BT1 (the currently-built tracks) default on;
// everything else defaults off since it doesn't exist yet.
    ~trackEnabled[name] = ~trackEnabled[name] ? (
        (name == \PT1) or: { name == \PT2 } or: { name == \PT3 } or: { name == \HT1 }
            or: { name == \MT1 } or: { name == \BT1 }
    );
};

// PT1/PT2 uniquely drive the clock-face flash/background color from inside
// their own Pbind (\updateGUI, in ~buildRowPattern/~buildColumnPattern below)
// - ~trackEnabled[name] alone used to control both the sound and that flash
// together, since stopping the Pbind stopped both at once. Split out so
// either can be toggled independently: ~trackEnabled still gates the actual
// audio (via \type going to \rest when off - see the Pbinds below), while
// ~trackFlashEnabled gates \updateGUI's flash call. No other track has a
// flash overlay, so this dictionary only has entries for PT1/PT2.
~trackFlashEnabled = ~trackFlashEnabled ? ();
~trackFlashEnabled[\PT1] = ~trackFlashEnabled[\PT1] ? true;
~trackFlashEnabled[\PT2] = ~trackFlashEnabled[\PT2] ? true;


// ---------------------------------------------------------------------------
// PT3's RHYTHM TEMPLATE
// ---------------------------------------------------------------------------
// Fixed hit/rest template for PT3's snare (~buildSnarePattern, below) -
// nearest-neighbor resampled to ~numBeats every rebuild, so its loop always
// spans exactly one PT1 bar rather than a fixed number of steps unrelated to
// anything else on the clock face.
~snareTemplate = [
    1,1,1,1,1,1,1,1,\rest,\rest



];


// ---------------------------------------------------------------------------
// PLAYER LIFECYCLE HELPERS
// ---------------------------------------------------------------------------
// Whether a track's EventStreamPlayer should be running at all: normally
// just ~trackEnabled[name], except PT1/PT2 also need to keep playing (to
// keep flashing) even with their own sound switched off, as long as their
// flash is still wanted.
~trackShouldPlay = { |name|
    var shouldPlay = ~trackEnabled[name];
    if(name == \PT1) { shouldPlay = shouldPlay or: { ~trackFlashEnabled[\PT1] } };
    if(name == \PT2) { shouldPlay = shouldPlay or: { ~trackFlashEnabled[\PT2] } };
    shouldPlay;
};

// Stop a track's current player (if any), then restart it if it should be
// playing and has a built pattern. Shared by the adjust window's sound/flash
// buttons (CT8guiAdjust.scd) so both kinds of toggle resync the same way.
~syncTrackPlayer = { |name|
    if(~trackPlayers[name].notNil) { ~trackPlayers[name].stop; ~trackPlayers[name] = nil };
    if(~trackShouldPlay.(name) and: { ~trackPatterns[name].notNil } and: { t.notNil }) {
        ~trackPlayers[name] = ~trackPatterns[name].play(t, quant: 1);
    };
};


// BUILD MUSICAL PATTERN FROM ~clockEvents
// ---------------------------------------------------------------------------
// PT1: the row-scan track. Convert the current ~clockEvents Array into the
// repeating musical Pbind.
~buildRowPattern = {
// Use an empty Array if the GUI has not yet produced any events.
    var events = ~clockEvents ? [];
// Build a harmless rest pattern rather than failing on an empty event stream.
    if(events.isEmpty) {
        "No active clock cells to play.".warn;
        ~trackPatterns[\PT1] = Pbind(
            \dur, 1,
            \type, \rest
        );
    } {
// Counts how many \cym cells have played since the last start-role event,
// times 50, added on top of \cym's own basefreq. Resets at every start event
// (no matter which synth is currently assigned to start), and just keeps
// climbing for however many \cym cells follow it - no cap. Only matters
// when \cym happens to be ~rowCellSynth right now. This is the one bit of
// per-synth behavior that isn't just a plain ~getSynthParam lookup below.
var cymFreqOffset = 0;
// 0-based position within the current pass through `events`; wraps back to
// 0 every time Pseq(events, inf) starts a fresh cycle. Set once per event by
// \instrument (evaluated first, per the key order below), then just read by
// the other keys further down to know it's that same "cycle start" beat.
var beatIndex = 0;
var isCycleStart = false;
// Diagnostic only, for the node-count/RT-memory investigation. beatCount:
// every event. barCount: only events where isCycleStart is true, i.e. once
// per full pass through `events` (a "bar" - see CT8main.scd's FUTURE
// DIRECTION note). Both reset to 0 on every rebuild (minute change,
// track/format toggles, etc.), same as cymFreqOffset/beatIndex above.
var beatCount = 0;
var barCount = 0;

// Construct an Event pattern whose source clock-cell sequence repeats forever.
~trackPatterns[\PT1] = Pbind(
			\dur, 1,
			\clockEvent, Pseq(events, inf),

// ~rowStartSynth/~rowCellSynth (set from the Synth Controls window's Row
// Start/Cell menus) pick which installed synth plays this role on this
// track - any combination from ~availableSynths, freely reassignable live.
// (The once-per-cycle low \fm hit that used to live here is now BT1, a real
// bass track built from both ~rowPattern and ~colPattern - see
// ~buildBassPattern, below. isCycleStart/beatIndex are kept only for
// \dbgBeatBar's bar-count diagnostic now.)
			\instrument, Pfunc { |event|
				var isStart = (event[\clockEvent][\role] == \rowStart);
				isCycleStart = (beatIndex == 0);
				beatIndex = (beatIndex + 1) % events.size;
				if(isStart) { ~rowStartSynth } { ~rowCellSynth }
			},

// Read fresh every note so the Synth Controls window's menus and per-synth
// knobs both take effect immediately - reassigning a menu already triggers
// a pattern rebuild on its own. ~getSynthParam dispatches by the ACTUAL
// synth chosen for this event, not by track/role, so a synth's knobs always
// control it no matter which slot (row/col start/cell) it's plugged into.
			\basefreq, Pfunc { |event|
				var isStart = (event[\clockEvent][\role] == \rowStart);
				var synth = if(isStart) { ~rowStartSynth } { ~rowCellSynth };
				if(isStart) { cymFreqOffset = 0 };
				if(synth == \cym and: { isStart.not }) { cymFreqOffset = cymFreqOffset + 50 };
				~getSynthParam.(synth, \basefreq, 0)
					+ (if(synth == \cym) { cymFreqOffset } { 0 })
			},
			\amp, Pfunc { |event|
				var isStart = (event[\clockEvent][\role] == \rowStart);
				var synth = if(isStart) { ~rowStartSynth } { ~rowCellSynth };
// 0.1 matches Pbind's own default \amp, for any synth with no \amp entry
// in ~availableSynths (e.g. plucking, which uses \sAmp instead).
				~getSynthParam.(synth, \amp, 0.1)
			},
			\len, Pfunc { |event|
				var isStart = (event[\clockEvent][\role] == \rowStart);
				var synth = if(isStart) { ~rowStartSynth } { ~rowCellSynth };
				~getSynthParam.(synth, \len, 0.25)
			},
// \freq is normally filled in by Pbind's own default pitch calculation
// (from degree/octave/scale) whenever it's not set explicitly - this
// override replaces that for every synth here, not just ones that have a
// \freq arg (harmless where there isn't one, e.g. baseD/cym).
			\freq, Pfunc { |event|
				var isStart = (event[\clockEvent][\role] == \rowStart);
				var synth = if(isStart) { ~rowStartSynth } { ~rowCellSynth };
				~getSynthParam.(synth, \freq, 440)
			},
// sAmp is plucking's real output-level control (see ~availableSynths).
			\sAmp, Pfunc { |event|
				var isStart = (event[\clockEvent][\role] == \rowStart);
				var synth = if(isStart) { ~rowStartSynth } { ~rowCellSynth };
				~getSynthParam.(synth, \sAmp, 0.5)
			},
// A reverb-send arg, harmlessly ignored by every synth here that doesn't
// declare an \fx arg (i.e. all of them right now - none of ~availableSynths'
// entries use it). Wrapped in Pfunc rather than passed as a bare value:
// ~revBus is a Bus object, not a plain number, and a bare non-Pfunc value's
// stream-conversion may not repeat indefinitely the way every other key's
// Pfunc reliably does - suspected cause of the pattern silently stopping
// after its first event.
			\fx, Pfunc { ~revBus },

// Diagnostic only - prints a bar count each time a new cycle through
// `events` begins (see beatCount/barCount, above); beat-level printing
// removed (too noisy - one line per event). Safe to delete once done with
// it; doesn't affect what's actually played. Returns beatCount, not nil: a
// Pfunc yielding bare nil is SC's stream-protocol signal for "this stream
// has ended", which was silently killing the whole Pbind after just one
// event - any non-nil return avoids that.
			\dbgBeatBar, Pfunc {
				beatCount = beatCount + 1;
				if(isCycleStart) {
					barCount = barCount + 1;
					("PT1 bar: " ++ barCount).postln;
				};
				beatCount
			},

// Sound and flash are independently toggleable now (~trackEnabled[\PT1] vs
// ~trackFlashEnabled[\PT1] - see the TRACK REGISTRY block) even though both
// live on this one Pbind/EventStreamPlayer - ~syncTrackPlayer keeps the
// player itself running as long as either one is wanted. \type going to
// \rest is the standard Event mechanism for "build this event's other keys
// as normal, but don't actually spawn a synth for it" - every key above
// still gets computed, just unused, when sound is off.
			\type, Pfunc { if(~trackEnabled[\PT1]) { \note } { \rest } },

			\updateGUI, Pfunc { |event|
				if(~trackFlashEnabled[\PT1]) {
					var cell = event[\clockEvent];
					{
						~flashRow.value(
							cell[\row],
							cell[\panel],
							cell[\segment],
							Color.blue
						);
					}.defer;
				};
// Must return non-nil regardless of the branch above - see \dbgBeatBar's
// comment just above for why a bare nil here would silently kill the Pbind.
				\flashed
			}
		);
    };
};


// PT2: the second, simultaneous percussion track, from the by-column scan.
~buildColumnPattern = {
    var events = ~columnEvents ? [];

    if(events.isEmpty) {
        "No active column cells to play.".warn;
        ~trackPatterns[\PT2] = Pbind(\dur, 1, \type, \rest);
    } {
// Counts how many \cym cells have played since the last start-role event,
// times 50, added on top of \cym's own basefreq. Resets at every start event
// (no matter which synth is currently assigned to start), and just keeps
// climbing for however many \cym cells follow it - no cap. Only matters
// when \cym happens to be ~colCellSynth right now. This is the one bit of
// per-synth behavior that isn't just a plain ~getSynthParam lookup below.
        var cymFreqOffset = 0;
// 0-based position within the current pass through `events`; wraps back to
// 0 every time Pseq(events, inf) starts a fresh cycle - mirrors PT1's
// beatIndex/isCycleStart. PT2 has no per-synth use for this (no \fm hit
// here), only the beat/bar diagnostic below needs it.
        var beatIndex = 0;
        var isCycleStart = false;
// Diagnostic only, for the node-count/RT-memory investigation. beatCount:
// every event. barCount: only events where isCycleStart is true, i.e. once
// per full pass through `events` (a "bar" - see CT8main.scd's FUTURE
// DIRECTION note).
        var beatCount = 0;
        var barCount = 0;

        ~trackPatterns[\PT2] = Pbind(
            \dur, 1,
            \clockEvent, Pseq(events, inf),

// Mirror of ~buildRowPattern's check, above: ~colStartSynth/~colCellSynth
// (set from the Synth Controls window's Col Start/Cell menus) pick which
// installed synth plays this role on this track. Also updates
// beatIndex/isCycleStart (unlike PT1, purely for the beat/bar diagnostic
// below - nothing here branches on isCycleStart).
            \instrument, Pfunc { |event|
                var isStart = (event[\clockEvent][\role] == \columnStart);
                isCycleStart = (beatIndex == 0);
                beatIndex = (beatIndex + 1) % events.size;
                if(isStart) { ~colStartSynth } { ~colCellSynth }
            },

            \basefreq, Pfunc { |event|
                var isStart = (event[\clockEvent][\role] == \columnStart);
                var synth = if(isStart) { ~colStartSynth } { ~colCellSynth };
                if(isStart) { cymFreqOffset = 0 };
                if(synth == \cym and: { isStart.not }) { cymFreqOffset = cymFreqOffset + 50 };
                ~getSynthParam.(synth, \basefreq, 0)
                    + (if(synth == \cym) { cymFreqOffset } { 0 })
            },
            \amp, Pfunc { |event|
                var isStart = (event[\clockEvent][\role] == \columnStart);
                var synth = if(isStart) { ~colStartSynth } { ~colCellSynth };
// 0.1 matches Pbind's own default \amp, for any synth with no \amp entry
// in ~availableSynths (e.g. plucking, which uses \sAmp instead).
                ~getSynthParam.(synth, \amp, 0.1)
            },
            \len, Pfunc { |event|
                var isStart = (event[\clockEvent][\role] == \columnStart);
                var synth = if(isStart) { ~colStartSynth } { ~colCellSynth };
                ~getSynthParam.(synth, \len, 0.25)
            },
// \freq is normally filled in by Pbind's own default pitch calculation
// (from degree/octave/scale) whenever it's not set explicitly - this
// override replaces that for every synth here, not just ones that have a
// \freq arg (harmless where there isn't one, e.g. baseD/cym).
            \freq, Pfunc { |event|
                var isStart = (event[\clockEvent][\role] == \columnStart);
                var synth = if(isStart) { ~colStartSynth } { ~colCellSynth };
                ~getSynthParam.(synth, \freq, 440)
            },
// sAmp is plucking's real output-level control (see ~availableSynths).
            \sAmp, Pfunc { |event|
                var isStart = (event[\clockEvent][\role] == \columnStart);
                var synth = if(isStart) { ~colStartSynth } { ~colCellSynth };
                ~getSynthParam.(synth, \sAmp, 0.5)
            },

// Diagnostic only - prints a bar count each time a new cycle through
// `events` begins (see beatCount/barCount, above); beat-level printing
// removed (too noisy - one line per event). Safe to delete once done with
// it; doesn't affect what's actually played. Returns beatCount, not nil: a
// Pfunc yielding bare nil is SC's stream-protocol signal for "this stream
// has ended", which was silently killing the whole Pbind after just one
// event - any non-nil return avoids that.
            \dbgBeatBar, Pfunc {
                beatCount = beatCount + 1;
                if(isCycleStart) {
                    barCount = barCount + 1;
                    ("PT2 bar: " ++ barCount).postln;
                };
                beatCount
            },

// Sound and flash are independently toggleable now (~trackEnabled[\PT2] vs
// ~trackFlashEnabled[\PT2] - see the TRACK REGISTRY block, and PT1's
// matching comment above) even though both live on this one Pbind - \type
// going to \rest is the standard Event mechanism for "build this event's
// other keys as normal, but don't actually spawn a synth for it."
            \type, Pfunc { if(~trackEnabled[\PT2]) { \note } { \rest } },

            \updateGUI, Pfunc { |event|
                if(~trackFlashEnabled[\PT2]) {
                    var cell = event[\clockEvent];
                    {
                        ~flashColumn.value(
                            cell[\column],
                            cell[\panel],
                            cell[\segment],
                            Color.black
                        );
                    }.defer;
                };
// Must return non-nil regardless of the branch above - see \dbgBeatBar's
// comment just above for why a bare nil here would silently kill the Pbind.
                \flashed
            }
        );
    };
};


// PT3: a percussion "snare" track, hand-designed by the user from \fm with
// extreme parameters (very high cRatio/index, short rel). Its rhythm is a
// fixed hit/rest template (~snareTemplate, above) - unlike PT1/PT2 it isn't
// derived from ~clockEvents/~columnEvents at all, so it has no \updateGUI
// (no segment to flash for a given hit). Nearest-neighbor resampled to
// ~numBeats every rebuild, so its loop always spans exactly one PT1 bar
// rather than a fixed number of steps unrelated to anything else on the
// clock face.
~buildSnarePattern = {
// Guard against ~numBeats being 0 (e.g. a rebuild triggered before the first
// clock scan has ever run) - collect{} over 0 is harmless, but the resample
// index math below divides by it.
    var numBeats = max(~numBeats ? 0, 1);
    var freqSteps = numBeats.collect { |i|
        ~snareTemplate[(i * ~snareTemplate.size / numBeats).floor.asInteger.clip(0, ~snareTemplate.size - 1)]
    };

    ~trackPatterns[\PT3] = Pbind(
        \instrument, \fm,
        \dur, 1,
        \freq, Pseq(freqSteps, inf) * 411,
        \cRatio, 45.9,
        \mRatio, 1.5,
        \index, 100,
        \iScale, 1,
        \atk, 0,
        \rel, 0.1,
        \cRel, -8,
        \amp, Pseq([0.18, 0.04, 0.18, 0.1], inf),
        \pan, 0,
        \out, 0,
// Wrapped in Pfunc, like ~fx above in PT1 - see that comment for why a bare
// Bus value is suspect here.
        \fx, Pfunc { ~revBus },
        \fxsend, -12
    );
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
        var chordGroups = [
            [48, 52, 55],   // C major (C3 E3 G3)
            [43, 47, 50],   // G major (G2 B2 D3)
            [41, 45, 48]    // F major (F2 A2 C3)
        ];

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
            \midinote, Pseq(chordGroups, inf),
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
// segments ("entries"), but rather than one note per entry, this plays 1 or
// 2 randomly-picked notes per column-slot, re-rolled live every time (not
// precomputed once per rebuild like HT1's chordGroups - the melody varies
// bar to bar even when the column layout itself doesn't change this
// minute). Notes are drawn from the white keys (natural notes, no
// sharps/flats) one octave above ~buildHarmonyPattern's chordGroups
// register (those sit around octaves 2-3, MIDI 41-55) - i.e. octave 4.
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
        var whiteNotes = [60, 62, 64, 65, 67, 69, 71]; // C4 D4 E4 F4 G4 A4 B4

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
// Array-valued \midinote (like HT1's chordGroups) plays all its notes as
// one simultaneous chord/dyad - here a fresh 1-or-2-note pick every time
// this key is read, rather than a fixed precomputed sequence.
            \midinote, Pfunc { Array.fill([1, 2].choose, { whiteNotes.choose }) },
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


// BT1: the first bass track - the low \fm hit that used to fire once per
// PT1 cycle (see ~buildRowPattern's comment) is now a real track: one hit
// at every \rowStart in ~rowPattern (same pitch as before, midinote 20)
// PLUS one hit at every \columnStart in ~colPattern (an octave higher,
// midinote 32), running simultaneously as two independent sub-patterns
// (Ppar) since the row-scan and column-scan grids have different beat
// counts and can't share one \dur sequence. Each sub-pattern mirrors HT1/
// MT1's structure: \dur is however many beats that row/column spans, so a
// hit lands exactly on every row/column boundary of its own grid.
~buildBassPattern = {
    var rowEvents = ~rowPattern ? [];
    var colEvents = ~colPattern ? [];
    var rowBassPattern, colBassPattern;

    if(rowEvents.isEmpty) {
        rowBassPattern = Pbind(\dur, 1, \type, \rest);
    } {
        var rowStartIdx, rowDurs;
        rowStartIdx = [];
        rowEvents.do { |ev, i| if(ev[\role] == \rowStart) { rowStartIdx = rowStartIdx.add(i) } };
        rowDurs = rowStartIdx.collect { |idx, i|
            var nextIdx = if((i + 1) < rowStartIdx.size) { rowStartIdx[i + 1] } { rowEvents.size };
            nextIdx - idx
        };
        rowBassPattern = Pbind(
            \instrument, \fm,
            \dur, Pseq(rowDurs, inf),
            \midinote, 20,
            \amp, 1.0,
            \rel, 0.4,
            \fx, Pfunc { ~revBus }
        );
    };

    if(colEvents.isEmpty) {
        colBassPattern = Pbind(\dur, 1, \type, \rest);
    } {
        var colStartIdx, colDurs;
        colStartIdx = [];
        colEvents.do { |ev, i| if(ev[\role] == \columnStart) { colStartIdx = colStartIdx.add(i) } };
        colDurs = colStartIdx.collect { |idx, i|
            var nextIdx = if((i + 1) < colStartIdx.size) { colStartIdx[i + 1] } { colEvents.size };
            nextIdx - idx
        };
        colBassPattern = Pbind(
            \instrument, \fm,
            \dur, Pseq(colDurs, inf),
            \midinote, 32,
            \amp, 1.0,
            \rel, 0.4,
            \fx, Pfunc { ~revBus }
        );
    };

    ~trackPatterns[\BT1] = Ppar([rowBassPattern, colBassPattern]);
};


// Register PT1/PT2/PT3/HT1/MT1/BT1's builders. Adding track N's builder
// here is the only step needed to bring it under the same start/stop/
// rebuild machinery below.
~trackBuilders[\PT1] = ~buildRowPattern;
~trackBuilders[\PT2] = ~buildColumnPattern;
~trackBuilders[\PT3] = ~buildSnarePattern;
~trackBuilders[\HT1] = ~buildHarmonyPattern;
~trackBuilders[\MT1] = ~buildMelodyPattern;
~trackBuilders[\BT1] = ~buildBassPattern;

// ---------------------------------------------------------------------------
// START PATTERN
// ---------------------------------------------------------------------------
// Ensure the reverb exists, (re)build every registered track's pattern, and
// start playback for whichever tracks should be playing (~trackShouldPlay -
// normally just ~trackEnabled, except PT1/PT2 also stay running for
// flash-only, sound-off use - see the TRACK REGISTRY block).
~setStartPbinds = {
    if(~clockRev.isNil or: { ~clockRev.isRunning.not }) {
        ~clockRev = Synth(
            \ELIreverb,
            [\in, ~revBus, \out, 0, \dec, ~reverbDec, \lpf, ~reverbLpf, \mix, ~reverbMix]
        );
    };

    ~trackBuilders.keysValuesDo { |name, builder| builder.value };

    ~trackNames.do { |name|
        if(~trackShouldPlay.(name) and: { ~trackPatterns[name].notNil }) {
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
// Defensive stop, then play whichever tracks should be playing
// (~trackShouldPlay - see ~setStartPbinds' comment above).
~restartPbinds = {
    ~stopPbinds.value;

    ~trackNames.do { |name|
        if(~trackShouldPlay.(name) and: { ~trackPatterns[name].notNil }) {
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
