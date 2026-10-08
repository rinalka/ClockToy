// ============================================================================
// CT8main.scd
// CLOCKTOY - MAIN / STARTUP AND RUNTIME CONTROL
// ============================================================================
//
// This file is the coordinator for the project. It cleans up an earlier run,
// establishes the operating mode and initial time, configures the audio server,
// uses the GUI and synth definitions already evaluated in the interpreter,
// builds the first clock event sequence, starts
// the musical pattern, and schedules repeated minute-change checks.
//

// ============================================================================
// FUTURE DIRECTION - "DAILY PIECE" GENERATIVE MODE (planned, not yet implemented)
// ============================================================================
// Rough sketch of where this project is headed, recorded here so the intent
// survives between sessions. None of this exists yet - ClockToy currently
// just runs the two live seven-segment tracks described above.
//
// User flow: the user chooses a starting point in the day - either the
// current real time or an arbitrary set time - and a duration for the
// piece, then presses Play.
//
// Four data tables drive what the piece does, all indexed by time of day:
//   1. Actions - one entry per 15-minute slot across a 24-hour day (walking,
//      eating, sleep: deep/light/REM, in bed awake, reading, etc.).
//   2. Heart rate - one 24-hour recording, sampled every 10 seconds.
//   3. Mood - one entry per 15-minute slot across a 24-hour day.
//   4. Weather - one entry per 15-minute slot across a 24-hour day.
//
// The piece is organized into 13 simultaneous tracks: 4 percussion, 1 bass,
// 4 rhythm/harmony, and 4 melody.
//
// Terminology: 
//a beat is one flashed segment/event (row or column scan);
// a bar is one full pass through all of a track's beats before the pattern
//  repeats - how many beats that is varies with the displayed time and
//  12/24-hour mode Sections: 
//a section is some  number of bars, sized from the 15-minute chunks in the Actions and Mood
//   tables above (maybe Weather too) 
//
// Generative code will read the four tables across the chosen start time and
// duration, and use them to select and configure instruments, set their
// parameters, and build the Pbinds that drive each track - the specifics of
// how that selection actually works are still to be designed.
//



(
// ---------------------------------------------------------------------------
// 0. LOAD EVERY OTHER CT8 FILE
// ---------------------------------------------------------------------------

// ~ct8Dir is hardcoded! Update this path if the project folder moves.
~ct8Dir = "C:/Users/baaan/Desktop/Music/sc/ClockToy/CT8";
~ct8FileNames = [
    "CT8synths.scd",
    "CT8guiClock.scd",
    "CT8harmonySelect.scd",
    "CT8tracks.scd",
    "CT8guiAdjust.scd",
    "CT8guiPercGenerator.scd",
    "CT8guiHarmonyMelodyGenerator.scd",
    "CT8guiSynthLab.scd",
    "CT8fakeData.scd"
];

~loadCt8File = { |fileName|
    ("Loading " ++ fileName ++ " ...").postln;
    thisProcess.interpreter.executeFile(~ct8Dir +/+ fileName);
};
~loadAllCt8Files = { ~ct8FileNames.do(~loadCt8File) };
~loadAllCt8Files.value;

// ---------------------------------------------------------------------------
// 1. VERIFY THE LOAD ACTUALLY SUCCEEDED
// a safety net - fires if failed to load (e.g. syntax error)
if(
    ~makeWindow.isNil
    or: { ~getLineSegOrder.isNil }
    or: { ~getColumnSegOrder.isNil }
    or: { ~installSynthDefs.isNil }
    or: { ~computeNextChord.isNil }
    or: { ~setStartPbinds.isNil }
    or: { ~trackEnabled.isNil }
) {
    Error("A CT8 file failed to load - check the post window above for the actual error.").throw;
};

// set current tracks true
~trackEnabled[\PT1] = true;
~trackEnabled[\PT2] = true;
~trackEnabled[\PT3] = true;
~trackEnabled[\HT1] = true;
~trackEnabled[\MT1] = true;
~trackEnabled[\MT2] = true;
~trackEnabled[\BT1] = true;

// ---------------------------------------------------------------------------
// 2. CLEAN UP ANY PREVIOUS RUN
// If the previous synth file defined ~stopAll, call it to dispose of the old engine.
if(~stopAll.notNil) { ~stopAll.value };
if(t.notNil) { t.clear; t.stop };

// Close all four ClockToy windows when (CmdPeriod) 
if(~closeWindowsOnCmdPeriod.notNil) { CmdPeriod.remove(~closeWindowsOnCmdPeriod) };
~closeWindowsOnCmdPeriod = {
    if(w.notNil) { w.close };
    if(~adjustWindow.notNil) { ~adjustWindow.close };
    if(~percGeneratorWindow.notNil) { ~percGeneratorWindow.close };
    if(~hmGeneratorWindow.notNil) { ~hmGeneratorWindow.close };
// ~stopSynthLab also frees its own private Groups/Bus, not just the window -
// see CT8guiSynthLab.scd.
    if(~stopSynthLab.notNil) { ~stopSynthLab.value };
};
CmdPeriod.add(~closeWindowsOnCmdPeriod);

// ---------------------------------------------------------------------------
// 3. RUNTIME PARAMETERS

// set current tracks true
~trackEnabled[\PT1] = true;
~trackEnabled[\PT2] = true;
~trackEnabled[\PT3] = true;
~trackEnabled[\HT1] = true;
~trackEnabled[\MT1] = true;
~trackEnabled[\MT2] = true;
~trackEnabled[\BT1] = true;

~twelveHourClock = true;  // false makes it a 24-hour clock
~runningRealTime = true;  // false starts the clock at a fixed time and advances it using ~fakeSecond
~tempo = 180 / 60;        // TempoClock uses beats per second
~pieceLengthSecs = 300;

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

s.quit;
Server.killAll;

AppClock.sched(1.0, {
    s.options.device = "ASIO : Focusrite USB ASIO"; // Explicitly select the Focusrite USB ASIO driver.
    s.options.numInputBusChannels = 2;              // Expose two hardware input channels to scsynth.
    s.options.numOutputBusChannels = 2;             // Use stereo hardware output.
    s.options.sampleRate = 48000;                   // Request a 48 kHz sample rate.
    // Bumped from 64MB for the Synth Lab's heavier synths (\drone/\kick/
    // \droneChord all run 8-20+ simultaneous oscillators per note) - this is
    // the only place this setting can take effect, since it's boot-time-only
    // and the server is already running by the time CT8guiSynthLab.scd's own
    // window gets built.
    s.options.memSize = 655360;                     // Real-time memory pool, in KB (default 8192).
    s.options.maxNodes = 8192;                      // Max simultaneous server nodes (default 1024).
    s.options.hardwareBufferSize = 256;             // Request a 256-sample hardware buffer.

    // Start the audio server asynchronously.
    s.boot;
    // nil;
});

s.waitForBoot({
    ~revBus = Bus.audio(s, 2);// Allocate a private stereo audio bus used to feed the reverb processor.
    ~installSynthDefs.value;// Compile/send the live SynthDef source evaluated from CT8synths.
    s.sync;// Wait until prior asynchronous server commands have completed.
 
    {
     ~makeWindow.value;// Construct the  four-digit clock GUI.
     ~makeAdjustWindow.value;// Construct the separate control window.
   
     ~makeHarmonyMelodyGeneratorWindow.value;// Construct the HT1-4/MT1-2 skeleton control window (not yet wired to playback).
     ~makePercGeneratorWindow.value;// Construct the PT1-PT4/BT1-BT2 instrument/pattern/pitch/volume control window.
// Temporarily not displayed while the Percussion + Bass Generator's own
// per-track layout is being reworked - ~makeSynthLabWindow itself is
// untouched, just not auto-opened here; evaluate it by hand
// (~makeSynthLabWindow.value) if you need it meanwhile.
//     ~makeSynthLabWindow.value;// Construct the standalone sound-experiment/audition window (own private reverb bus, unrelated to ~revBus).
     ~displayClock.value;// Draw the initial four digits using ~hours and ~minutes.
     ~getLineSegOrder.value; // Scan the lit seven-segment cells and create the ordered ~clockEvents Array.
     ~getColumnSegOrder.value; // Build track two's independent by-column event stream.
    }.defer;

    AppClock.sched(0.15, {// Delay briefly so GUI construction can settle before musical playback begins.
        t = TempoClock.new(~tempo);// Create the project TempoClock at the requested beats-per-second value.
        ~setStartPbinds.value;// Build and start the clock pattern and persistent reverb synth.
// Flashing is independent of any track - build and start it alongside the
// tracks above, not through ~setStartPbinds (CT8guiClock.scd owns this).
        ~rebuildFlashPatterns.value;
        ~restartFlashPlayers.value;

// Auto-stop after ~pieceLengthSecs. ~playSessionToken guards against a
// stale timer from an earlier CT8main.scd run firing during a later one
// (re-evaluating this file doesn't cancel an already-scheduled AppClock
// callback, only stuff scheduled on t) - same technique ~flashRow/
// ~flashColumn already use for their own stale-callback problem.
        ~playSessionToken = (~playSessionToken ? 0) + 1;
        {
            var mySessionToken = ~playSessionToken;
            AppClock.sched(~pieceLengthSecs, {
                if(~playSessionToken == mySessionToken) {
                    ("Piece-length timer (" ++ ~pieceLengthSecs ++ " sec) elapsed - stopping playback.").postln;
                    ~stopPbinds.value;
                };
                nil; //return nil when done!
            });
        }.value;

        t.sched(0, {// Install a repeating function on the TempoClock to check for minute changes.
            ~checkForNewMinute.value;// Compare/update clock time and rebuild display/music when the minute changes.
            ~secondTime; // Return the number of TempoClock beats to wait before running this function again.
        });
// Separate repeating check, once per beat, for the shared chord progression
// (~checkForNewChordBar, CT8harmonySelect.scd) - independent of
// ~checkForNewMinute/~secondTime above, since the chord advances on its own
// ~numBeats-beat cycle, not on real/simulated minutes.
        t.sched(0, {
            ~checkForNewChordBar.value;
            1;
        });
        "                     ".postln;
        "ClockToy initialized.".postln;
	        nil;
    });
});

)


~copyTStartRecord.(\BT1, 8); 
~copyTStartPlayback.(\MT1); 