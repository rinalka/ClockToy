// ============================================================================
// CT8fakeData.scd
// FAKE INPUT-DATA CONTROL PANEL for the planned "Daily Piece" generative mode
// ============================================================================
//
// Stand-in for the four real data tables sketched in CT8main.scd's FUTURE
// DIRECTION note (Actions, heart rate, Mood, Weather), so the generative
// code can be developed and tested before any real data exists.
//
// Same editing technique as sc/Riff3/mySectionPlotControlPanel.scd's
// ~makeAPlot: a Plotter in editMode inside a CompositeView: click-and-drag
// on the plot to set a value, which gets written straight back into a
// backing Array via editFunc.
//
// Scaled down for quick iteration: instead of the real design's 96
// 15-minute slots across a 24-hour day, ~fakeSlots gives Actions/Mood/
// Weather a small number of slots representing a few minutes. Heart rate
// gets its own, finer-grained sample count (~fakeHeartRateSamples) over
// that same span, echoing the real design's much shorter (10-second)
// sampling interval.
//
// This file is independent of CT8gui/CT8syn/CT8main - evaluate it on its own.
(
~fakeSlots = 16;             // Actions/Mood/Weather: one value per slot
~fakeHeartRateSamples = 60;  // heart rate: one value per sample, finer grain

// Actions and Weather are edited as plain integers; these legends say what
// each integer currently means - keep them in view while dragging points.
~actionLegend = [
    \sleepDeep, \sleepLight, \REM, \inBedAwake, \reading,
    \eating, \walking, \sitting
];
~weatherLegend = [\clear, \cloudy, \rain, \storm, \snow, \fog];

// Mood is a plain numeric scale, not a legend: -5 (bad) to 5 (good).
~moodLo = -5; ~moodHi = 5;
// Heart rate in BPM.
~heartRateLo = 40; ~heartRateHi = 180;

// Flat, sensible starting values so the plots aren't blank or random.
~resetFakeData = {
    ~fakeActions = Array.fill(~fakeSlots, { 0 });       // sleepDeep
    ~fakeMood = Array.fill(~fakeSlots, { 0 });          // neutral
    ~fakeWeather = Array.fill(~fakeSlots, { 0 });       // clear
    ~fakeHeartRate = Array.fill(~fakeHeartRateSamples, { 65 });
};
~resetFakeData.value;

// One editable plot for one backing Array. lo/hi clip what a drag can set,
// so Actions/Weather stay valid legend indices and Mood/heart rate stay
// within their sensible numeric ranges.
~makeFakeDataPlot = { |parent, labelString, arrayToPlot, lo, hi|
    var view, plotter;

    StaticText(parent, 300@16)
        .string_(labelString)
        .align_(\left)
        .font_(Font("Monaco", 12));

    view = CompositeView(parent, 300@90).background_(Color.rand(0.7));
    plotter = Plotter(" ", parent: view);
    plotter.value = arrayToPlot;
    plotter.editMode = true;
    plotter.editFunc = { |plotter, plotIndex, index, val, x, y|
        arrayToPlot[index] = val.round.clip(lo, hi);
    };
    plotter.plotMode = \plines;
    plotter.setProperties(
        \fontColor, Color.black,
        \plotColor, Color.grey(0.25, 0.6),
        \backgroundColor, Color.rand(0.7, 0.9),
        \gridColorX, Color.grey,
        \gridColorY, Color.grey,
    );
};

~makeFakeDataWindow = {
    var postButton, resetButton;

    if(~fakeDataWindow.notNil) { ~fakeDataWindow.close };

    ~fakeDataWindow = Window("Fake Daily-Data Control Panel", Rect(200, 200, 340, 580), resizable: true, border: true)
        .background_(Color.grey(0.95))
        .front
        .alwaysOnTop_(true);
    ~fakeDataWindow.view.decorator = FlowLayout(~fakeDataWindow.view.bounds, 8@8, 4@4);

    StaticText(~fakeDataWindow, 300@16)
      //  .string_("Actions legend: " ++ ~actionLegend.asString)
        .font_(Font("Monaco", 10));
    ~makeFakeDataPlot.(~fakeDataWindow, "Actions (drag = legend index)", ~fakeActions, 0, ~actionLegend.size - 1);

    StaticText(~fakeDataWindow, 300@16)
        //.string_("Heart rate (BPM)")
        .font_(Font("Monaco", 10));
    ~makeFakeDataPlot.(~fakeDataWindow, "Heart Rate", ~fakeHeartRate, ~heartRateLo, ~heartRateHi);

    StaticText(~fakeDataWindow, 300@16)
       // .string_("Mood (-5 bad .. 5 good)")
        .font_(Font("Monaco", 10));
    ~makeFakeDataPlot.(~fakeDataWindow, "Mood", ~fakeMood, ~moodLo, ~moodHi);

    StaticText(~fakeDataWindow, 300@16)
       // .string_("Weather legend: " ++ ~weatherLegend.asString)
        .font_(Font("Monaco", 10));
    ~makeFakeDataPlot.(~fakeDataWindow, "Weather (drag = legend index)", ~fakeWeather, 0, ~weatherLegend.size - 1);

// Rebuilds the whole window against the freshly-reset arrays - simplest way
// to refresh all four plots at once without keeping external references to
// each Plotter instance.
    resetButton = Button(~fakeDataWindow, 145@24)
        .states_([["Reset to Flat", Color.black, Color.yellow]])
        .action_({ ~resetFakeData.value; ~makeFakeDataWindow.value; });

    postButton = Button(~fakeDataWindow, 145@24)
        .states_([["Post Current Values", Color.black, Color.green]])
        .action_({
            ("Actions: " + ~fakeActions).postln;
            ("Heart rate: " + ~fakeHeartRate).postln;
            ("Mood: " + ~fakeMood).postln;
            ("Weather: " + ~fakeWeather).postln;
        });
};

// Temporarily not auto-displayed while the Percussion + Bass Generator's
// own per-track layout is being reworked - ~makeFakeDataWindow itself is
// untouched, just not auto-called here; evaluate it by hand
// (~makeFakeDataWindow.value) if you need it meanwhile.
// ~makeFakeDataWindow.value;

"Fake daily-data control panel ready (not auto-displayed). Drag points on each plot to edit; use Post Current Values to see the arrays.".postln;
)
