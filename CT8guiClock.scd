// ============================================================================
// CT8guiClock.scd
// CLOCKTOY - CLOCK GEOMETRY, DISPLAY, EVENT GENERATION, AND TIME CHANGES
// ============================================================================
//
// This file owns the visual model of the four-digit seven-segment clock and the
// conversion from that geometry into abstract musical events. Its central
// product is ~clockEvents: an ordered Array of lit cells. Each event records a
// row, panel, segment, and an abstract role (\rowStart or \cell). The tracks
// file (CT8tracks.scd) decides what those roles sound like; this file owns
// what they look like, including the row/col flash players themselves
// (~buildRowFlashPattern/~buildColFlashPattern and their lifecycle) - flashing
// is independent of any track, on by default, switchable via
// ~rowFlashEnabled/~colFlashEnabled regardless of whether PT1/PT2 are
// producing sound.
//
// First of the three GUI files (CT8guiClock -> CT8guiAdjust -> CT8guiSynth),
// which were split out of the original single CT8gui.scd. CT8main.scd's
// ~loadAllGuiFiles loads all three (plus CT8fakeData.scd) in order; use
// ~loadGuiFile.("CT8guiClock.scd") to reload just this one.
//


(

// ---------------------------------------------------------------------------
// WINDOW CREATION
// ---------------------------------------------------------------------------
// Build the application window and its four digit panels, plus two thin
// black UserViews used purely as divider bars between them.
~makeWindow = {
// Close earlier SuperCollider windows before creating a fresh ClockToy display.
    Window.closeAll;
    w = Window("My Daily Digital Clock", Rect(1400, 400, 500, 212), resizable: true, border: true)
        .background_(Color.black)
        .front
        .alwaysOnTop_(true);
    w.view.decorator = FlowLayout(w.bounds, 4@4, 4@4);
    UserView(w, 492@1).background_(Color.black);
 //   UserView(w, 50@200).background_(Color.black);

    ~cellBaseColor = Color.new255(0x22, 0x22, 0x22); // web hex #222, dark grey
    ~rowFlashColor = Color.new255(0x22, 0x22, 0x50);
    ~columnFlashColor = Color.new255(0x50, 0x22, 0x22);
    ~segmentOnColor = Color.new255(0xcc, 0xcc, 0xcc); // very light grey, steady "lit" segment

    // Drawing state for four 5x3 digit grids and seven dashes per digit.
    ~activeSegments = Array.fill(4, { Array.fill(7, false) });
    ~dashFlashActive = Array.fill(4, { Array.fill(7, false) });
    ~dashFlashColor = Array.fill(4, { Array.fill(7, Color.black) });
    ~dashFlashSerial = Array.fill(4, { Array.fill(7, 0) });
    ~rowFlashActive = Array.fill(5, false);
    ~columnFlashActive = Array.fill(12, false);

// Create the four UserViews that represent HH:MM digit positions.
    ~digitPanel = 4.collect { |i|
        var view = UserView(w, 120@200).background_(~cellBaseColor);
        view.drawFunc = { |userView| ~drawPanel.value(i, userView) };
        view;
    };
    UserView(w, 546@40).background_(Color.black);
};

// ---------------------------------------------------------------------------
// TIME -> FOUR DISPLAY DIGITS
// ---------------------------------------------------------------------------
// Convert hours/minutes into four decimal digits: tens-hours, hours, tens-minutes, minutes.
~getClockDigits = { |hours, minutes|
    var shownHours = hours;
    if(~twelveHourClock == true) {
        shownHours = hours % 12;
        if(shownHours == 0) { shownHours = 12 };
    };
    [shownHours.div(10), shownHours % 10, minutes.div(10), minutes % 10]
};

// ---------------------------------------------------------------------------
// LEGACY FIVE-ROW RHYTHM COUNTS (vestigial)
// ---------------------------------------------------------------------------
// Count how many seven-segment strokes occupy each of the five visual rows.
// Still called on every time-change (see ~checkForNewMinute and the adjust
// window's buttons below), but nothing else in the project reads its result,
// ~currentRythm - the actual musical scan is ~getLineSegOrder/~getColumnSegOrder.
~getClockRhythm = {
// Per-digit row counts. Each entry describes contribution to the five display rows.
     var digitalClockLines = [
        [1,2,0,2,1], // 0
        [0,1,0,1,0], // 1
        [1,1,1,1,1], // 2
        [1,1,1,1,1], // 3
        [0,2,1,1,0], // 4
        [1,1,1,1,1], // 5
        [1,1,1,2,1], // 6
        [1,1,0,1,0], // 7
        [1,2,1,2,1], // 8
        [1,2,1,1,1]  // 9
    ];
// Read the current global time as four display digits.
    var digits = ~getClockDigits.value(~hours, ~minutes);
// Accumulator for the combined row counts across all four digits.
    var result = [0, 0, 0, 0, 0];

    for(0, 3, { |i|
        result = result + digitalClockLines[digits[i]];
    });
// Keep only non-empty rows; "Rythm" spelling is retained from the source file.
    ~currentRythm = result.select({ |elem| elem != 0 });
};


// ---------------------------------------------------------------------------
// LIT SEGMENTS -> ABSTRACT CLOCK EVENTS
// ---------------------------------------------------------------------------
// Build the ordered musical cell stream from all currently lit clock segments.
~getLineSegOrder = {
// Seven on/off flags for each decimal digit, indexed by segment number 0..6.
    var linePattern = [
        [1, 1, 1, 0, 1, 1, 1], // 0
        [0, 0, 1, 0, 0, 1, 0], // 1
        [1, 0, 1, 1, 1, 0, 1], // 2
        [1, 0, 1, 1, 0, 1, 1], // 3
        [0, 1, 1, 1, 0, 1, 0], // 4
        [1, 1, 0, 1, 0, 1, 1], // 5
        [1, 1, 0, 1, 1, 1, 1], // 6
        [1, 0, 1, 0, 0, 1, 0], // 7
        [1, 1, 1, 1, 1, 1, 1], // 8
        [1, 1, 1, 1, 0, 1, 1]  // 9
    ];

// Physical scan order of all 28 possible strokes, grouped into five visual
// rows of 4, 8, 4, 8, 4 cells each, as [panel, segment] pairs.
    var dashIndices = [
        [0,0], [1,0], [2,0], [3,0],
        [0,1], [0,2], [1,1], [1,2], [2,1], [2,2], [3,1], [3,2],
        [0,3], [1,3], [2,3], [3,3],
        [0,4], [0,5], [1,4], [1,5], [2,4], [2,5], [3,4], [3,5],
        [0,6], [1,6], [2,6], [3,6]
    ];
// Number of possible segment positions in each of the five visual rows.
    var rowLengths = [4, 8, 4, 8, 4];
// Read the current global time as four display digits.
    var digits = ~getClockDigits.value(~hours, ~minutes);
// Expand the four digits into four seven-element on/off segment patterns.
    var result = digits.collect { |digit| linePattern[digit] };
    var currentIndex = 0;
// Growable temporary collection used while finding active cells.
    var events = List.new;

// A blank leading (tens-of-hours) panel (12-hour mode only) contributes no
// lit segments, so it produces no audio events and never flashes.
    if(~twelveHourClock and: { digits[0] == 0 }) { result[0] = Array.fill(7, 0) };

// Walk each visual row independently: the first lit cell in a non-empty row
// becomes \rowStart, every later lit cell in that row becomes \cell.
    rowLengths.do { |length, row|
// Becomes false after the first active segment in this row has been emitted.
        var firstInRow = true;

        length.do {
// Look up [panel, segment] for the current physical scan position.
            var pair = dashIndices[currentIndex];
            var panel = pair[0];
            var segment = pair[1];

// Only lit segments become musical events.
            if(result[panel][segment] == 1) {
// Record geometry plus an abstract role rather than naming a SynthDef here.
                events.add((
                    row: row,
                    panel: panel,
                    segment: segment,
// First lit cell in a row is \rowStart; subsequent lit cells are \cell.
                    role: if(firstInRow) { \rowStart } { \cell }
                ));
                firstInRow = false;
            };

            currentIndex = currentIndex + 1;
        };
    };

// Publish the completed event stream for CT8tracks.scd to interpret.
    ~clockEvents = events.asArray;

// SHARED STATE, read by CT8tracks.scd: ~rowPattern is a plain Array (not a
// Pbind - PT1's Pbind is ~trackPatterns[\PT1]), the generic, stable name
// every track's generator reads as shared input. ~numBeats tracks its
// length, since \dur is 1 for every event/beat here. Deliberately kept here
// rather than declared in the tracks file - the geometry/segment data this
// scan needs only lives in this file, so this is the only place it can
// actually be computed; CT8tracks.scd's builders just read the result.
    ~rowPattern = ~clockEvents;
    ~numBeats = ~rowPattern.size;

// Kept only for backward compatibility/inspection - each event's panel and
// segment index, flattened out of ~clockEvents.
    ~dashPanNum = ~clockEvents.collect { |event| event[\panel] };
    ~dashSegNum = ~clockEvents.collect { |event| event[\segment] };

    ~clockEvents;
};


// ---------------------------------------------------------------------------
// LIT SEGMENTS -> COLUMN-ORDERED EVENTS FOR TRACK TWO
// ---------------------------------------------------------------------------
// Scan the three visual columns within each digit, giving twelve columns total.
// The first lit segment in each column is \columnStart; the rest are \columnCell.
~getColumnSegOrder = {
    var linePattern = [
        [1, 1, 1, 0, 1, 1, 1], // 0
        [0, 0, 1, 0, 0, 1, 0], // 1
        [1, 0, 1, 1, 1, 0, 1], // 2
        [1, 0, 1, 1, 0, 1, 1], // 3
        [0, 1, 1, 1, 0, 1, 0], // 4
        [1, 1, 0, 1, 0, 1, 1], // 5
        [1, 1, 0, 1, 1, 1, 1], // 6
        [1, 0, 1, 0, 0, 1, 0], // 7
        [1, 1, 1, 1, 1, 1, 1], // 8
        [1, 1, 1, 1, 0, 1, 1]  // 9
    ];
    var segmentColumns = [
        [1, 4],       // left vertical column
        [0, 3, 6],    // centre horizontal column
        [2, 5]        // right vertical column
    ];
    var digits = ~getClockDigits.value(~hours, ~minutes);
    var result = digits.collect { |digit| linePattern[digit] };
    var events = List.new;

// A blank leading (tens-of-hours) panel (12-hour mode only) contributes no
// lit segments, so it produces no audio events and never flashes.
    if(~twelveHourClock and: { digits[0] == 0 }) { result[0] = Array.fill(7, 0) };

    4.do { |panel|
        3.do { |localColumn|
            var firstInColumn = true;
            var columnNumber = (panel * 3) + localColumn;

            segmentColumns[localColumn].do { |segment|
                if(result[panel][segment] == 1) {
                    events.add((
                        column: columnNumber,
                        panel: panel,
                        segment: segment,
                        role: if(firstInColumn) { \columnStart } { \columnCell }
                    ));
                    firstInColumn = false;
                };
            };
        };
    };

    ~columnEvents = events.asArray;

// SHARED STATE, read by CT8tracks.scd - see ~rowPattern's comment in
// ~getLineSegOrder, above, for why this lives here rather than there.
    ~colPattern = ~columnEvents;

    ~columnEvents;
};


// ---------------------------------------------------------------------------
// LEGACY / ALTERNATE SORT HELPER
// ---------------------------------------------------------------------------
// Legacy/helper sorter for a by-column ordering; not used by the current row event builder.
~customSort = { |arr1, arr2|   // used only for "byColumn"
// Desired segment priority inside each grouped column.
    var order = [1,4,0,3,6,2,5];
// Zip the grouping keys and segment values into pairs.
    var paired = arr1.collect({ |x, i| [x, arr2[i]] });
// Dictionary collects values under their shared grouping key.
    var grouped = Dictionary.new;
    var result;

    paired.do { |pair|
        var key = pair[0];
        if(grouped[key].isNil) { grouped[key] = [] };
        grouped[key] = grouped[key].add(pair[1]);
    };

    result = grouped.keys.asArray.sort.collect { |key|
        var group = grouped[key];
        group.sort { |a, b| order.indexOf(a) < order.indexOf(b) };
    }.flatten;

    result;
};

// ---------------------------------------------------------------------------
// DISPLAY ALL FOUR DIGITS
// ---------------------------------------------------------------------------
// Draw the current global ~hours and ~minutes into all four digit panels.
~displayClock = {
    var time = ~getClockDigits.value(~hours, ~minutes);
// Leading (tens-of-hours) panel is left blank rather than showing "0", but
// only in 12-hour mode ("9:45", not "09:45"). A 24-hour clock keeps the
// leading zero ("09:45").
    ~drawDigit.value(if(~twelveHourClock and: { time[0] == 0 }) { nil } { time[0] }, 0);
    ~drawDigit.value(time[1], 1);
    ~drawDigit.value(time[2], 2);
    ~drawDigit.value(time[3], 3);
};

// ---------------------------------------------------------------------------
// DRAW ONE DECIMAL DIGIT
// ---------------------------------------------------------------------------
// Record which of a digit's seven strokes are lit, into ~activeSegments;
// ~drawPanel (below) is what actually decides each stroke's color.
// digit == nil blanks the panel entirely (used to suppress a leading zero).
~drawDigit = { |digit, panel|
// Segment-number lists for digits 0 through 9.
    var digitLinesUsed = [
        [0,1,2,4,5,6],
		[2,5],
		[0,2,3,4,6],
		[0,2,3,5,6],
		[1,2,3,5],
        [0,1,3,5,6],
		[0,1,3,4,5,6],
		[0,2,5],
		[0,1,2,3,4,5,6],
		[0,1,2,3,5,6]
    ];
// Store which dashes are lit; ~drawPanel renders them from current state.
    7.do { |i|
        ~activeSegments[panel][i] = digit.notNil and: { digitLinesUsed[digit].includes(i) };
    };
    ~digitPanel[panel].refresh;
};

// ---------------------------------------------------------------------------
// DRAW ONE COMPLETE 5x3 DIGIT PANEL
// ---------------------------------------------------------------------------
// Rows are thin/thick/thin/thick/thin; columns are narrow/wide/narrow.
~drawPanel = { |panel, view|
    var width = view.bounds.width;
    var height = view.bounds.height;
    var columnEdges = [0, width / 6, width * 5 / 6, width];
    var rowEdges = [0, height / 10, height * 4.5 / 10,
        height * 5.5 / 10, height * 9 / 10, height];
    var segmentCells = [
        [0, 1], // top horizontal
        [1, 0], // upper left
        [1, 2], // upper right
        [2, 1], // middle horizontal
        [3, 0], // lower left
        [3, 2], // lower right
        [4, 1]  // bottom horizontal
    ];

    5.do { |row|
        3.do { |column|
            var globalColumn = (panel * 3) + column;
            var color = if(~columnFlashActive[globalColumn]) {
                ~columnFlashColor
            } {
                if(~rowFlashActive[row]) { ~rowFlashColor } { ~cellBaseColor }
            };
            var rect = Rect(
                columnEdges[column],
                rowEdges[row],
                columnEdges[column + 1] - columnEdges[column],
                rowEdges[row + 1] - rowEdges[row]
            );

            Pen.fillColor = color;
            Pen.fillRect(rect);
        };
    };

    // Keep only the outside edge of each digit panel; there are no internal
    // grid lines between its five rows and three columns.
    Pen.strokeColor = Color.black;
    Pen.width = 1;
    Pen.strokeRect(Rect(0, 0, width, height));

// Every segment is always drawn: unlit ones are colored the same as the
// panel background (so they're effectively invisible) and lit ones show
// light grey (or their flash color). Vertical strokes sit on the shared
// edge with the middle column, and reach up/down into the neighboring thin
// rows' horizontal centers, instead of being centered in their own band -
// that's what makes the corners actually touch.
    7.do { |segment|
        var cell = segmentCells[segment];
        var row = cell[0];
        var column = cell[1];
        var globalColumn = (panel * 3) + column;
        var left = columnEdges[column];
        var right = columnEdges[column + 1];
        var top = rowEdges[row];
        var bottom = rowEdges[row + 1];
        var isLit = ~activeSegments[panel][segment];
// An "off" segment must match whatever the row/column-flash background
// underneath it actually is right now, or it would paint over that
// highlight instead of staying invisible against it.
        var offColor = if(~columnFlashActive[globalColumn]) {
            ~columnFlashColor
        } {
            if(~rowFlashActive[row]) { ~rowFlashColor } { ~cellBaseColor }
        };
        var start;
        var finish;

        if([0, 3, 6].includes(segment)) {
            start = left @ ((top + bottom) / 2);
            finish = right @ ((top + bottom) / 2);
        } {
            var x = if(column == 0) { columnEdges[1] } { columnEdges[2] };
// Only reach into the neighboring thin rows when lit: an off segment must
// stay inside its own row band, or its background-matching color (computed
// from that one row) would bleed into a neighboring row's different fill.
            var topY = if(isLit) { (rowEdges[row - 1] + rowEdges[row]) / 2 } { top };
            var bottomY = if(isLit) { (rowEdges[row + 1] + rowEdges[row + 2]) / 2 } { bottom };
            start = x @ topY;
            finish = x @ bottomY;
        };

        Pen.strokeColor = if(isLit) {
            if(~dashFlashActive[panel][segment]) {
                ~dashFlashColor[panel][segment]
            } {
                ~segmentOnColor
            }
        } {
            offColor
        };
        Pen.width = 10;
        Pen.line(start, finish);
        Pen.stroke;
    };
};


// ---------------------------------------------------------------------------
// TIME-CHANGE DETECTION AND PATTERN REBUILD
// ---------------------------------------------------------------------------
// Called repeatedly by main; advance/read time and rebuild clock state when minute changes.
~checkForNewMinute = {
// Snapshot the currently displayed minute before this check.
    var lastMinute = ~minutes;
// Real-time mode reads the system minute; simulated mode counts repeated calls.
    if (~runningRealTime) {
// Replace the displayed minute with the computer clock minute.
        ~minutes = Date.getDate.minute; // Then use the system clock
    } {
// In simulated mode each call advances the fake-second counter.
        ~fakeSecond = ~fakeSecond + 1; // Else track simulated seconds loop
// Sixty simulated calls advance the displayed minute once.
        if (~fakeSecond == 60) {
            ~minutes = ~minutes + 1;
            ~fakeSecond = 0;
        };
    };
// Rebuild the clock only when a minute boundary has actually been crossed.
    if (~minutes != lastMinute) {
        {
            lastMinute = ~minutes;
            if (~minutes == 60) { ~minutes = 0 };
            if (~minutes == 0) { ~hours = ~hours + 1 };
            if (~hours == 24) { ~hours = 0 };

// Stop the old repeating pattern before replacing its source events.
            ~stopPbinds.value;
// Recalculate row-count rhythm data for the new displayed time.
            ~getClockRhythm.value;
// Redraw the four digits. The function itself reads globals; extra arguments are harmless.
            ~displayClock.value(~hours, ~minutes);
// Rebuild the ordered ~clockEvents stream for the new digits.
            ~getLineSegOrder.value;
// Build the independent by-column event stream for percussion track two.
            ~getColumnSegOrder.value;

// Ask the tracks file to rebuild every registered track's Pbind from the
// new events (see ~trackBuilders, CT8tracks.scd).
            ~updatePbinds.value;
// Start whichever tracks are enabled.
            ~restartPbinds.value;
// Flashing is independent of any track now - rebuild/restart it in step
// with the scan, same as the tracks above.
            ~rebuildFlashPatterns.value;
            ~restartFlashPlayers.value;
        }.defer; // Defer safely updates user-facing views on the main window thread
    };
};

// ---------------------------------------------------------------------------
// VISUAL FEEDBACK FOR SOUNDING CELLS
// ---------------------------------------------------------------------------
// Briefly highlight the cell that just sounded, then let it fall back to
// its normal ~segmentOnColor. NOTE: the dashColor argument on both functions
// below is accepted but ignored - the flash color is hardcoded inline
// (blue here, red in ~flashColumn) regardless of what callers pass in.
//
// Row-track event: keep the current complete row tinted ~rowFlashColor until
// the track moves to another row. The current dash flashes blue for 90% of
// one beat.
~flashRow = { |row, panel, segment, dashColor, hold|
    var dashToken;

    hold = hold ? (0.9 / ~tempo);

    ~rowFlashActive = Array.fill(5, false);
    ~rowFlashActive[row] = true;

    ~dashFlashSerial[panel][segment] = ~dashFlashSerial[panel][segment] + 1;
    dashToken = ~dashFlashSerial[panel][segment];
    ~dashFlashColor[panel][segment] = Color.blue;
    ~dashFlashActive[panel][segment] = true;
    4.do { |i| ~digitPanel[i].refresh };

    AppClock.sched(hold, {
        if(~dashFlashSerial[panel][segment] == dashToken) {
            ~dashFlashActive[panel][segment] = false;
            ~digitPanel[panel].refresh;
        };
        nil;
    });
};

// Column-track event: keep the current complete column tinted
// ~columnFlashColor until the track moves to another column. The current
// dash flashes red for 90% of one beat.
~flashColumn = { |column, panel, segment, dashColor, hold|
    var dashToken;

    hold = hold ? (0.9 / ~tempo);

    ~columnFlashActive = Array.fill(12, false);
    ~columnFlashActive[column] = true;

    ~dashFlashSerial[panel][segment] = ~dashFlashSerial[panel][segment] + 1;
    dashToken = ~dashFlashSerial[panel][segment];
    ~dashFlashColor[panel][segment] = Color.red;
    ~dashFlashActive[panel][segment] = true;
    4.do { |i| ~digitPanel[i].refresh };

    AppClock.sched(hold, {
        if(~dashFlashSerial[panel][segment] == dashToken) {
            ~dashFlashActive[panel][segment] = false;
            ~digitPanel[panel].refresh;
        };
        nil;
    });
};


// ---------------------------------------------------------------------------
// ROW/COL FLASH PLAYERS (independent of any track)
// ---------------------------------------------------------------------------
// Visual-only Pbinds that walk ~clockEvents/~columnEvents on the shared
// TempoClock, calling ~flashRow/~flashColumn in step - entirely separate
// from PT1/PT2 (CT8tracks.scd), which only care about sound now. Flashing no
// longer depends on any track existing or being enabled; these keep running
// regardless of PT1/PT2's own on/off state. \type is always \rest - these
// never spawn a synth, only drive the \updateGUI side effect (the standard
// Event mechanism for "build this event's other keys as normal, but don't
// spawn a synth for it" - see CT8tracks.scd's \type comment).
~rowFlashEnabled = ~rowFlashEnabled ? true;
~colFlashEnabled = ~colFlashEnabled ? true;

~buildRowFlashPattern = {
    var events = ~clockEvents ? [];
    if(events.isEmpty) {
        ~rowFlashPattern = Pbind(\dur, 1, \type, \rest);
    } {
        ~rowFlashPattern = Pbind(
            \dur, 1,
            \type, \rest,
            \clockEvent, Pseq(events, inf),
            \updateGUI, Pfunc { |event|
                if(~rowFlashEnabled) {
                    var cell = event[\clockEvent];
                    {
                        ~flashRow.value(cell[\row], cell[\panel], cell[\segment], Color.blue);
                    }.defer;
                };
// Must return non-nil regardless of the branch above - a Pfunc yielding
// bare nil is SC's stream-protocol signal for "this stream has ended",
// which would silently kill this Pbind after just one event.
                \flashed
            }
        );
    };
};

~buildColFlashPattern = {
    var events = ~columnEvents ? [];
    if(events.isEmpty) {
        ~colFlashPattern = Pbind(\dur, 1, \type, \rest);
    } {
        ~colFlashPattern = Pbind(
            \dur, 1,
            \type, \rest,
            \clockEvent, Pseq(events, inf),
            \updateGUI, Pfunc { |event|
                if(~colFlashEnabled) {
                    var cell = event[\clockEvent];
                    {
                        ~flashColumn.value(cell[\column], cell[\panel], cell[\segment], Color.black);
                    }.defer;
                };
                \flashed
            }
        );
    };
};

// Rebuild both flash patterns from the current scan - called alongside
// ~updatePbinds everywhere that gets called (minute rollover, source/format
// toggles), so flashing always matches what's currently lit.
~rebuildFlashPatterns = {
    ~buildRowFlashPattern.value;
    ~buildColFlashPattern.value;
};

// Stop both flash players and clear their references - called by ~stopAll
// (CT8tracks.scd) for full cleanup, and by ~restartFlashPlayers below.
~stopFlashPlayers = {
    if(~rowFlashPlayer.notNil) { ~rowFlashPlayer.stop; ~rowFlashPlayer = nil };
    if(~colFlashPlayer.notNil) { ~colFlashPlayer.stop; ~colFlashPlayer = nil };
};

// Stop both flash players, then restart whichever is enabled - called
// alongside ~restartPbinds everywhere that gets called.
~restartFlashPlayers = {
    ~stopFlashPlayers.value;
    if(~rowFlashEnabled and: { ~rowFlashPattern.notNil } and: { t.notNil }) {
        ~rowFlashPlayer = ~rowFlashPattern.play(t, quant: 1);
    };
    if(~colFlashEnabled and: { ~colFlashPattern.notNil } and: { t.notNil }) {
        ~colFlashPlayer = ~colFlashPattern.play(t, quant: 1);
    };
};

// Stop/conditionally-restart just one of the two flash players (\row or
// \col) - used by the Colour row's buttons (CT8guiAdjust.scd) to toggle one
// live without touching the other.
~syncFlashPlayer = { |which|
    if(which == \row) {
        if(~rowFlashPlayer.notNil) { ~rowFlashPlayer.stop; ~rowFlashPlayer = nil };
        if(~rowFlashEnabled and: { ~rowFlashPattern.notNil } and: { t.notNil }) {
            ~rowFlashPlayer = ~rowFlashPattern.play(t, quant: 1);
        };
    } {
        if(~colFlashPlayer.notNil) { ~colFlashPlayer.stop; ~colFlashPlayer = nil };
        if(~colFlashEnabled and: { ~colFlashPattern.notNil } and: { t.notNil }) {
            ~colFlashPlayer = ~colFlashPattern.play(t, quant: 1);
        };
    };
};


// ---------------------------------------------------------------------------
// PANEL BACKGROUND REFRESH
// ---------------------------------------------------------------------------
// Reapply each stored panel background color and refresh all four panels.
~recolorPanels = {
    ~rowFlashActive = Array.fill(5, false);
    ~columnFlashActive = Array.fill(12, false);
    4.do { |index| ~digitPanel[index].refresh };
};

"ClockToy clock GUI functions loaded.".postln;

)
