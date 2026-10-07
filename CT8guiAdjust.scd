// ============================================================================
// CT8guiAdjust.scd
// CLOCK TOY ADJUST WINDOW 
// ============================================================================
// Requires CT8guiClock.scd's ~makeWindow to have already run .
//
// This window changes controls only. The clock drawing/flash code lives in
// CT8guiClock.scd and is untouched by anything here.
//


(

~makeAdjustWindow = {
    var tempoSlider, tempoLabel, makeFlashButton, makeTrackButton, unbuiltColor;
    var realTimeButton, enteredTimeButton, updateSourceColors;
    var hourBox, minuteBox, refreshTime;
    var format12Button, format24Button, updateFormatColors;
    var minuteSecondsBox, updateSimSecondTime;
    var chordNameReadout;
    var adjustWidth = 420;
    var adjustHeight = 320;
    var gap = 10;
// Stack this window directly below the clock window, using its actual
// on-screen bounds rather than an unrelated hardcoded position.
    var adjustBounds = Rect(
        w.bounds.left,
        w.bounds.top - adjustHeight - gap,
        adjustWidth,
        adjustHeight
    );

    if(~adjustWindow.notNil) { ~adjustWindow.close };

// Built the same way as ~makeWindow: same Window(...) constructor, named
// resizable/border args, then .front.
    ~adjustWindow = Window("Clock Toy Adjust", adjustBounds, resizable: false, border: true)
        .front
        .alwaysOnTop_(true);
    ~adjustWindow.view.decorator = FlowLayout(~adjustWindow.view.bounds, 12@12, 8@8);



// ROW 1: metronome tempo - a slider over a fixed 60-240 BPM range (replaces
// the old NumberBox's much wider 20-400 clip), with a label showing the
// current value since a plain Slider has no numeric readout of its own.
    StaticText(~adjustWindow, 115@24).string_("Metronome  ♩ =");
    tempoLabel = StaticText(~adjustWindow, 34@24).string_(((~tempo ? 3) * 60).round(1).asString);
    tempoSlider = Slider(~adjustWindow, 150@24)
        .value_(((~tempo ? 3) * 60).clip(60, 240).linlin(60, 240, 0, 1))
        .action_({ |sl|
            var newBpm = sl.value.linlin(0, 1, 60, 240).round(1);
            ~tempo = newBpm / 60;
            if(t.notNil and: { ~tempoChange.notNil }) {
                ~tempoChange.value(t, newBpm, 12);
            } {
                if(t.notNil) { t.tempo = ~tempo };
            };
            updateSimSecondTime.value;
            tempoLabel.string_(newBpm.asString);
        });
    ~adjustWindow.view.decorator.nextLine;

// ROW 2: track on/off, one button per track in ~trackNames (CT8tracks.scd) -
// including tracks with no builder registered yet. Toggling one of those is
// harmless: ~setStartPbinds/~restartPbinds already skip any track whose
// ~trackPatterns[name] is still nil, so it just sits enabled-but-silent
// until a real builder gets registered for it. Only MT3/MT4 are left here
// now - PT1-4/BT1-2's on/off buttons moved to the Percussion + Bass
// Generator window (CT8guiPercGenerator.scd), and HT1-4/MT1-2's to the
// Harmony + Melody Generator window (CT8guiHarmonyMelodyGenerator.scd),
// each beside that track's own name. Tracks with no builder yet
// (~trackBuilders[name].isNil) show orange in both states instead of
// red/green, since there's nothing audible either way.
    unbuiltColor = Color.new255(255, 165, 0);
    makeTrackButton = { |name|
        var isBuilt = ~trackBuilders[name].notNil;
        Button(~adjustWindow, 68@24)
            .states_(
                if(isBuilt) {
                    [
                        [name.asString, Color.black, Color.red],
                        [name.asString, Color.black, Color.green]
                    ]
                } {
                    [
                        [name.asString, Color.black, unbuiltColor],
                        [name.asString, Color.black, unbuiltColor]
                    ]
                }
            )
            .value_(if(~trackEnabled[name] == false) { 0 } { 1 })
            .action_({ |b|
                ~trackEnabled[name] = (b.value == 1);
                ~syncTrackPlayer.(name);
            });
    };

// No "Harm" row any more - HT1-4's on/off buttons moved into the new
// Harmony + Melody Generator window (CT8guiHarmonyMelodyGenerator.scd),
// beside each track's name, same reason PT1-4/BT1-2's moved out of here
// earlier. "Mel" only covers MT3/MT4 now - MT1/MT2 moved to that same new
// window too.
    StaticText(~adjustWindow, 40@24).string_("Mel");
    ~trackNames.select({ |name| ["MT3", "MT4"].includes(name.asString) }).do(makeTrackButton);
    ~adjustWindow.view.decorator.nextLine;

// ROW 6: clock source
    realTimeButton = Button(~adjustWindow, 120@24)
        .states_([["Real Time", Color.black, Color.grey]]);
    enteredTimeButton = Button(~adjustWindow, 120@24)
        .states_([["Entered Time", Color.black, Color.grey]]);
    ~adjustWindow.view.decorator.nextLine;

// ROW 7: Hour / Min / Sim Sec entry fields
// How many real-world seconds one simulated minute should take, while in
// "Entered Time" mode. Recomputed into ~secondTime (a beat count) whenever
// this value or the tempo changes, since t.sched waits in beats, not seconds.
    ~minuteSeconds = ~minuteSeconds ? 30;
    updateSimSecondTime = {
        if(~runningRealTime.not) {
            ~secondTime = ~minuteSeconds * (~tempo ? 3) / 60;
        };
    };
    StaticText(~adjustWindow, 34@24).string_("Hour");
    hourBox = NumberBox(~adjustWindow, 52@24).value_(~hours ? 12).clipLo_(0).clipHi_(23).step_(1);
    StaticText(~adjustWindow, 28@24).string_("Min");
    minuteBox = NumberBox(~adjustWindow, 52@24).value_(~minutes ? 0).clipLo_(0).clipHi_(59).step_(1);
    StaticText(~adjustWindow, 55@24).string_("Sim Sec");
    minuteSecondsBox = NumberBox(~adjustWindow, 70@24)
        .value_(~minuteSeconds)
        .clipLo_(0.1).clipHi_(3600).step_(1)
        .action_({ |box|
            ~minuteSeconds = box.value.clip(0.1, 3600);
            updateSimSecondTime.value;
        });
    ~adjustWindow.view.decorator.nextLine;

    refreshTime = {
        if(~runningRealTime == false) {
            ~hours = hourBox.value.asInteger.clip(0, 23);
            ~minutes = minuteBox.value.asInteger.clip(0, 59);
            ~fakeSecond = 0;
            ~stopPbinds.value;
            ~getClockRhythm.value;
            ~displayClock.value;
            ~getLineSegOrder.value;
            ~getColumnSegOrder.value;
            ~updatePbinds.value;
            ~restartPbinds.value;
            ~rebuildFlashPatterns.value;
            ~restartFlashPlayers.value;
        };
    };

    hourBox.action_({ refreshTime.value });
    minuteBox.action_({ refreshTime.value });

// Recolor the source buttons (active = green, inactive = red) and the three
// entry fields that only matter in "Entered Time" mode (green = editable,
// red = ignored while the real system clock is driving the display).
    updateSourceColors = {
        if(~runningRealTime) {
            realTimeButton.states_([["Real Time", Color.black, Color.green]]);
            enteredTimeButton.states_([["Entered Time", Color.black, Color.red]]);
            minuteSecondsBox.background_(Color.red);
            hourBox.background_(Color.red);
            minuteBox.background_(Color.red);
        } {
            realTimeButton.states_([["Real Time", Color.black, Color.red]]);
            enteredTimeButton.states_([["Entered Time", Color.black, Color.green]]);
            minuteSecondsBox.background_(Color.green);
            hourBox.background_(Color.green);
            minuteBox.background_(Color.green);
        };
    };
    updateSourceColors.value;

    realTimeButton.action_({
        ~runningRealTime = true;
        ~fakeSecond = 0;
        ~secondTime = 1;
        ~hours = Date.getDate.localtime.hour;
        ~minutes = Date.getDate.localtime.minute;
        hourBox.value_(~hours); minuteBox.value_(~minutes);
        ~stopPbinds.value;
        ~getClockRhythm.value;
        ~displayClock.value;
        ~getLineSegOrder.value;
        ~getColumnSegOrder.value;
        ~updatePbinds.value;
        ~restartPbinds.value;
        ~rebuildFlashPatterns.value;
        ~restartFlashPlayers.value;
        updateSourceColors.value;
    });

    enteredTimeButton.action_({
        ~runningRealTime = false;
        ~fakeSecond = 0;
        updateSimSecondTime.value;
        refreshTime.value;
        updateSourceColors.value;
    });

// ROW 8: clock display format
    format24Button = Button(~adjustWindow, 120@24)
        .states_([["24 Hour", Color.black, Color.grey]]);
    format12Button = Button(~adjustWindow, 120@24)
        .states_([["12 Hour", Color.black, Color.grey]]);

// Recolor the display-format buttons (current format = green, other = red).
    updateFormatColors = {
        if(~twelveHourClock) {
            format12Button.states_([["12 Hour", Color.black, Color.green]]);
            format24Button.states_([["24 Hour", Color.black, Color.red]]);
        } {
            format12Button.states_([["12 Hour", Color.black, Color.red]]);
            format24Button.states_([["24 Hour", Color.black, Color.green]]);
        };
    };
    updateFormatColors.value;

    format24Button.action_({
        ~twelveHourClock = false;
        ~stopPbinds.value;
        ~getClockRhythm.value;
        ~displayClock.value;
        ~getLineSegOrder.value;
        ~getColumnSegOrder.value;
        ~updatePbinds.value;
        ~restartPbinds.value;
        ~rebuildFlashPatterns.value;
        ~restartFlashPlayers.value;
        updateFormatColors.value;
    });

    format12Button.action_({
        ~twelveHourClock = true;
        ~stopPbinds.value;
        ~getClockRhythm.value;
        ~displayClock.value;
        ~getLineSegOrder.value;
        ~getColumnSegOrder.value;
        ~updatePbinds.value;
        ~restartPbinds.value;
        ~rebuildFlashPatterns.value;
        ~restartFlashPlayers.value;
        updateFormatColors.value;
    });
    ~adjustWindow.view.decorator.nextLine;


// ROW 9: row/col clock-face flash on/off - independent of any track now
// (~rowFlashEnabled/~colFlashEnabled/~syncFlashPlayer, CT8guiClock.scd);
// on by default, stays on regardless of whether any track is making sound.
    makeFlashButton = { |which, label|
        var isEnabled = { if(which == \row) { ~rowFlashEnabled } { ~colFlashEnabled } };
        Button(~adjustWindow, 70@24)
            .states_([
                [label, Color.black, Color.red],
                [label, Color.black, Color.green]
            ])
            .value_(if(isEnabled.value == false) { 0 } { 1 })
            .action_({ |b|
                var enabled = (b.value == 1);
                if(which == \row) { ~rowFlashEnabled = enabled } { ~colFlashEnabled = enabled };
                ~syncFlashPlayer.(which);
// Clear the flash overlay immediately when turned off, rather than waiting
// for the next event to (not) flash.
                if(enabled.not) {
                    if(which == \row) {
                        ~rowFlashActive = Array.fill(5, false);
                    } {
                        ~columnFlashActive = Array.fill(12, false);
                    };
                    4.do { |i| ~digitPanel[i].refresh };
                };
            });
    };

    StaticText(~adjustWindow, 40@24).string_("Colour");
    makeFlashButton.(\row, "Row Clr");
    makeFlashButton.(\col, "Col Clr");
    ~adjustWindow.view.decorator.nextLine;

// ROW 10: hold the chord progression on one hand-picked chord, for pattern
// testing (~chordHeld/~checkForNewChordBar, CT8harmonySelect.scd) - while
// held, the bar-boundary check still resets its own beat counter every
// bar, it just skips advancing ~currentChord/~nextChord, so releasing it
// lands cleanly on the next natural boundary rather than firing an overdue
// advance immediately. Set/Chord write ~currentChord directly any time
// (not gated on Hold being on), the same way the Hour/Minute boxes above
// write the displayed time directly - so dialing in a chord before
// pressing Hold, or nudging it while already held, both just work.
    StaticText(~adjustWindow, 70@24).string_("Hold Chord");
    Button(~adjustWindow, 70@24)
        .states_([
            ["Running", Color.black, Color.green],
            ["Held", Color.black, Color.red]
        ])
        .value_(if(~chordHeld == true) { 1 } { 0 })
        .action_({ |b| ~chordHeld = (b.value == 1); });
    StaticText(~adjustWindow, 30@24).string_("Set");
    NumberBox(~adjustWindow, 40@24)
        .value_(~chordSet ? 0)
        .clipLo_(0).clipHi_(~chords.size - 1).step_(1)
        .action_({ |box|
            var set = box.value.clip(0, ~chords.size - 1).asInteger;
            var idx = (~currentChordNumber ? 1).clip(1, ~chords[set].size);
            ~chordSet = set;
            ~lastChord = idx;
            ~currentChordNumber = idx;
            ~currentChord = ~chords[set][idx - 1];
            ~nextChord = ~computeNextChord.value;
            ~onChordChanged.value;
        });
    StaticText(~adjustWindow, 40@24).string_("Chord");
    NumberBox(~adjustWindow, 40@24)
        .value_(~currentChordNumber ? 1)
        .clipLo_(1).clipHi_(7).step_(1)
        .action_({ |box|
            var set = ~chordSet ? 0;
            var idx = box.value.clip(1, ~chords[set].size).asInteger;
            ~lastChord = idx;
            ~currentChordNumber = idx;
            ~currentChord = ~chords[set][idx - 1];
            ~nextChord = ~computeNextChord.value;
            ~onChordChanged.value;
        });
// Chord NAME readout (e.g. "Cmaj7"), not just the raw Set/Chord numbers -
// ~onChordChanged (called here, by the two boxes above, and by
// ~checkForNewChordBar itself, CT8harmonySelect.scd, whenever the chord
// changes for ANY reason - Markov-advanced or hand-overridden) is the one
// place that knows how to read it back out of ~chordNames[~chordSet]
// [~currentChordNumber - 1], so this stays in sync regardless of which of
// those changed it. Black text - this window has no explicit dark
// background, same as every other label here.
    chordNameReadout = StaticText(~adjustWindow, 90@24)
        .stringColor_(Color.black);
    ~onChordChanged = {
// Called from the TempoClock thread too (~checkForNewChordBar), and Qt
// widgets must only be touched from the GUI thread - so defer the update.
        var name = ~chordNames[~chordSet][~currentChordNumber - 1];
        { chordNameReadout.string_(name) }.defer;
    };
    ~onChordChanged.value;
    ~adjustWindow.view.decorator.nextLine;
};

"ClockToy adjust-window GUI functions loaded.".postln;

)
