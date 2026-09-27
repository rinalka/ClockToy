// ============================================================================
// CT6main.scd
// CLOCKTOY - MAIN / STARTUP AND RUNTIME CONTROL
// ============================================================================
//
// This file is the coordinator for the project. It cleans up an earlier run,
// establishes the operating mode and initial time, configures the audio server,
// uses the GUI and synth definitions already evaluated in the interpreter,
// builds the first clock event sequence, starts
// the musical pattern, and schedules repeated minute-change checks.
//


(
// ---------------------------------------------------------------------------
// 1. VERIFY THAT THE OTHER TWO OPEN FILES HAVE BEEN EVALUATED
// Evaluate CT6gui first, CT6syn second, and this file last.  No saving or
// executeFile reload is required: the live editor definitions are used.

~playRowTrack = true;
~playColumnTrack = true;

if(
    ~makeWindow.isNil
    or: { ~getLineSegOrder.isNil }
    or: { ~getColumnSegOrder.isNil }
    or: { ~installSynthDefs.isNil }
    or: { ~setStartPbinds.isNil }
) {
    Error("Evaluate all of CT6gui, then all of CT6syn, before CT6main.").throw;
};

// ---------------------------------------------------------------------------
// 2. CLEAN UP ANY PREVIOUS RUN
// SuperCollider interpreter state survives between evaluations, so ..

// If the previous synth file defined ~stopAll, call it to dispose of the old engine.
if(~stopAll.notNil) { ~stopAll.value };
if(t.notNil) { t.clear; t.stop };

// ---------------------------------------------------------------------------
// 3. RUNTIME PARAMETERS
// These values select real-time versus simulated-time operation and establish
// the TempoClock speed and initial display time.

~twelveHourClock = true;  // false makes it a 24-hour clock
~runningRealTime = true;  // false starts the clock at a fixed time and advances it using ~fakeSecond
~tempo = 180 / 60;        // TempoClock uses beats per second

~dashDir = "byRow";       // Current musical event generation is row-based.

// Establish the initial displayed time and scheduler interval.
if(~runningRealTime) {
    ~secondTime = 1;
    ~hours = Date.getDate.localtime.hour;
    ~minutes = Date.getDate.localtime.minute;
} { // not real-time clock
    ~fakeSecond = 0;      // starts at 0; counts to 60 in simulated mode
    ~secondTime = 0.5;
    ~hours = 12;
    ~minutes = 8;
};

// ---------------------------------------------------------------------------
// 4. AUDIO SERVER SETUP
// ---------------------------------------------------------------------------
// Configure the default SuperCollider server for the Focusrite interface, then
// boot it before allocating buses or adding SynthDefs.

s.quit;
Server.killAll;

s.options.device = "ASIO : Focusrite USB ASIO"; // Explicitly select the Focusrite USB ASIO driver.
s.options.numInputBusChannels = 2;              // Expose two hardware input channels to scsynth.
s.options.numOutputBusChannels = 2;             // Use stereo hardware output.
s.options.sampleRate = 48000;                   // Request a 48 kHz sample rate.
s.options.hardwareBufferSize = 256;             // Request a 256-sample hardware buffer.

// Start the audio server asynchronously.
s.boot;

s.waitForBoot({
    ~revBus = Bus.audio(s, 2);// Allocate a private stereo audio bus used to feed the reverb processor.
    ~installSynthDefs.value;// Compile/send the live SynthDef source evaluated from CT6syn.
    s.sync;// Wait until prior asynchronous server commands have completed.
    {
     ~makeWindow.value;// Construct the four-digit clock GUI.
     ~displayClock.value;// Draw the initial four digits using ~hours and ~minutes.
     ~getLineSegOrder.value(~dashDir); // Scan the lit seven-segment cells and create the ordered ~clockEvents Array.
     ~getColumnSegOrder.value; // Build track two's independent by-column event stream.
    }.defer;

    AppClock.sched(0.15, {// Delay briefly so GUI construction can settle before musical playback begins.
        t = TempoClock.new(~tempo);// Create the project TempoClock at the requested beats-per-second value.
        ~setStartPbinds.value;// Build and start the clock pattern and persistent reverb synth.

        t.sched(0, {// Install a repeating function on the TempoClock to check for minute changes.
            ~checkForNewMinute.value;// Compare/update clock time and rebuild display/music when the minute changes.
            ~secondTime; // Return the number of TempoClock beats to wait before running this function again.
        });
        "                     ".postln;
        "ClockToy initialized.".postln;
		"  really                   ".postln;
        nil;
    });
});

)

// Everything below is optional testing material.
(// turn percussion tracks on and off
~playRowTrack = true;
~playColumnTrack = true;
)

(// reset the tempo
~tempo = 00 / 60;
t = TempoClock.new(~tempo);
//and reevaluate main
)


