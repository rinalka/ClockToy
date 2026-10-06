// ============================================================================
// CT8guiTracksLab.scd
// CLOCKTOY - TRACK-TEMPLATE LAB (prototype, structured like CT8guiSynthLab.scd)
// ============================================================================
//
// A quick, throwaway tool for trying out track-template ideas before any of
// them get built into CT8tracks.scd for real - CT8tracks.scd is completely
// untouched by this file. Plays one \kick voice through a small, fixed menu
// of choices:
//   1. Pattern source - ~rowPattern or ~colPattern (same shared scan data
//      every real track already reads).
//   2. Pitch - fixed, or rising by a step each beat and resetting to base at
//      every row/col-start (this lab's own reset-at-start/grow-by-step
//      design - the real ~buildPercPattern's \rising pitch mode,
//      CT8tracks.scd, later adopted the identical logic for PT1-4; this
//      file predates that, not the other way around).
//   3. Volume - fixed, or accented (louder) specifically on row/col-start
//      beats.
//   4. Notes per beat - one, two (played as a simultaneous dyad, same
//      array-expansion technique HT1/MT1/droneChord already use), or a
//      random choice between one and two every beat.
//   5. Rhythm - each scan-beat as one quarter-note-length hit, two
//      eighth-note-length hits (same pitch/amp, just subdivided), or a
//      random choice between the two every beat. Independent of #4 - the
//      two combine (e.g. a dyad played as two eighths).
//
// Playback always starts in step with the real clock: rather than rebuilding
// and restarting immediately on open or on every control change, this waits
// for the clock's next rebuild - a minute change, but also a Real/Entered
// Time switch or 12/24-hour toggle, anything that calls ~getLineSegOrder
// (the same moment ~stopPbinds/~restartPbinds restart every real track and
// flash player, all via quant:1) - and only (re)builds then, landing this
// player on the exact same beat they do, instead of an arbitrary one. A
// control change just updates its variable and waits for that same moment
// too (or click Resync to go quiet and re-arm immediately, still waiting
// for the next rebuild rather than resyncing itself out of phase). Each
// (re)build dumps the whole planned
// beat sequence - role/isStart/pitchOffset per original scan-beat - to the
// post window, to make it easy to check the pitch-rise/reset logic is
// actually tracking row/col-start boundaries correctly.
//
// NOT part of CT8main's load/boot sequence - evaluate this file on its own,
// whenever the real project (CT8main.scd) is already running (needs the
// server booted and `t` to already exist). Self-contained: its own Pbind/
// EventStreamPlayer, straight to the hardware output, no private reverb bus
// of its own (unlike CT8guiSynthLab.scd) - instead it just dials in \kick's
// own tiny built-in ~allpassWash tail (see CT8synths.scd's \hat \wet/\level
// comment) via the Reverb wet/level controls below, live, since \kick is
// the one thing this file always plays (was \mix/FreeVerb - stale ever
// since \kick itself moved to \wet/\level, which silently broke this
// control until now). Reverting is just deleting this one file - nothing
// elsewhere references it.
//
// \kick's own drumHarmonic (the ratio its pitch-sweep's attack transient
// starts above its settled pitch) is exposed too, live same as reverb -
// its drumFreq (the settled pitch itself) is NOT a separate control,
// though, since that's already what Base pitch/Pitch step feed into the
// Pbind's \drumFreq key below; a second, separate \drumFreq entry would
// just silently override that per-beat-varying one instead of adding
// anything.
// While open, mutes every track in ~trackNames (CT8tracks.scd) so this
// prototype can be heard on its own; restores each one's prior
// ~trackEnabled value when the window closes.
//


(

~makeTracksLabWindow = {
    var window, patternSource = \row, pitchMode = \fixed, ampMode = \fixed, notesMode = \one, subdivMode = \quarter;
    var basePitch = 50, pitchStep = 20, baseAmp = 0.5, accentAmp = 1.0;
    var reverbWet = 0.2, reverbLevel = 1, drumHarmonic = 2;
    var labPattern, labPlayer, mutedTrackEnabled;
    var buildLabPattern, syncLabPlayer, armResyncWait, settingsChanged, lastSeenRowPattern, watchActive;
    var sourceMenu, pitchMenu, ampMenu, notesMenu, subdivMenu;
    var pitchBaseBox, pitchStepBox, ampBaseBox, accentAmpBox, statusText, makeNumberRow;

    if(s.serverRunning.not or: { t.isNil }) {
        "Can't open the Tracks Lab - CT8main.scd needs to be running first (server booted, TempoClock t exists).".warn;
        ^nil;
    };

// Free a previous lab instance (if this is a re-run) before muting/creating
// anything new.
    if(~stopTracksLab.notNil) { ~stopTracksLab.value };

// Mute every track so this prototype plays in isolation; restored by
// ~stopTracksLab.
    mutedTrackEnabled = ();
    ~trackNames.do { |name|
        mutedTrackEnabled[name] = ~trackEnabled[name];
        ~trackEnabled[name] = false;
    };
    ~stopPbinds.value;

// Fully pre-resolves the whole bar into flat dur/freq/amp arrays, one
// resolved "slot" per entry (one slot per original scan-beat, or two if that
// beat subdivides into eighths - see subdivMode below). Doing this at build
// time, rather than with live per-event Pfuncs, means the whole planned
// sequence can be dumped to the post window in one shot for debugging - see
// the postln below - and means pitch/amp are computed exactly once per
// ORIGINAL scan-beat (both eighth-notes of a split beat share the same
// pitch/amp, since they're the same underlying clock-cell, just rhythmically
// subdivided).
    buildLabPattern = {
        var events = if(patternSource == \row) { ~rowPattern ? [] } { ~colPattern ? [] };
        var startRole = if(patternSource == \row) { \rowStart } { \columnStart };
        if(events.isEmpty) {
            labPattern = Pbind(\dur, 1, \type, \rest);
        } {
            var pitchOffset = 0;
            var durs = List.new;
            var freqLists = List.new;
            var amps = List.new;

            ("--- Tracks Lab rebuild: % beats, pattern=%, pitch=%, subdiv=% ---"
                .format(events.size, patternSource, pitchMode, subdivMode)).postln;

            events.do { |ev, i|
// This is the ONLY place pitchOffset ever changes - resets on a genuine
// row/col-start, otherwise grows by pitchStep when pitchMode is \rising.
                var isStart = (ev[\role] == startRole);
                var freqs, amp, subCount;

                if(isStart) {
                    pitchOffset = 0;
                } {
                    if(pitchMode == \rising) { pitchOffset = pitchOffset + pitchStep };
                };

                ("  beat % role=% isStart=% pitchOffset=%"
                    .format(i, ev[\role], isStart, pitchOffset)).postln;

                freqs = [basePitch + pitchOffset];
                case
                { notesMode == \two } { freqs = freqs ++ [basePitch + pitchOffset + pitchStep] }
                { notesMode == \random } { if(0.5.coin) { freqs = freqs ++ [basePitch + pitchOffset + pitchStep] } };

                amp = if(ampMode == \accent) { if(isStart) { accentAmp } { baseAmp } } { baseAmp };

                subCount = switch(subdivMode,
                    \quarter, { 1 },
                    \eighths, { 2 },
                    \random, { [1, 2].choose }
                );

                subCount.do {
                    durs.add(1 / subCount);
                    freqLists.add(freqs);
                    amps.add(amp);
                };
            };

            labPattern = Pbind(
                \instrument, \kick,
                \out, 0,
                \dur, Pseq(durs.asArray, inf),
                \drumFreq, Pseq(freqLists.asArray, inf),
                \amp, Pseq(amps.asArray, inf),
// \kick's own tiny built-in ~allpassWash tail (CT8synths.scd) plus its
// pitch-sweep's drumHarmonic ratio - all three read live via Pfunc rather
// than baked into the rebuild like everything else here, since each is one
// flat value, not something that needs the pattern reshaped; their own
// boxes below can change them without waiting for the clock's next rebuild
// or a Resync click.
                \wet, Pfunc { reverbWet },
                \level, Pfunc { reverbLevel },
                \drumHarmonic, Pfunc { drumHarmonic }
            );
        };
    };

// Rebuild from whatever the controls/current scan say, then restart on the
// shared TempoClock. Only ever called right as a clock rebuild is detected
// (see the t.sched watcher below) - the real tracks/flash players all
// restart together, via quant:1, at that exact moment, so restarting here
// at the same moment lands this player on the same beat they do, instead
// of an arbitrary one. Calling this at any other time would immediately
// throw that sync back out, so nothing else calls it directly.
    syncLabPlayer = {
        buildLabPattern.value;
        if(labPlayer.notNil) { labPlayer.stop; labPlayer = nil };
        labPlayer = labPattern.play(t, quant: 1);
        { statusText.string_("Playing - synced to the clock."); }.defer;
    };

// Stop playback (if any) and go quiet until the clock's next rebuild, which
// will call syncLabPlayer. Used both to arm the initial wait on window-open
// and by the Resync button, so changed settings never get heard out of
// phase with the real clock.
    armResyncWait = {
        if(labPlayer.notNil) { labPlayer.stop; labPlayer = nil };
        lastSeenRowPattern = ~rowPattern;
        { statusText.string_("Waiting for the clock's next rebuild to (re)sync..."); }.defer;
    };

// Controls update their variable and call this instead of rebuilding
// immediately - the change is picked up next time syncLabPlayer runs (i.e.
// the clock's next rebuild), keeping playback always phase-locked rather
// than resyncing on every tweak.
    settingsChanged = {
        { statusText.string_("Settings changed - takes effect at clock's next rebuild (or click Resync)."); }.defer;
    };

// Polls once per beat for a rebuild, detected as ~rowPattern becoming a
// new array object - every rebuild trigger (minute change, Real/Entered
// Time switch, 12/24-hour toggle) reassigns it fresh via ~getLineSegOrder,
// even when the displayed time ends up unchanged, so this catches all of
// them uniformly. (Watching ~minutes itself isn't reliable - switching
// source/format can rebuild without ~minutes' value actually changing.)
    watchActive = true;
    t.sched(0, {
        if(watchActive) {
            if(~rowPattern !== lastSeenRowPattern) {
                lastSeenRowPattern = ~rowPattern;
                syncLabPlayer.value;
            };
            1;
        } {
            nil;
        };
    });

    ~stopTracksLab = {
        watchActive = false;
        if(~tracksLabWindow.notNil) { ~tracksLabWindow.onClose = nil; ~tracksLabWindow.close };
        if(labPlayer.notNil) { labPlayer.stop; labPlayer = nil };
        if(mutedTrackEnabled.notNil) {
            ~trackNames.do { |name| ~trackEnabled[name] = mutedTrackEnabled[name] };
            ~restartPbinds.value;
        };
        ~tracksLabWindow = nil;
        ~stopTracksLab = nil;
    };

    ~tracksLabWindow = Window("Tracks Lab (prototype)", Rect(40, 40, 420, 432));
    ~tracksLabWindow.alwaysOnTop_(true);
    ~tracksLabWindow.view.background = Color(0.13, 0.14, 0.16);
    ~tracksLabWindow.view.decorator = FlowLayout(~tracksLabWindow.view.bounds, 12@12, 8@8);

    StaticText(~tracksLabWindow, 380@24).string_("TRACKS LAB - one prototype track")
        .font_(Font("Arial", 14, true)).stringColor_(Color.white);
    statusText = StaticText(~tracksLabWindow, 380@20)
        .string_("Other tracks muted while this window is open.")
        .stringColor_(Color(0.7, 0.85, 0.75));
    ~tracksLabWindow.view.decorator.nextLine;

    StaticText(~tracksLabWindow, 90@24).string_("Pattern").stringColor_(Color.white);
    sourceMenu = PopUpMenu(~tracksLabWindow, 100@24)
        .items_(["Row", "Col"])
        .action_({ |m| patternSource = if(m.value == 0) { \row } { \col }; settingsChanged.value; });
    ~tracksLabWindow.view.decorator.nextLine;

    StaticText(~tracksLabWindow, 90@24).string_("Pitch").stringColor_(Color.white);
    pitchMenu = PopUpMenu(~tracksLabWindow, 140@24)
        .items_(["Fixed", "Rising at start"])
        .action_({ |m| pitchMode = if(m.value == 0) { \fixed } { \rising }; settingsChanged.value; });
    ~tracksLabWindow.view.decorator.nextLine;

// Generic labelled NumberBox row, for the plain numeric values (no need for
// Synth Lab's log/exp slider machinery here - these are simple linear
// values).
    makeNumberRow = { |label, val, lo, hi, callback|
        StaticText(~tracksLabWindow, 90@24).string_(label).stringColor_(Color.white);
        NumberBox(~tracksLabWindow, 100@24)
            .value_(val)
            .clipLo_(lo).clipHi_(hi)
            .action_({ |box| callback.value(box.value.clip(lo, hi)); settingsChanged.value; });
    };

    pitchBaseBox = makeNumberRow.value("Base pitch", basePitch, 20, 500, { |v| basePitch = v });
    pitchStepBox = makeNumberRow.value("Pitch step", pitchStep, 0, 200, { |v| pitchStep = v });
    ~tracksLabWindow.view.decorator.nextLine;

    StaticText(~tracksLabWindow, 90@24).string_("Volume").stringColor_(Color.white);
    ampMenu = PopUpMenu(~tracksLabWindow, 140@24)
        .items_(["Fixed", "Accent at start"])
        .action_({ |m| ampMode = if(m.value == 0) { \fixed } { \accent }; settingsChanged.value; });
    ~tracksLabWindow.view.decorator.nextLine;

    ampBaseBox = makeNumberRow.value("Base amp", baseAmp, 0, 2, { |v| baseAmp = v });
    accentAmpBox = makeNumberRow.value("Accent amp", accentAmp, 0, 2, { |v| accentAmp = v });
    ~tracksLabWindow.view.decorator.nextLine;

    StaticText(~tracksLabWindow, 90@24).string_("Notes/beat").stringColor_(Color.white);
    notesMenu = PopUpMenu(~tracksLabWindow, 140@24)
        .items_(["One", "Two", "Random 1 or 2"])
        .action_({ |m|
            notesMode = switch(m.value, 0, { \one }, 1, { \two }, 2, { \random });
            settingsChanged.value;
        });
    ~tracksLabWindow.view.decorator.nextLine;

// Rhythm: subdivides one scan-beat into either a single full-length hit or
// two half-length hits sharing the same pitch/amp (see buildLabPattern's
// subCount) - independent of Notes/beat above, which is about simultaneous
// pitches, not timing subdivision; the two can combine (e.g. a dyad played
// as two eighth-notes).
    StaticText(~tracksLabWindow, 90@24).string_("Rhythm").stringColor_(Color.white);
    subdivMenu = PopUpMenu(~tracksLabWindow, 140@24)
        .items_(["1 quarter", "2 eighths", "Random"])
        .action_({ |m|
            subdivMode = switch(m.value, 0, { \quarter }, 1, { \eighths }, 2, { \random });
            settingsChanged.value;
        });
    ~tracksLabWindow.view.decorator.nextLine;

// Reverb wet/level: \kick's own tiny built-in ~allpassWash tail (see
// buildLabPattern's \wet/\level comment, above). Unlike every other
// control here, these don't call settingsChanged/wait for a rebuild -
// they're plain Pfunc reads, so they're already live.
    StaticText(~tracksLabWindow, 90@24).string_("Reverb wet").stringColor_(Color.white);
    NumberBox(~tracksLabWindow, 100@24)
        .value_(reverbWet)
        .clipLo_(0).clipHi_(1).step_(0.01)
        .action_({ |box|
            reverbWet = box.value.clip(0, 1);
            { statusText.string_("Reverb wet updated (live, no rebuild needed)."); }.defer;
        });
    StaticText(~tracksLabWindow, 90@24).string_("Reverb level").stringColor_(Color.white);
    NumberBox(~tracksLabWindow, 100@24)
        .value_(reverbLevel)
        .clipLo_(0).clipHi_(1).step_(0.01)
        .action_({ |box|
            reverbLevel = box.value.clip(0, 1);
            { statusText.string_("Reverb level updated (live, no rebuild needed)."); }.defer;
        });
    ~tracksLabWindow.view.decorator.nextLine;

// Drum harmonic: \kick's own pitch-sweep ratio (how far above its settled
// drumFreq - see the file header - the attack transient starts). Same live
// treatment as Reverb wet/level above, for the same reason - one flat
// value, not something baked into the per-beat rebuild.
    StaticText(~tracksLabWindow, 90@24).string_("Drum harmonic").stringColor_(Color.white);
    NumberBox(~tracksLabWindow, 100@24)
        .value_(drumHarmonic)
        .clipLo_(1).clipHi_(8).step_(0.1)
        .action_({ |box|
            drumHarmonic = box.value.clip(1, 8);
            { statusText.string_("Drum harmonic updated (live, no rebuild needed)."); }.defer;
        });
    ~tracksLabWindow.view.decorator.nextLine;

// Stops playback now and re-arms the wait rather than rebuilding
// immediately, so even a manual "I want this to update now" click still
// lands on the clock's next rebuild instead of resyncing itself out of phase.
    Button(~tracksLabWindow, 140@26).states_([["Resync", Color.black, Color(0.65, 0.85, 0.65)]])
        .action_({ armResyncWait.value });

    ~tracksLabWindow.onClose = { ~stopTracksLab.value };
    ~tracksLabWindow.front;

    armResyncWait.value;
};

"ClockToy tracks-lab-window GUI functions loaded.".postln;
~makeTracksLabWindow.value;

)
