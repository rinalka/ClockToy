// ============================================================================
// CT8guiSynth.scd
// CLOCKTOY - SYNTH CONTROL WINDOW (CT8)
// ============================================================================
//
// Third of the three GUI files (CT8guiClock -> CT8guiAdjust -> CT8guiSynth),
// which were split out of the original single CT8gui.scd. Requires
// CT8guiAdjust.scd's ~makeAdjustWindow to have already run (~makeSynthWindow
// reads ~adjustWindow.bounds to position itself alongside it), and reads
// ~availableSynths/~synthParams/~synthParamSpecs from CT8synths.scd - but
// only when actually CALLED (CT8main.scd calls it after CT8synths.scd is
// loaded), so evaluating this file itself has no ordering requirement
// against CT8synths.
// CT8main.scd's ~loadAllGuiFiles loads all three (plus CT8fakeData.scd) in
// order; use ~loadGuiFile.("CT8guiSynth.scd") to reload just this one.
//
// Two rows of Row/Col Start/Cell menus (pick any synth from ~availableSynths,
// CT8synths.scd, for any of the four slots), followed by one row per synth
// in that same table, built generically from its [paramName, lo, hi,
// default, step] specs - a synth with no param specs (e.g. plucking/hat
// right now) just gets a placeholder row. Adding a synth, or adding a live
// parameter to an existing one, means editing ~availableSynths only -
// nothing in here needs to change. CT8tracks.scd reads ~synthParams fresh
// for every note via Pfunc, so anything changed here takes effect
// immediately, no restart needed.
//


(

~makeSynthWindow = {
    var rowStartMenu, rowCellMenu, colStartMenu, colCellMenu, rebuildPatterns;
    var synthNames = ~availableSynths.collect { |row| row[0] };
    var maxParams = ~availableSynths.collect({ |row| row.size - 1 }).maxItem.max(1);
    var totalRows = ~availableSynths.size + 2; // +2 for the Row/Col menu rows
// Wide enough for a synth name plus maxParams (label + box) pairs; tall
// enough for one row per synth plus the two menu rows, each forced onto its
// own line below via .nextLine so this doesn't depend on width-based wrap.
    var synthWidth = 78 + (maxParams * 102) + 40;
    var synthHeight = 24 + (totalRows * 24) + ((totalRows - 1) * 8) + 20;
    var gap = 10;
// Sit to the right of the adjust window, sharing its top edge.
    var synthBounds = Rect(
        ~adjustWindow.bounds.left + ~adjustWindow.bounds.width + gap,
        ~adjustWindow.bounds.top,
        synthWidth,
        synthHeight
    );

// ~rowStartSynth/~rowCellSynth/~colStartSynth/~colCellSynth's defaults now
// live in CT8tracks.scd (this window isn't currently being built - see
// CT8main.scd - so they can't depend on this function ever running).

    if(~synthWindow.notNil) { ~synthWindow.close };

    ~synthWindow = Window("Synth Controls", synthBounds, resizable: false, border: true)
        .front
        .alwaysOnTop_(true);
    ~synthWindow.view.decorator = FlowLayout(~synthWindow.view.bounds, 12@12, 8@8);

// ROW/COL -> SYNTH ASSIGNMENT: pick any installed synth for each of the four
// slots (Row Start, Row Cell, Col Start, Col Cell). ~buildRowPattern and
// ~buildColumnPattern (CT8syn) read ~rowStartSynth/~rowCellSynth/
// ~colStartSynth/~colCellSynth fresh, so reassigning here and rebuilding is
// all that's needed - any combination is valid, e.g. baseD paired with hat.
    rebuildPatterns = {
        ~stopPbinds.value;
        ~updatePbinds.value;
        ~restartPbinds.value;
    };

    StaticText(~synthWindow, 30@24).string_("Row:");
    StaticText(~synthWindow, 40@24).string_("Start");
    rowStartMenu = PopUpMenu(~synthWindow, 90@24)
        .items_(synthNames.collect(_.asString))
        .value_(synthNames.indexOf(~rowStartSynth) ? 0)
        .action_({ |menu|
            ~rowStartSynth = synthNames[menu.value];
            rebuildPatterns.value;
        });
    StaticText(~synthWindow, 34@24).string_("Cell");
    rowCellMenu = PopUpMenu(~synthWindow, 90@24)
        .items_(synthNames.collect(_.asString))
        .value_(synthNames.indexOf(~rowCellSynth) ? 0)
        .action_({ |menu|
            ~rowCellSynth = synthNames[menu.value];
            rebuildPatterns.value;
        });
    ~synthWindow.view.decorator.nextLine;

    StaticText(~synthWindow, 30@24).string_("Col:");
    StaticText(~synthWindow, 40@24).string_("Start");
    colStartMenu = PopUpMenu(~synthWindow, 90@24)
        .items_(synthNames.collect(_.asString))
        .value_(synthNames.indexOf(~colStartSynth) ? 0)
        .action_({ |menu|
            ~colStartSynth = synthNames[menu.value];
            rebuildPatterns.value;
        });
    StaticText(~synthWindow, 34@24).string_("Cell");
    colCellMenu = PopUpMenu(~synthWindow, 90@24)
        .items_(synthNames.collect(_.asString))
        .value_(synthNames.indexOf(~colCellSynth) ? 0)
        .action_({ |menu|
            ~colCellSynth = synthNames[menu.value];
            rebuildPatterns.value;
        });
    ~synthWindow.view.decorator.nextLine;

// PER-SYNTH PARAMETER ROWS: one row per entry in ~availableSynths, built
// straight from its param specs. ~synthParams[synthName][paramName] is what
// ~getSynthParam (CT8syn) actually reads when playing that synth.
    ~availableSynths.do { |row|
        var synthName = row[0];
        var paramSpecs = row[1..];

        StaticText(~synthWindow, 70@24).string_(synthName.asString);

        if(paramSpecs.isEmpty) {
            StaticText(~synthWindow, 240@24).string_("(no controls yet)");
        } {
            paramSpecs.do { |spec|
                var pname = spec[0];
                var lo = spec[1];
                var hi = spec[2];
                var stepSize = spec[4];

                StaticText(~synthWindow, 34@24).string_(pname.asString);
                NumberBox(~synthWindow, 60@24)
                    .value_(~synthParams[synthName][pname])
                    .clipLo_(lo).clipHi_(hi).step_(stepSize)
                    .action_({ |box|
                        ~synthParams[synthName][pname] = box.value.clip(lo, hi);
                    });
            };
        };

        ~synthWindow.view.decorator.nextLine;
    };
};

"ClockToy synth-control-window GUI functions loaded.".postln;

)
