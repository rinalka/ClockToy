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
    var tempoSlider, tempoLabel, makeTrackButton, makeSoundButton, makeFlashButton, unbuiltColor;
    var realTimeButton, enteredTimeButton, updateSourceColors;
    var hourBox, minuteBox, refreshTime;
    var format12Button, format24Button, updateFormatColors;
    var minuteSecondsBox, updateSimSecondTime;
    var adjustWidth = 420;
    var adjustHeight = 350;
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

// ROWS 2-5: track on/off, one button per track in ~trackNames (CT8tracks.scd) -
// including tracks with no builder registered yet (PT4, HT2-4, MT2-4).
// Toggling one of those on/off is harmless: ~setStartPbinds/~restartPbinds
// already skip any track whose ~trackPatterns[name] is still nil, so it just
// sits enabled-but-silent until a real builder gets registered for it.
// Grouped into the same four categories as ~trackNames' own comments
// (percussion/bass/harmony/melody). Tracks with no builder registered yet
// (~trackBuilders[name].isNil) show orange in both states instead of
// red/green - they can still be toggled (harmlessly, per the comment above),
// but there's nothing audible either way, so the color says "not wired up
// yet" rather than "off"/"on".
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

// PT1/PT2 uniquely also drive the clock-face flash/background color from
// inside their own Pbind (\updateGUI, CT8tracks.scd) - separate buttons (Snd
// on the Perc row, Clr on their own Colour row below) rather than the one
// combined on/off every other track still has, so sound and flash can be
// silenced separately. ~trackEnabled[name] still gates sound (\type -> \rest
// when off); the new ~trackFlashEnabled[name] gates the flash call - both go
// through ~syncTrackPlayer, which keeps the shared EventStreamPlayer running
// as long as either one is wanted (~trackShouldPlay, CT8tracks.scd).
    makeSoundButton = { |name|
        Button(~adjustWindow, 58@24)
            .states_([
                [(name.asString ++ " Snd"), Color.black, Color.red],
                [(name.asString ++ " Snd"), Color.black, Color.green]
            ])
            .value_(if(~trackEnabled[name] == false) { 0 } { 1 })
            .action_({ |b|
                ~trackEnabled[name] = (b.value == 1);
                ~syncTrackPlayer.(name);
            });
    };

    makeFlashButton = { |name|
        Button(~adjustWindow, 58@24)
            .states_([
                [(name.asString ++ " Clr"), Color.black, Color.red],
                [(name.asString ++ " Clr"), Color.black, Color.green]
            ])
            .value_(if(~trackFlashEnabled[name] == false) { 0 } { 1 })
            .action_({ |b|
                ~trackFlashEnabled[name] = (b.value == 1);
                ~syncTrackPlayer.(name);
// Clear the flash overlay immediately when turned off, rather than waiting
// for the next event to (not) flash - matches the old combined button's
// behavior.
                if(~trackFlashEnabled[name].not) {
                    if(name == \PT1) {
                        ~rowFlashActive = Array.fill(5, false);
                        4.do { |i| ~digitPanel[i].refresh };
                    };
                    if(name == \PT2) {
                        ~columnFlashActive = Array.fill(12, false);
                        4.do { |i| ~digitPanel[i].refresh };
                    };
                };
            });
    };

    StaticText(~adjustWindow, 40@24).string_("Perc");
    makeSoundButton.(\PT1);
    makeSoundButton.(\PT2);
    ~trackNames.select({ |name| name.asString.beginsWith("PT") and: { (name == \PT1).not and: { (name == \PT2).not } } }).do(makeTrackButton);
    ~adjustWindow.view.decorator.nextLine;

    StaticText(~adjustWindow, 40@24).string_("Bass");
    ~trackNames.select({ |name| name.asString.beginsWith("BT") }).do(makeTrackButton);
    ~adjustWindow.view.decorator.nextLine;

    StaticText(~adjustWindow, 40@24).string_("Harm");
    ~trackNames.select({ |name| name.asString.beginsWith("HT") }).do(makeTrackButton);
    ~adjustWindow.view.decorator.nextLine;

    StaticText(~adjustWindow, 40@24).string_("Mel");
    ~trackNames.select({ |name| name.asString.beginsWith("MT") }).do(makeTrackButton);
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
        updateFormatColors.value;
    });
    ~adjustWindow.view.decorator.nextLine;
    

// ROW 9: PT1/PT2 flash/background color on/off - kept separate
// from the other track rows, at the bottom of the window, since it's a
// display-only toggle rather than a track like the rows above.
    StaticText(~adjustWindow, 40@24).string_("Colour");
    makeFlashButton.(\PT1);
    makeFlashButton.(\PT2);
    ~adjustWindow.view.decorator.nextLine;
};

"ClockToy adjust-window GUI functions loaded.".postln;

)
