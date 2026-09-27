// ============================================================================
// CT6syn.scd
// CLOCKTOY - SOUND DEFINITIONS AND CLOCK-EVENT INTERPRETER
// ============================================================================
//
// CT6gui creates an ordered stream of abstract clock-cell events. This file
// gives those events sound: row starts currently become plucks, later cells in
// the same row become short sine clicks. It also owns the shared reverb,
// pattern lifecycle, tempo changes, and cleanup routine.
//
(
"ct6 synth functions loaded".postln;

// ---------------------------------------------------------------------------
// PITCH MATERIAL / CURRENT PITCH CONTROLS
// ---------------------------------------------------------------------------
// MIDI-note pool containing piano white-key pitches over a broad register.
~whiteNotes = [36,38,40,41,43,45,47,48,50,52,53,55,57,59,60,62,64,65,67,69,71,72,74,76,77,79,81,83,84];

// Select MIDI note 41 (F2) from the pool and convert it to Hz for the pluck role.
~pluckFreq = ~whiteNotes[3].midicps;
// Frequency in Hz for the current short sine-click implementation of the hat role.
~hatFreq = 4000;


// ---------------------------------------------------------------------------
// SYNTHDEFS
// Keep SynthDef creation in a function.  CT6main calls this only after the
// server has booted and ~revBus exists.  Evaluating this file again while the
// project is running also installs edited SynthDefs immediately.
~installSynthDefs = {

// PLUCK SYNTH
SynthDef(\plucking, {
    arg outbus = 0, amp = 0.2, sAmp = 0.5,
        freq = 440, pluckDecay = 0.35, coef = 0.25, pan = 0,
        atk = 0.001, sus = 0.015, rel = 0.10,
        dynamic = 0.25;

    var env, excitation, snd;

    // Very short amplitude envelope
    env = EnvGen.kr(
        Env.linen(atk, sus, rel),
        doneAction: 2
    );

    // Short noise impulse excites the string
    excitation = BrownNoise.ar(amp)
        * EnvGen.kr(Env.perc(0.001, 0.008));

    snd = Pluck.ar(
        excitation,
        Impulse.kr(0),
        0.005,
        freq.reciprocal,
        pluckDecay,
        coef
    );

    snd = LeakDC.ar(snd).clip2;
    snd = Pan2.ar(snd, pan);

    Out.ar(outbus, snd * env * sAmp);

    // Keep existing reverb send for now.
    Out.ar(~revBus, snd * env * dynamic);
}).add;

//Synth(\plucking, [\freq, 87, \amp, 1]);

// ---------------------------------------------------------------------------
// HAT - short metallic cymbal tick
// ---------------------------------------------------------------------------
SynthDef(\hat, {
    |amp = 0.2, pan = 0, out = 0|

    var env, noise, metal, snd;

    // Extremely short envelope
    env = Env.perc(0.001, 0.018).ar(Done.freeSelf);

    // Bright broadband component
    noise = HPF.ar(WhiteNoise.ar, 2500);

    // Inharmonic metallic components
    metal = Mix.ar(
        SinOsc.ar([4200, 5350, 7100, 4300])
    ) * 0.15;

    snd = (noise * 0.75) + metal;
    snd = HPF.ar(snd, 5000);
    snd = snd * env * amp;

    Out.ar(out, Pan2.ar(snd, pan));
}).add;

//Synth(\hat, [ \amp, 0.5]);

// ---------------------------------------------------------------------------
// BASS DRUM - first lit cell in each column
// ---------------------------------------------------------------------------
SynthDef(\bassDrum, {
    |out = 0, amp = 0.85, pan = 0|
    var ampEnv = Env.perc(0.001, 0.32, curve: -7).ar(Done.freeSelf);
    var pitchEnv = Env([78, 43, 34], [0.025, 0.16], curve: -5).ar;
    var body = SinOsc.ar(pitchEnv) * ampEnv;
    var click = HPF.ar(WhiteNoise.ar(0.10), 3500)
        * Env.perc(0.001, 0.012).ar;
    var snd = ((body + click) * amp).tanh;

    Out.ar(out, Pan2.ar(snd, pan));
}).add;

// ---------------------------------------------------------------------------
// SHORT WHISTLE - subsequent lit cells in a column
// ---------------------------------------------------------------------------
SynthDef(\shortWhistle, {
    |out = 0, amp = 0.16, freq = 1900, pan = 0, dynamic = 0.12|
    var env = Env.perc(0.006, 0.11, curve: -5).ar(Done.freeSelf);
    var pitch = XLine.kr(freq * 1.08, freq, 0.10);
    var breath = BPF.ar(WhiteNoise.ar(0.10), pitch, 0.12);
    var snd = (SinOsc.ar(pitch) + breath) * env * amp;
    var stereo = Pan2.ar(snd, pan);

    Out.ar(out, stereo);
    Out.ar(~revBus, stereo * dynamic);
}).add;


// REVERB PROCESSOR
// ---------------------------------------------------------------------------
// Persistent stereo reverb processor shared by sounds that send to ~revBus.
SynthDef(\clockVerb, {
    |inBus = 0, outBus = 0, mix = 0.22, room = 0.65, damp = 0.35|
// Read two channels from the private reverb bus.
    var sig = In.ar(inBus, 2);
// Process left/right through SuperCollider FreeVerb2.
    var wet = FreeVerb2.ar(sig[0], sig[1], mix, room, damp);
    Out.ar(outBus, wet);
}).add;

"ClockToy SynthDefs installed.".postln;
};

// Sound palette: the scanner emits abstract roles; this mapping decides their sound.
// Later, activity data can replace this mapping without changing the clock geometry.



// ABSTRACT ROLE -> SOUND MAPPING
// ---------------------------------------------------------------------------
// Declarative mapping from abstract GUI roles to intended sound names.
~clockSoundMap = (
    rowStart: \plucking,
    cell: \hat,
    columnStart: \bassDrum,
    columnCell: \shortWhistle
);


// BUILD MUSICAL PATTERN FROM ~clockEvents
// ---------------------------------------------------------------------------
// Convert the current ~clockEvents Array into the repeating musical Pbind.
~buildClockPattern = {
// Use an empty Array if the GUI has not yet produced any events.
    var events = ~clockEvents ? [];
// Build a harmless rest pattern rather than failing on an empty event stream.
    if(events.isEmpty) {
        "No active clock cells to play.".warn;
// Construct an Event pattern whose source clock-cell sequence repeats forever.
        ~clockPattern = Pbind(
            \dur, 1,
            \type, \rest
        );
    } {

// Construct an Event pattern whose source clock-cell sequence repeats forever.
~clockPattern = Pbind(
			\dur, 1,
			\clockEvent, Pseq(events, inf),

			\instrument, Pfunc { |event|
				if(event[\clockEvent][\role] == \rowStart)
				{ \plucking }
				{ \hat }
			},

			\updateGUI, Pfunc { |event|
				var cell = event[\clockEvent];
				{
					~flashRow.value(
						cell[\row],
						cell[\panel],
						cell[\segment],
						Color.blue
					);
				}.defer;
			}
		);
    };
};


// Build the second, simultaneous percussion track from the by-column scan.
~buildColumnPattern = {
    var events = ~columnEvents ? [];

    if(events.isEmpty) {
        "No active column cells to play.".warn;
        ~columnPattern = Pbind(\dur, 1, \type, \rest);
    } {
        ~columnPattern = Pbind(
            \dur, 1,
            \clockEvent, Pseq(events, inf),

            \instrument, Pfunc { |event|
                if(event[\clockEvent][\role] == \columnStart)
                    { \bassDrum }
                    { \shortWhistle }
            },

            \updateGUI, Pfunc { |event|
                var cell = event[\clockEvent];
                {
                    ~flashColumn.value(
                        cell[\column],
                        cell[\panel],
                        cell[\segment],
                        Color.black
                    );
                }.defer;
            }
        );
    };
};


// ---------------------------------------------------------------------------
// START PATTERN
// ---------------------------------------------------------------------------
// Ensure the reverb exists, build the current pattern, and start playback.
~setStartPbinds = {
    if(~clockRev.isNil or: { ~clockRev.isRunning.not }) {
        ~clockRev = Synth(
            \clockVerb,
            [\inBus, ~revBus, \outBus, 0]
        );
    };

    ~buildClockPattern.value;
    ~buildColumnPattern.value;

    if(~playRowTrack) {
        ~clockPlayer = ~clockPattern.play(t, quant: 1);
    };

    if(~playColumnTrack) {
        ~columnPlayer = ~columnPattern.play(t, quant: 1);
    };
};


// ---------------------------------------------------------------------------
// STOP PATTERN
// ---------------------------------------------------------------------------
// Stop the active EventStreamPlayer and clear its reference.
~stopPbinds = {
    if(~clockPlayer.notNil) {
        ~clockPlayer.stop;
        ~clockPlayer = nil;
    };
    if(~columnPlayer.notNil) {
        ~columnPlayer.stop;
        ~columnPlayer = nil;
    };
};


// ---------------------------------------------------------------------------
// REBUILD PATTERN OBJECT
// ---------------------------------------------------------------------------
// Rebuild ~clockPattern from the current ~clockEvents without starting it.
~updatePbinds = {
    ~buildClockPattern.value;
    ~buildColumnPattern.value;
};


// ---------------------------------------------------------------------------
// RESTART CURRENT PATTERN
// ---------------------------------------------------------------------------
// Defensive stop, then play the already rebuilt ~clockPattern.
~restartPbinds = {
    ~stopPbinds.value;

    if(~playRowTrack) {
        ~clockPlayer = ~clockPattern.play(t, quant: 1);
    };

    if(~playColumnTrack) {
        ~columnPlayer = ~columnPattern.play(t, quant: 1);
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

// Hot reload: after startup, evaluating this whole file sends any edited
// SynthDefs to the already-running server.  Before startup, CT6main does it.
if(s.serverRunning and: { ~revBus.notNil }) {
    ~installSynthDefs.value;
};

)
