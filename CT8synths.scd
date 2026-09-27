// ============================================================================
// CT8synths.scd
// CLOCKTOY - SOUND DEFINITIONS (SYNTHDEFS + LIVE PARAMETERS)
// ============================================================================
//
// Everything sound-generating lives here: SynthDefs, the ~availableSynths
// table describing each one's live-adjustable parameters, and
// ~getSynthParam, the lookup function CT8tracks.scd's Pbinds use to read
// those parameters fresh on every note. This file knows nothing about
// tracks, patterns, or the clock face - CT8tracks.scd is the file that
// decides which synth plays when and reads its parameters via
// ~getSynthParam.
//
// Split out of the original CT8syn.scd (which mixed synth definitions with
// track-generation logic) so the two concerns - "what sounds exist" vs "how
// tracks are built" - can be worked on independently. Globals are declared
// up top, before any function, so the data this file works with (the synth
// table, live param state, reverb defaults) is visible at a glance.
//
// CT8main.scd calls ~installSynthDefs once the audio server has booted and
// ~revBus exists. Re-evaluating this whole file while the project is
// running also re-installs any edited SynthDefs immediately (see the
// `if(s.serverRunning and: ...)` guard at the bottom).
//


(

// ---------------------------------------------------------------------------
// AVAILABLE SYNTHS
// ---------------------------------------------------------------------------
// One row per synth: [synthName, [paramName, lo, hi, default, step], ...].
// Add a new SynthDef below, then add its row here - with as many or as few
// [paramName, lo, hi, default, step] param specs as you want live control
// over - to make it selectable in the Synth Controls window's Row/Col
// Start/Cell menus. The window builds its per-synth control rows straight
// from this table (see ~makeSynthWindow, CT8guiSynth.scd), so nothing else
// needs to change to add a synth or give it a new live-editable parameter.
~availableSynths = [
    [\baseD,
        [\basefreq, 20, 2000, 50, 1],
        [\amp, 0, 4, 2, 0.01]
    ],
    [\cym,
        [\basefreq, 20, 4000, 300, 10],
        [\len, 0.01, 4, 0.25, 0.01],
        [\amp, 0, 4, 0.1, 0.01]
    ],
    [\plucking,
        [\freq, 20, 2000, 440, 1],
        [\sAmp, 0, 4, 0.5, 0.01]
    ],
    [\hat,
        [\freq, 20, 8000, 4200, 10],
        [\amp, 0, 4, 0.2, 0.01]
    ]
];

// ~synthParamSpecs: synth -> (paramName -> [lo, hi, default, step]) - a
// quick-lookup Event built from ~availableSynths, for the GUI and
// ~getSynthParam below.
// ~synthParams: synth -> (paramName -> current live value). Persists across
// re-evaluations of this file (only backfills defaults for synths/params
// that are new since last time), so live tweaks in the Synth Controls
// window survive re-running this file.
~synthParamSpecs = ();
~synthParams = ~synthParams ? ();
~availableSynths.do { |row|
    var synthName = row[0];
    var specs = ();
    ~synthParams[synthName] = ~synthParams[synthName] ? ();
    row[1..].do { |paramSpec|
        var pname = paramSpec[0];
        specs[pname] = paramSpec[1..]; // [lo, hi, default, step]
        ~synthParams[synthName][pname] = ~synthParams[synthName][pname] ? paramSpec[3];
    };
    ~synthParamSpecs[synthName] = specs;
};


// ---------------------------------------------------------------------------
// REVERB CONTROLS
// ---------------------------------------------------------------------------
// Live-adjustable parameters for the persistent ~clockRev Synth (\ELIreverb,
// below). Unlike ~synthParams (per-note synths, read fresh via Pfunc on
// every trigger), ~clockRev is one long-running Synth instance, so "live"
// here means calling .set directly on it - see the Reverb Controls window
// (CT8guiReverb.scd), which does exactly that. Persist across
// re-evaluations, defaulting to \ELIreverb's own SynthDef defaults.
~reverbDec = ~reverbDec ? 4;
~reverbLpf = ~reverbLpf ? 1500;
~reverbMix = ~reverbMix ? 0.5;


// ---------------------------------------------------------------------------
// PARAMETER LOOKUP
// ---------------------------------------------------------------------------
// Look up a synth's current live parameter value, or fall back if that
// synth has no such parameter (e.g. plucking/hat, which have no live
// controls wired up yet). Used by CT8tracks.scd's Pbinds so each Pbind key
// works uniformly no matter which specific synth is actually playing.
~getSynthParam = { |synth, paramName, fallback|
    if(~synthParamSpecs[synth].notNil and: { ~synthParamSpecs[synth].includesKey(paramName) }) {
        ~synthParams[synth][paramName]
    } {
        fallback
    }
};


// ---------------------------------------------------------------------------
// SYNTHDEFS
// Keep SynthDef creation in a function.  CT8main calls this only after the
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
        * EnvGen.kr(Env.perc(0.01, 0.008));

    snd = Pluck.ar(
        excitation,
        Impulse.kr(0),
        0.5,
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

//Synth(\plucking, [\freq, 260, \amp, 1.5, \sus, 0.6, \dynamic, 20]);

// ---------------------------------------------------------------------------
// HAT - short metallic cymbal tick
// ---------------------------------------------------------------------------
SynthDef(\hat, {
    |amp = 0.2, pan = 0, out = 0, freq = 4200 noiseFreq = 1000|

    var env, noise, metal, snd;

    // Extremely short envelope
    env = Env.perc(0.001, 0.018).ar(Done.freeSelf);

    // Bright broadband component
    noise = HPF.ar(WhiteNoise.ar, noiseFreq);

// Inharmonic metallic components: same four partials as before, now scaled
// from freq instead of hardcoded, so freq=4200 (the default) sounds
// identical to the original fixed [4200, 5350, 7100, 4300].
    metal = Mix.ar(
        SinOsc.ar(freq * [1, 1.273809524, 1.690476190, 1.023809524])
    ) * 0.15;

    snd = (noise * 0.75) + metal;
    snd = HPF.ar(snd, 5000);
    snd = snd * env * amp;

    Out.ar(out, Pan2.ar(snd, pan));
}).add;

//Synth(\hat, [ \amp, 1.9,\freq, 200, \noiseFreq, 1000]);

// ---------------------------------------------------------------------------
// BASS DRUM (legacy, unused) - replaced by \baseD
// ---------------------------------------------------------------------------
// Not in ~availableSynths, so the Synth Controls menus can't select it.
// Still compiled/installed below; kept only for reference/comparison.
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
// SHORT WHISTLE (legacy, unused) - replaced by \cym
// ---------------------------------------------------------------------------
// Not in ~availableSynths, so the Synth Controls menus can't select it.
// Still compiled/installed below; kept only for reference/comparison.
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

//Synth(\shortWhistle, [ \amp, 0.9,\freq, 1500]);

// ---------------------------------------------------------------------------
// CYMBAL - classic 6-square-wave metallic cymbal (808/909-style technique)
// ---------------------------------------------------------------------------
SynthDef(\cym, {|t_trig = 1, out=0, basefreq = 300, len = 0.25, amp=1, pan = 0|

// Six inharmonic ratios (an approximation of a bell/cymbal's partials),
// scaled by basefreq.
	var freqs = basefreq * [ 1, 1.4823959094229, 1.800048697346, 2.545458972486, 2.6322863403944, 3.9552471390309 ];
	var signal, pulseEnv;

	pulseEnv = EnvGen.ar(Env([1.0, 0.6], [len], [-0.5]), t_trig);
	signal = Mix.new(LFPulse.ar(freqs * 4.09));
// XOR-style decode: sum six square waves, then pick out specific sums
// (how many of the six happen to be high at once) and weight each
// differently, which is what gives this its metallic, non-tonal character.
	signal = (BinaryOpUGen('==', signal, 6.0) * 0.6) + (BinaryOpUGen('==', signal, 2.0) * 0.2) + (BinaryOpUGen('==', signal, 1.0) * 0.9);
 	signal = (signal * pulseEnv) + (Mix.new(LFPulse.ar(freqs, width:0.55)) * 0.9);
	signal = RLPF.ar(signal, 7000, 0.6);
 	signal = RHPF.ar(signal, 6800, 1.5);
	signal = RHPF.ar(signal, 6800, 1.5);
	signal = RHPF.ar(signal, 1200, 1.5);
	signal = signal + FreeVerb.ar(signal);
	signal = signal * EnvGen.ar(Env([0, 1, 0.4, 0, 0], [0.002, len, 0.05, 0.5], [0, -0.5, 0, -50]), t_trig, doneAction:2);
	signal = [signal, DelayN.ar(signal, 0.005, 0.005)];
	signal = signal * (amp * 0.4);
	Out.ar(out, signal);
}).add;
//Synth(\cym, [\basefreq, 1500, \len, 1]);


// ---------------------------------------------------------------------------
// bass drum better
// ---------------------------------------------------------------------------
SynthDef(\baseD, {|t_trig = 1, basefreq = 55, rq = 0.1, overdrive = 2, samplen = 100, amp = 1, pan = 0, out = 0|
	var output, failsafe, safetyTimeout, makeupgain = 3.5;

	output = Trig.ar(t_trig,samplen/SampleRate.ir);
	output = BPF.ar(output,basefreq,rq,amp*makeupgain);
	output = (output * overdrive).tanh;
	failsafe = FreeSelf.kr(Trig.kr(t_trig) * (amp <= 0));
	DetectSilence.ar(output, time: 0.1, doneAction:2);
// Hard cutoff: guarantees this synth frees within 3 seconds even if
// DetectSilence never crosses its threshold (e.g. a very low rq ringing
// almost indefinitely). Without this, a run of unlucky parameters lets
// instances accumulate forever - the likely cause of "out of real time
// memory" after a long run, since every other active synth here frees via
// a fixed-duration envelope, not amplitude detection.
	safetyTimeout = Line.kr(0, 0, 3, doneAction: 2);
	output = Pan2.ar(output, pan);
	Out.ar(out, output);
}).add;
Synth(\baseD, [\basefreq, 180]);

// ---------------------------------------------------------------------------
// eli fm
// ---------------------------------------------------------------------------
// Multi use FM synth
	SynthDef(\fm, {
		arg freq=500, mRatio=1, cRatio=1,
		index=1, iScale=5, cAtk=4, cRel=(-4),
		amp=0.2, atk=0.01, rel=3, pan=0,
		out=0, fx=0, fxsend=(-25);
		var car, mod, env, iEnv;

		//index of modulation
		iEnv = EnvGen.kr(
			Env(
				[index, index*iScale, index],
				[atk, rel],
				[cAtk, cRel]
			)
		);

		//amplitude envelope
		env = EnvGen.kr(Env.perc(atk,rel,curve:[cAtk,cRel]),doneAction:2);

		//modulator/carrier
		mod = SinOsc.ar(freq * mRatio, mul:freq * mRatio * iEnv);
		car = SinOsc.ar(freq * cRatio + mod) * env * amp;

		car = Pan2.ar(car, pan);

		//direct out/reverb send
		Out.ar(out, car);
		Out.ar(fx, car * fxsend.dbamp);
	}).add;




    // REVERB PROCESSOR (legacy, unused) - replaced by \ELIreverb, below
// ---------------------------------------------------------------------------
// Persistent stereo reverb processor shared by sounds that send to ~revBus.
// Still compiled/installed below; kept only for reference/comparison.
SynthDef(\clockVerb, {
    |inBus = 0, outBus = 0, mix = 0.22, room = 0.65, damp = 0.35|
// Read two channels from the private reverb bus.
    var sig = In.ar(inBus, 2);
// Process left/right through SuperCollider FreeVerb2.
    var wet = FreeVerb2.ar(sig[0], sig[1], mix, room, damp);
    Out.ar(outBus, wet);
}).add;

// Modified from ELi
// This is now the active persistent reverb (see ~setStartPbinds, CT8tracks.scd) -
// \clockVerb, above, is left defined but unused.
SynthDef(\ELIreverb, {
    arg in=0, out=0, dec=4, lpf=1500, mix=0.5;
    var dry, wet;

// Bug fix: the arg is named "in"/"out", not "inBus"/"outBus" - those aren't
// declared anywhere, so this wouldn't even compile as originally written.
    dry = In.ar(in, 2);
    wet = dry.sum;
    wet = DelayN.ar(wet, 0.03, 0.03);
    wet = CombN.ar(wet, 0.1, { Rand(0.01, 0.099) } ! 32, dec);
    wet = SplayAz.ar(2, wet);
    wet = LPF.ar(wet, lpf);
    5.do {
        wet = AllpassN.ar(
            wet,
            0.1,
            { Rand(0.01, 0.099) } ! 2,
            3
        )
    };
    wet = LPF.ar(wet, lpf);
    wet = LeakDC.ar(wet);
    Out.ar(out, XFade2.ar(dry, wet, mix.linlin(0, 1, -1, 1)));
}).add;

};

// Hot reload: after startup, evaluating this whole file sends any edited
// SynthDefs to the already-running server.  Before startup, CT8main does it.
if(s.serverRunning and: { ~revBus.notNil }) {
    ~installSynthDefs.value;
};
"CT8 synth definitions loaded.".postln;
)
