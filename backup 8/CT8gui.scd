// ============================================================================
// CT8gui.scd
// CLOCKTOY - CLOCK GEOMETRY, DISPLAY, EVENT GENERATION, AND TIME CHANGES
// ============================================================================
//
// This file owns the visual model of the four-digit seven-segment clock and the
// conversion from that geometry into abstract musical events. Its central
// product is ~clockEvents: an ordered Array of lit cells. Each event records a
// row, panel, segment, and an abstract role (\rowStart or \cell). The synth
// file decides what those roles sound like.
//


(

// WINDOW CREATION  with 7 panels top and bot for text, and 4 panels for digits
// ---------------------------------------------------------------------------
// Build the application window and four digit panels used by the seven-segment display.
"making window".postln;

~makeWindow = {
// Close earlier SuperCollider windows before creating a fresh ClockToy display.
    Window.closeAll;
    w = Window("My Daily Digital Clock", Rect(800, 800, 500, 212), resizable: true, border: true)
        .background_(Color.black)
        .front
        .alwaysOnTop_(true);
    w.view.decorator = FlowLayout(w.bounds, 4@4, 4@4);
    UserView(w, 492@1).background_(Color.black);
 //   UserView(w, 50@200).background_(Color.black);

    ~cellBaseColor = Color(0.84, 0.84, 0.84);
    ~rowFlashColor = Color.white;
    ~columnFlashColor = Color.yellow;

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

// Takes the hours and minutes and makes an array of the 4 digits the clock will display

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

// Return an array of the duration for each of the 5 rows, by counting the number of segments in each column of that row

// ---------------------------------------------------------------------------
// LEGACY FIVE-ROW RHYTHM COUNTS
// ---------------------------------------------------------------------------
// Count how many seven-segment strokes occupy each of the five visual rows.
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
    // Remove zero elements
// Store only non-empty rows; spelling is retained from the source file.
    ~currentRythm = result.select({ |elem| elem != 0 });
};


// ---------------------------------------------------------------------------
// LIT SEGMENTS -> ABSTRACT CLOCK EVENTS
// ---------------------------------------------------------------------------
// Build the ordered musical cell stream from all currently lit clock segments.
~getLineSegOrder = { |dir|
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

    // Physical scan order of the 28 possible seven-segment strokes.
    // The groups are the five visual rows: 4, 8, 4, 8, 4 cells.
// Physical scan order of all 28 possible strokes, grouped into five visual rows.
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

    // Build the musical clock pattern directly from the lit cells.
    // The first lit cell in each non-empty row is \rowStart; all others are \cell.
// Walk each visual row independently so its first lit cell can be specially marked.
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

// Publish the completed event stream for CT6syn to interpret.
    ~clockEvents = events.asArray;

    // Keep these arrays for compatibility with older code and for inspection.
// Compatibility/inspection Array containing only each event panel index.
    ~dashPanNum = ~clockEvents.collect { |event| event[\panel] };
// Compatibility/inspection Array containing only each event segment index.
    ~dashSegNum = ~clockEvents.collect { |event| event[\segment] };

    // The musical scanner is intentionally row-based. Other display orderings can
    // still be added later without changing the sound engine's event format.
// The argument is retained, but current musical traversal remains row-based.
    if(dir != "byRow") {
        "Clock music currently uses byRow scan order.".postln;
    };

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

// Draw the 4 digits needed for any time (hour, minutes)

// ---------------------------------------------------------------------------
// DISPLAY ALL FOUR DIGITS
// ---------------------------------------------------------------------------
// Draw the current global ~hours and ~minutes into all four digit panels.
~displayClock = {
    var time = ~getClockDigits.value(~hours, ~minutes);
    ~drawDigit.value(time[0], 0);
    ~drawDigit.value(time[1], 1);
    ~drawDigit.value(time[2], 2);
    ~drawDigit.value(time[3], 3);
};

// Draw any digit into one of the 4 panels

// ---------------------------------------------------------------------------
// DRAW ONE DECIMAL DIGIT
// ---------------------------------------------------------------------------
// Render one decimal digit by choosing which of its seven strokes should appear red.
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
        ~activeSegments[panel][i] = digitLinesUsed[digit].includes(i);
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

    7.do { |segment|
        if(~activeSegments[panel][segment]) {
            var cell = segmentCells[segment];
            var row = cell[0];
            var column = cell[1];
            var left = columnEdges[column];
            var right = columnEdges[column + 1];
            var top = rowEdges[row];
            var bottom = rowEdges[row + 1];
            var start;
            var finish;

            if([0, 3, 6].includes(segment)) {
                start = left @ ((top + bottom) / 2);
                finish = right @ ((top + bottom) / 2);
            } {
                start = ((left + right) / 2) @ top;
                finish = ((left + right) / 2) @ bottom;
            };

            Pen.strokeColor = if(~dashFlashActive[panel][segment]) {
                ~dashFlashColor[panel][segment]
            } {
                Color.red
            };
            Pen.width = 10;
            Pen.line(start, finish);
            Pen.stroke;
        };
    };
};


// ---------------------------------------------------------------------------
// TIME-CHANGE DETECTION AND PATTERN REBUILD
// ---------------------------------------------------------------------------
// Called repeatedly by main; advance/read time and rebuild clock state when minute changes.
~checkForNewMinute = {
// Snapshot the currently displayed minute before this check.
    var lastMinute = ~minutes;
    // Check the minute
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
    // If the minute has changed, adjust minutes and hours if needed
// Rebuild the clock only when a minute boundary has actually been crossed.
    if (~minutes != lastMinute) {
        {
            "Time change detected... updating pattern clocks.".postln;
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
            ~getLineSegOrder.value(~dashDir);
// Build the independent by-column event stream for percussion track two.
            ~getColumnSegOrder.value;

// Ask the synth file to rebuild ~clockPattern from the new events.
            ~updatePbinds.value;
// Start the newly rebuilt pattern.
            ~restartPbinds.value;
        }.defer; // Defer safely updates user-facing views on the main window thread
    };
};

// Briefly highlight the cell that just sounded, then restore its normal red.

// ---------------------------------------------------------------------------
// VISUAL FEEDBACK FOR SOUNDING CELLS
// ---------------------------------------------------------------------------
// Row-track event: keep the current complete row white until the track moves
// to another row. The current red dash flashes blue for 90% of one beat.
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

// Column-track event: keep the current complete column yellow until the track
// moves to another column. The current red dash flashes black for 90% of one beat.
~flashColumn = { |column, panel, segment, dashColor, hold|
    var dashToken;

    hold = hold ? (0.9 / ~tempo);

    ~columnFlashActive = Array.fill(12, false);
    ~columnFlashActive[column] = true;

    ~dashFlashSerial[panel][segment] = ~dashFlashSerial[panel][segment] + 1;
    dashToken = ~dashFlashSerial[panel][segment];
    ~dashFlashColor[panel][segment] = Color.black;
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
// PANEL BACKGROUND REFRESH
// ---------------------------------------------------------------------------
// Reapply each stored panel background color and refresh all four panels.
~recolorPanels = {
    ~rowFlashActive = Array.fill(5, false);
    ~columnFlashActive = Array.fill(12, false);
    4.do { |index| ~digitPanel[index].refresh };
};



// ---------------------------------------------------------------------------
// CLOCK TOY ADJUST WINDOW (CT8)
// This window changes controls only.  The CT7 clock drawing/flash code above
// is intentionally left unchanged.
// ---------------------------------------------------------------------------
~makeAdjustWindow = {
    var tempoBox, rowButton, columnButton, sourceButton;
    var hourBox, minuteBox, formatButton, refreshTime;

    if(~adjustWindow.notNil) { ~adjustWindow.close };

    ~adjustWindow = Window("Clock Toy Adjust", Rect(1370, 760, 340, 260), false).front;
    ~adjustWindow.view.decorator = FlowLayout(~adjustWindow.view.bounds, 12@12, 8@8);

    StaticText(~adjustWindow, 115@24).string_("Metronome  ♩ =");
    tempoBox = NumberBox(~adjustWindow, 80@24)
        .value_((~tempo ? 3) * 60)
        .clipLo_(20).clipHi_(400).step_(1)
        .action_({ |box|
            ~tempo = box.value.clip(20, 400) / 60;
            if(t.notNil) { t.tempo = ~tempo };
        });

    StaticText(~adjustWindow, 115@24).string_("Track 1 (rows)");
    rowButton = Button(~adjustWindow, 120@24)
        .states_([["OFF"], ["ON"]])
        .value_(if(~playRowTrack == false) { 0 } { 1 })
        .action_({ |b|
            ~playRowTrack = (b.value == 1);
            if(~clockPlayer.notNil) { ~clockPlayer.stop; ~clockPlayer = nil };
            if(~playRowTrack and: { ~clockPattern.notNil } and: { t.notNil }) {
                ~clockPlayer = ~clockPattern.play(t, quant: 1);
            };
            if(~playRowTrack.not) {
                ~rowFlashActive = Array.fill(5, false);
                4.do { |i| ~digitPanel[i].refresh };
            };
        });

    StaticText(~adjustWindow, 115@24).string_("Track 2 (columns)");
    columnButton = Button(~adjustWindow, 120@24)
        .states_([["OFF"], ["ON"]])
        .value_(if(~playColumnTrack == false) { 0 } { 1 })
        .action_({ |b|
            ~playColumnTrack = (b.value == 1);
            if(~columnPlayer.notNil) { ~columnPlayer.stop; ~columnPlayer = nil };
            if(~playColumnTrack and: { ~columnPattern.notNil } and: { t.notNil }) {
                ~columnPlayer = ~columnPattern.play(t, quant: 1);
            };
            if(~playColumnTrack.not) {
                ~columnFlashActive = Array.fill(12, false);
                4.do { |i| ~digitPanel[i].refresh };
            };
        });

    StaticText(~adjustWindow, 115@24).string_("Clock source");
    sourceButton = Button(~adjustWindow, 150@24)
        .states_([["Entered Time"], ["Real Time"]])
        .value_(if(~runningRealTime == false) { 0 } { 1 });

    StaticText(~adjustWindow, 42@24).string_("Hour");
    hourBox = NumberBox(~adjustWindow, 52@24).value_(~hours ? 12).clipLo_(0).clipHi_(23).step_(1);
    StaticText(~adjustWindow, 52@24).string_("Minute");
    minuteBox = NumberBox(~adjustWindow, 52@24).value_(~minutes ? 0).clipLo_(0).clipHi_(59).step_(1);

    refreshTime = {
        if(~runningRealTime == false) {
            ~hours = hourBox.value.asInteger.clip(0, 23);
            ~minutes = minuteBox.value.asInteger.clip(0, 59);
            ~fakeSecond = 0;
            ~stopPbinds.value;
            ~getClockRhythm.value;
            ~displayClock.value;
            ~getLineSegOrder.value(~dashDir);
            ~getColumnSegOrder.value;
            ~updatePbinds.value;
            ~restartPbinds.value;
        };
    };

    hourBox.action_({ refreshTime.value });
    minuteBox.action_({ refreshTime.value });

    sourceButton.action_({ |b|
        ~runningRealTime = (b.value == 1);
        ~fakeSecond = 0;
        if(~runningRealTime) {
            ~secondTime = 1;
            ~hours = Date.getDate.localtime.hour;
            ~minutes = Date.getDate.localtime.minute;
            hourBox.value_(~hours); minuteBox.value_(~minutes);
            ~stopPbinds.value;
            ~getClockRhythm.value;
            ~displayClock.value;
            ~getLineSegOrder.value(~dashDir);
            ~getColumnSegOrder.value;
            ~updatePbinds.value;
            ~restartPbinds.value;
        } {
            ~secondTime = 0.5;
            refreshTime.value;
        };
    });

    StaticText(~adjustWindow, 115@24).string_("Clock display");
    formatButton = Button(~adjustWindow, 150@24)
        .states_([["24 Hour"], ["12 Hour"]])
        .value_(if(~twelveHourClock == true) { 1 } { 0 })
        .action_({ |b|
            ~twelveHourClock = (b.value == 1);
            ~stopPbinds.value;
            ~getClockRhythm.value;
            ~displayClock.value;
            ~getLineSegOrder.value(~dashDir);
            ~getColumnSegOrder.value;
            ~updatePbinds.value;
            ~restartPbinds.value;
        });
};

"ClockToy GUI functions loaded.".postln;

)
