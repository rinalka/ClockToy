// ============================================================================
// CT8synths.scd
// CLOCKTOY - SOUND DEFINITIONS (SYNTHDEFS + LIVE PARAMETERS)
// ============================================================================
//
// Everything sound-generating lives here: SynthDefs, plus a couple of
// globals (~reverbDec/~reverbLpf/~reverbMix) for the persistent reverb
// Synth. This file knows nothing about tracks, patterns, or the clock face
// - CT8tracks.scd is the file that decides which synth plays when and with
// which parameters (its own per-track Percussion Generator config now, not
// anything from here).
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
// REVERB CONTROLS
// ---------------------------------------------------------------------------
// Live-adjustable parameters for the persistent ~clockRev Synth (\ELIreverb,
// below) - one long-running Synth instance, unlike every per-note synth
// CT8tracks.scd triggers fresh each hit. No GUI
// currently exposes these live (the old Reverb Controls window was removed -
// see CLAUDE.md); for now, adjust by editing these defaults directly. Persist
// across re-evaluations, defaulting to \ELIreverb's own SynthDef defaults.
~reverbDec = ~reverbDec ? 4;
~reverbLpf = ~reverbLpf ? 1500;
~reverbMix = ~reverbMix ? 0.5;


// ---------------------------------------------------------------------------
// SHARED ALLPASS WASH
// ---------------------------------------------------------------------------
// \hat/\cym/\baseD/\kick/\fm/\plucking's own built-in \wet/\level reverb (below) - same
// dry/wet/level algorithm as the standalone \allpassReverb synth further
// down, just inline rather than reading from a bus: a chain of 10 AllpassN
// filters (each channel independently randomized, so even a mono `sig`
// comes out decorrelated-stereo), crossfaded against the dry signal by
// `wet` and scaled by `level` afterward. `level` defaults to 1 here (not
// \allpassReverb's own 0.6), so `wet=0, level=1` - the default every
// caller below uses - is truly a no-op, not a volume change. This is a
// plain helper function, not a SynthDef, so reusing it directly in
// CT8guiSynthLab.scd's \labHat/\labCym is fine and not the kind of
// SynthDef-sharing this project otherwise avoids across the lab split -
// there's no bus-routing assumption baked into it to conflict with.
~allpassWash = { |sig, wet = 0, level = 1|
    var fx = sig;
    10.do { fx = AllpassN.ar(fx, 0.05, [Rand(0, 0.05), Rand(0, 0.05)], 1) };
    XFade2.ar(sig, fx, wet.linlin(0, 1, -1, 1)) * level;
};

// ---------------------------------------------------------------------------
// AUX SEND BUS (shared by every track's own two aux sends - "mixer phase")
// ---------------------------------------------------------------------------
// ~auxSend is the per-SynthDef half of this: a plain helper (not a SynthDef,
// same idea as ~allpassWash) that writes a SCALED copy of this synth's own
// finished output to up to two destination buses, in addition to its normal
// Out.ar(out, sig). amtA/amtB default to 0, so this is a no-op by
// multiplication wherever a track's two aux sends haven't been turned up -
// the same "silent unless deliberately set" convention wet/level already
// use. busA/busB are plain bus-index Floats/Integers here (Out.ar accepts
// either) - CT8tracks.scd's own builders are the ones that have to be
// careful passing a live Bus reference through a Pbind key (see ~buildPercPattern's
// own \fx comment) rather than this helper, which just receives whatever a
// SynthDef arg resolves to.
~auxSend = { |sig, busA = 0, amtA = 0, busB = 0, amtB = 0|
    Out.ar(busA, sig * amtA);
    Out.ar(busB, sig * amtB);
};



// ---------------------------------------------------------------------------
// SYNTHDEFS
// Keep SynthDef creation in a function.  CT8main calls this only after the
// server has booted and ~revBus exists.  Evaluating this file again while the
// project is running also installs edited SynthDefs immediately.
~installSynthDefs = {

// ~auxEffectNames/~auxEffectBuses are the "mixer phase" effects registry,
// per feedback - two parallel arrays (same convention CT8guiSynthLab.scd's
// own names/synthNames already use), index-matched: ~auxEffectNames[i] is
// the GUI label for the dropdown each track's Send A/Send B gets
// (CT8guiPercGenerator.scd/CT8guiHarmonyMelodyGenerator.scd), ~auxEffectBuses[i]
// is the actual Bus every track currently assigned to effect i sends into.
// Built here, inside ~installSynthDefs, rather than at this file's own
// top level, because ~revBus (effect 0, "ELI Reverb" - the first entry,
// per feedback, reusing the SAME bus/Synth \fm/\plucking's own \fx send
// already reaches, rather than standing up a second, redundant reverb
// instance) doesn't exist yet until CT8main.scd's boot sequence creates
// it, right before calling ~installSynthDefs the first time. Adding a
// second effect (a bandpass filter, an echo - per feedback, both planned)
// later is just appending one more name and one more bus/Synth here, not
// a redesign.
    ~auxEffectNames = ["ELI Reverb"];
    ~auxEffectBuses = [~revBus];


// // PLUCK SYNTH
// SynthDef(\plucking, {
//     arg outbus = 0, amp = 0.2, sAmp = 0.5,
//         freq = 440, pluckDecay = 0.35, coef = 0.25, pan = 0,
//         atk = 0.001, sus = 0.015, rel = 0.10,
//         dynamic = 0.25, wet = 0, level = 1;

//     var env, excitation, snd;

//     // Very short amplitude envelope
//     env = EnvGen.kr(
//         Env.linen(atk, sus, rel),
//         doneAction: 2
//     );

//     // Short noise impulse excites the string
//     excitation = BrownNoise.ar(amp)
//         * EnvGen.kr(Env.perc(0.01, 0.008));

//     snd = Pluck.ar(
//         excitation,
//         Impulse.kr(0),
//         0.5,
//         freq.reciprocal,
//         pluckDecay,
//         coef
//     );

//     snd = LeakDC.ar(snd).clip2;
//     snd = Pan2.ar(snd, pan);

//     // Keep existing reverb send for now - unaffected by wet/level below,
//     // same reason as \fm's fx/fxsend (see its comment).
//     Out.ar(~revBus, snd * env * dynamic);

//     // This instrument's own tiny built-in reverb tail, same ~allpassWash
//     // \hat/\cym/\baseD/\kick already use - added for BT1/BT2's Wet/Level
//     // sliders (CT8guiPercGenerator.scd), which need \plucking to actually
//     // have a wet/level knob to turn.
//     Out.ar(outbus, ~allpassWash.(snd * env * sAmp, wet, level));
// }).add;

//Synth(\plucking, [\freq, 260, \amp, 1.5, \sus, 0.6, \dynamic, 20]);

SynthDef(\plucking, {
    arg out = 0,
        freq = 440,
        amp = 0.5,
        pluckDecay = 0.35,
        coef = 0.25,
        pan = 0,
        atk = 0.001,
        sus = 0.015,
        rel = 0.10,
        wet = 0,
        level = 1,
        dynamic = 0.25,
        auxBusA = 0, auxAmtA = 0, auxBusB = 0, auxAmtB = 0;


    var env, excitation, snd;
    var bassBoost, excDecay, bassRel;

    // 1.0 at middle C (261.63 Hz) and above.
    // Gradually increases below middle C.
    bassBoost = (261.63 / freq).sqrt.clip(1, 2.5);

    // Give lower notes a somewhat longer excitation.
    excDecay = (0.008 * bassBoost).clip(0.008, 0.025);

    // Give lower notes more time to develop/ring.
    bassRel = rel * bassBoost;

    env = EnvGen.kr(
        Env.linen(atk, sus, bassRel),
        doneAction: 2
    );

    excitation = BrownNoise.ar(amp * bassBoost)
        * EnvGen.kr(
            Env.perc(0.005, excDecay)
        );

    snd = Pluck.ar(
        excitation,
        Impulse.kr(0),
        0.5,
        freq.reciprocal,
        pluckDecay,
        coef
    );

    snd = LeakDC.ar(snd);
    snd = snd.clip2;
    snd = Pan2.ar(snd, pan);

// ~revBus send has its own independent attenuation (dynamic) - unlike
// wet/level below, which only control the private ~allpassWash tail on the
// main output. Without this, the send is exactly as loud as the dry
// signal, which (unlike \fm's deliberately quiet -25dB fxsend into this
// same shared bus) is loud enough to dominate ~clockRev regardless of this
// note's own wet/level/amp.
    Out.ar(~revBus, snd * env * dynamic);
    snd = ~allpassWash.(snd * env, wet, level);
    ~auxSend.(snd, auxBusA, auxAmtA, auxBusB, auxAmtB);
    Out.ar(out, snd);
}).add;

// ---------------------------------------------------------------------------
// HAT - short metallic cymbal tick
// ---------------------------------------------------------------------------
SynthDef(\hat, {
    |amp = 0.2, pan = 0, out = 0, freq = 4200, noiseFreq = 1000, wet = 0, level = 1,
     auxBusA = 0, auxAmtA = 0, auxBusB = 0, auxAmtB = 0|

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
    snd = Pan2.ar(snd, pan);

// Tiny built-in reverb tail, ~allpassWash (above) rather than FreeVerb (an
// earlier mistake) - defaults to wet=0 (fully dry) so the real
// composition's Pbinds, which never set \wet, are unaffected;
// CT8guiSynthLab.scd/CT8guiTracksLab.scd and the Percussion Generator
// (~percWet[name]/~percLevel[name], CT8tracks.scd) are the only things
// that ever set it above 0. Caveat shared by every synth with this tail:
// env's doneAction:2 (above) frees the whole synth - reverb tail included
// - based on the DRY signal going silent, so a nonzero wet's tail gets cut
// off abruptly rather than ringing all the way out. Acceptable for
// "simple," not worth the extra complexity of decoupling the free timer
// from the dry envelope for this.
    snd = ~allpassWash.(snd, wet, level);
    ~auxSend.(snd, auxBusA, auxAmtA, auxBusB, auxAmtB);
    Out.ar(out, snd);
}).add;

//Synth(\hat, [ \amp, 1.9,\freq, 200, \noiseFreq, 1000]);

// ---------------------------------------------------------------------------
// CYMBAL - classic 6-square-wave metallic cymbal (808/909-style technique)
// ---------------------------------------------------------------------------
SynthDef(\cym, {|t_trig = 1, out=0, basefreq = 300, len = 0.25, amp=1, pan = 0, wet = 0, level = 1,
    auxBusA = 0, auxAmtA = 0, auxBusB = 0, auxAmtB = 0|

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
	signal = signal * EnvGen.ar(Env([0, 1, 0.4, 0, 0], [0.002, len, 0.05, 0.5], [0, -0.5, 0, -50]), t_trig, doneAction:2);
	signal = [signal, DelayN.ar(signal, 0.005, 0.005)];
	signal = signal * (amp * 0.4);
// ~allpassWash (see \hat's comment for the general default/caveat every
// synth with this tail shares) rather than FreeVerb (an earlier mistake).
	signal = ~allpassWash.(signal, wet, level);
	~auxSend.(signal, auxBusA, auxAmtA, auxBusB, auxAmtB);
	Out.ar(out, signal);
}).add;
//Synth(\cym, [\basefreq, 1500, \len, 1]);


// ---------------------------------------------------------------------------
// bass drum better
// ---------------------------------------------------------------------------
SynthDef(\baseD, {|t_trig = 1, basefreq = 55, rq = 0.1, overdrive = 2, samplen = 100, amp = 1, pan = 0, out = 0, wet = 0, level = 1,
    auxBusA = 0, auxAmtA = 0, auxBusB = 0, auxAmtB = 0|
	var output, failsafe, safetyTimeout, makeupgain = 3.5;

	output = Trig.ar(t_trig,samplen/SampleRate.ir);
	output = BPF.ar(output,basefreq,rq,amp*makeupgain);
	output = (output * overdrive).tanh;
	failsafe = FreeSelf.kr(Trig.kr(t_trig) * (amp <= 0));
// Hard cutoff: guarantees this synth frees within 3 seconds even if
// DetectSilence never crosses its threshold (e.g. a very low rq ringing
// almost indefinitely). Without this, a run of unlucky parameters lets
// instances accumulate forever - the likely cause of "out of real time
// memory" after a long run, since every other active synth here frees via
// a fixed-duration envelope, not amplitude detection.
	safetyTimeout = Line.kr(0, 0, 3, doneAction: 2);
	output = Pan2.ar(output, pan);
// ~allpassWash (see \hat's comment for the general default/caveat) rather
// than FreeVerb (an earlier mistake). DetectSilence now watches the
// POST-wash signal (moved below) rather than the dry `output` above, so a
// nonzero wet's tail gets to ring out fully before this synth frees -
// identical timing to before when wet=0, since the wash is then a bit-exact
// no-op.
	output = ~allpassWash.(output, wet, level);
	~auxSend.(output, auxBusA, auxAmtA, auxBusB, auxAmtB);
	DetectSilence.ar(Mix.ar(output), time: 0.1, doneAction: 2);
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
		out=0, fx=0, fxsend=(-25), wet=0, level=1,
		auxBusA=0, auxAmtA=0, auxBusB=0, auxAmtB=0;
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

		//direct out/reverb send - fx/fxsend unaffected by wet/level below,
		//so BT1/BT2's own Wet/Level sliders (CT8guiPercGenerator.scd) don't
		//change how loud this reaches the shared ~clockRev send; HT1/MT1
		//never set wet/level, so this is a no-op for them (see ~allpassWash,
		//above).
		Out.ar(fx, car * fxsend.dbamp);

		//this instrument's own tiny built-in reverb tail, same ~allpassWash
		//~hat/\cym/\baseD/\kick already use - added for BT1/BT2's Wet/Level
		//sliders, which need \fm to actually have a wet/level knob to turn.
		car = ~allpassWash.(car, wet, level);
		~auxSend.(car, auxBusA, auxAmtA, auxBusB, auxAmtB);
		Out.ar(out, car);
	}).add;




// Modified from ELi
// This is now the active persistent reverb (see ~setStartPbinds, CT8tracks.scd).
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


// ---------------------------------------------------------------------------
// Incorporated from Ct8synthLab.scd (the user's standalone sound-experiment
// file) - the interface for auditioning these lives in CT8guiSynthLab.scd.
// Not used by any track builder yet - that's a separate step for whenever
// they're ready to be used in a track, not assumed here.

// Drone: 20 detuned sawtooth voices, each independently filtered and
// amplitude-modulated by slow LFNoise, for a shifting cluster/pad texture.
SynthDef(\drone, { |out=0, freq=110, dur=5, amp=0.4, pan=0,
    width=0.025, filterRatio=2|
    var env, sig, stereo;
    env = EnvGen.kr(Env([0, 1, 1, 0], [1, dur, 3]), doneAction: 2);
    sig = Array.fill(20, {
        var multiplier, ampmult, oscFreq, filterDrift, cutoff;
        multiplier = [0.99, 1, 1.01, 1.99, 2, 2.01, 3.99, 4, 4.01].choose;
        ampmult = multiplier.reciprocal;
        oscFreq = LFNoise1.kr(0.5.rrand(1.0)).range(
            freq * (1-width), freq * (1+width)) * multiplier;
        filterDrift = LFNoise1.kr(0.15.rrand(0.45)).range(0.8, 1.25);
        cutoff = (oscFreq * filterRatio * filterDrift).clip(30, 18000);
        RLPF.ar(
            LFSaw.ar(oscFreq, iphase: 0.0.rrand(2.0)),
            freq: cutoff,
            rq: LFNoise1.kr(0.5).range(0.1, 0.6),
            mul: LFNoise0.kr(2).range(16.reciprocal, ampmult)
        )
    });
    stereo = Splay.ar(env * sig);
    Out.ar(out, amp * Balance2.ar(stereo[0], stereo[1],
        pan * SinOsc.kr(LFNoise1.kr(1).range(0.05, 0.2))));
}).add;

// Lead: sawtooth through a wobbling resonant filter, thickened by a chain
// of 10 allpass filters.
// freq is a MIDI note number now, not Hz (default 69 = A4 = the old literal
// 440 default, exactly) - same "plain control arg, .midicps'd inside the
// body" pattern as \droneChord's own note1-4 (CT8synths.scd's own bullet),
// so the Synth Lab's \midi slider curve (integer-rounded, 0 decimals) means
// something sensible here. sharpness used to compute freq.cpsmidi (Hz back
// to MIDI) - now redundant/simplified away, since freq already IS the MIDI
// value it used to convert TO. Clamped to [30, 99] per feedback ("lead
// needs to limit freq to never go below 30 or above 99") - both here (so
// anything that ever feeds this synth an out-of-range value stays safe)
// and in the Synth Lab's own slider range (CT8guiSynthLab.scd), which can
// no longer produce one in the first place.
// rel (the overall envelope's release time) is a real control arg now,
// not a hardcoded local var - per feedback ("added a release variable rel
// to lead, can you please see it gets into synthlab"). That envelope's own
// release segment is curve -4 now (was unspecified, i.e. linear) - per
// feedback ("i would like the release for the overall envelope to be
// gradual") - NOT the literal \exp curve type: that's degenerate for a
// segment ENDING at 0 (the level just holds at its start value until the
// very last instant, then drops instantly - not gradual at all, a
// different failure mode than \exp's own NaN-at-a-zero-START bug found
// earlier on \droneChord/\shimmerPad, but still wrong). -4 is this
// project's own established, safe way to get a natural-sounding gradual
// decay on a segment touching zero (same curve \shimmerPad/\kick use).
SynthDef(\lead, { |out=0, freq=69, dur=2, amp=0.7, pan=0,
    wobblelow=0.3, wobblehigh=1, rel=2|
    var atk = 0.5;
    var midiFreq = freq.clip(30, 99);
    var hzFreq = midiFreq.midicps;
    var env = EnvGen.kr(Env([0, 1, 1, 0], [atk, (dur-atk).max(0.01), rel], [\lin, \lin, -4]), doneAction: 2);
    var freqenv = EnvGen.kr(Env([0.7, 1, 1], [0.3, dur]));
    var sharpness = midiFreq.linlin(0, 127, 1, 15);
    var wobble = SinOsc.kr(6).range(wobblelow, wobblehigh);
    var sig = RLPF.ar(
        LFSaw.ar(freqenv * hzFreq * LFNoise1.kr(1).range(0.995, 1.005)),
        hzFreq * sharpness, LFNoise1.kr(3).range(0.2, 0.5), wobble
    );
    10.do { sig = AllpassN.ar(sig, 0.05, [Rand(0, 0.05), Rand(0, 0.05)], 1) };
    Out.ar(out, amp * env * Pan2.ar(sig / 10, pan));
}).add;

// Seq: pulse wave through a swept lowpass, with an optional pitch glide at
// the start of each note - a short plucky sequencer voice.
// freq is a MIDI note number now, not Hz (default 76, the nearest integer
// MIDI note to the old literal 660 default - 76.midicps is ~659.26, under
// a Hz off) - same reasoning as \lead's own freq, just above.
SynthDef(\seq, { |out=0, freq=76, dur=0.5, amp=0.25, pan=0,
    glissdir=1, gliss=0.1|
    var hzFreq = freq.midicps;
    var laggliss = Lag.kr(gliss, 0.1);
    var env = EnvGen.kr(Env.perc(0.01, 2), doneAction: 2);
    var freqenv = EnvGen.kr(Env([
        1 + (glissdir * laggliss), 1 - (glissdir * laggliss), 1, 1
    ], [0.07, 0.07, 1]));
    var filtenv = EnvGen.kr(Env([0.5, 1, 1], [0.15, dur]));
    var sig = LPF.ar(Pulse.ar(freqenv * hzFreq), hzFreq * filtenv * 3);
    Out.ar(out, amp * env * Pan2.ar(sig, pan));
}).add;

// Noise: filtered white noise gated by a slow random pulse, swept by a
// slow-moving lowpass cutoff - a breathy/textural noise voice.
SynthDef(\noise, { |out=0, dur=5, amp=0.15, pan=0|
    var env = EnvGen.kr(Env.perc(1, dur * 0.8, curve: -10), doneAction: 2);
    var sig = LPF.ar(WhiteNoise.ar * LFPulse.kr(LFNoise1.kr(0.5).range(3, 12)),
        LFNoise1.kr(2).range(2, 1) * 4000);
    Out.ar(out, Pan2.ar(env * amp * sig, pan));
}).add;

// Noise Carrier: the "bar-long note" half of FXT1/FXT2's two-synth pulse
// design, per feedback ("treating the pulse as a separate event. the bar
// long note gets triggered, but is sent to the input of a second event
// that is the pulse envelope") - replaces the earlier single-SynthDef
// masterEnv+burstEnv design, which turned out to always have an audible
// floor present (masterEnv's own constant hold level), making the pulse
// itself barely noticeable no matter the Pulse % setting. Reuses \noise's
// own noise-generating chain (WhiteNoise through a swept LPF, gated by a
// random LFPulse) verbatim, but writes its raw, CONTINUOUS signal to a
// private per-track bus (~fxCarrierBus[name], CT8tracks.scd) instead of
// hardware output - \fxPulse (below) is the ONLY thing that actually
// shapes it and sends it to real output, so there's no floor to mask
// anything any more: between pulses, \fxPulse's own envelope is at 0,
// full silence. This envelope is just a simple fade-in/fade-out for the
// whole bar (masterDur seconds, plus a fixed 1-second tail - "a bit
// tacked on the end"), not a held level - it only exists to avoid a click
// at the bar's own start/end, since \fxPulse alone decides what's
// actually audible at any given moment. Freed via doneAction:2 at the
// bar's own end. Curve -4, safe even on the 0-start attack segment,
// unlike the literal \exp curve type (see \droneChord's own bullet for
// why not).
SynthDef(\noiseCarrier, { |out=0, masterDur=2|
    var env = EnvGen.kr(Env([0, 1, 1, 0], [0.1, masterDur, 1], -4), doneAction: 2);
    var sig = LPF.ar(WhiteNoise.ar * LFPulse.kr(LFNoise1.kr(0.5).range(3, 12)),
        LFNoise1.kr(2).range(2, 1) * 4000);
    Out.ar(out, Pan2.ar(env * sig, 0));
}).add;

// FX Pulse: the shared "pulse envelope" half of FXT1/FXT2's two-synth
// design (CT8tracks.scd's own ~buildFxPattern bullet has the full
// two-synth/bus/Group design) - ONE SynthDef, reused regardless of which
// carrier (\noiseCarrier/\rumbleCarrier, below) is currently writing to
// this track's own bus (`in`), since shaping a signal doesn't care what
// generated it. Applies a plain attack/hold/release envelope (curve -4,
// same reasoning as every other envelope here) and is the ONLY thing that
// determines whether anything is actually heard at a given moment - no
// floor underneath it the way the old masterEnv+burstEnv design had, so
// between pulses this is genuine silence, not a quieter hum. One Pbind
// event per pulse (triggered however many times a bar, per
// ~fxPattern[name]'s own Dur Pat choice) - not retriggered internally the
// way the old design was, so pulsedur/releaseDur are sized from THIS
// trigger's own actual span length every time, not a bar-wide average.
// wet/level/auxBusA-auxAmtB are the usual ~allpassWash/~auxSend tail,
// moved here from the carrier - the reverb send should colour the actual
// audible bursts, not a signal nothing ever hears on its own.
SynthDef(\fxPulse, { |in=0, out=0, pulsedur=0.2, releaseDur=0.3,
    wet=0, level=1, auxBusA=0, auxAmtA=0, auxBusB=0, auxAmtB=0|
    var env = EnvGen.kr(
        Env([0, 1, 1, 0], [0.01, pulsedur, releaseDur], -4),
        doneAction: 2
    );
    var sig = In.ar(in, 2) * env;
    sig = ~allpassWash.(sig, wet, level);
    ~auxSend.(sig, auxBusA, auxAmtA, auxBusB, auxAmtB);
    Out.ar(out, sig);
}).add;

// Kick: PMOsc drum body plus a filtered-noise beater transient, each with
// its own pitch-sweep/filter envelope; frees itself via DetectSilence once
// both have died out (no hard safety timeout like ~baseD's, so a run of
// parameters that never goes silent could in principle hang around - worth
// knowing if this ever gets used in a fast-retriggering track).
SynthDef(\kick, { |out=0, pan=0, amp=0.5, curve=(-4),
    drumAmp=1, beaterAmp=0.02, drumFreq=50, drumHarmonic=2,
    drumSweep=0.02, drumAtt=0.005, drumRel=0.4,
    drumFilter=1000, modIndex=6.5, modFreq=5,
    beaterFreq=500, beaterHarmonic=12, beaterSweep=0.03,
    beaterAtt=0.01, beaterRel=0.3, wet=0, level=1,
    auxBusA=0, auxAmtA=0, auxBusB=0, auxAmtB=0|
    var drumEnv, drumContour, drum, beaterContour, beaterEnv, beater, snd;
    drumEnv = Env.perc(drumAtt, drumRel, drumAmp, curve).kr;
    drumContour = Line.kr(drumFreq * drumHarmonic, drumFreq, drumSweep);
    drum = PMOsc.ar(drumContour, modFreq, modIndex);
    drum = LPF.ar(drum, drumFilter, drumEnv);
    beaterEnv = Env.perc(beaterAtt, beaterRel, beaterAmp, curve).kr;
    beaterContour = Line.kr(beaterFreq * beaterHarmonic, beaterFreq, beaterSweep);
    beater = HPF.ar(WhiteNoise.ar, beaterFreq);
    beater = LPF.ar(beater, beaterContour, beaterEnv);
    snd = Mix.ar(drum + beater) * amp;
    snd = Pan2.ar(snd, pan);
// ~allpassWash (see \hat's comment for the general default/caveat) rather
// than FreeVerb (an earlier mistake). DetectSilence now watches the
// POST-wash signal (moved below) rather than the dry `snd` above, so a
// nonzero wet's tail gets to ring out fully before this synth frees -
// identical timing to before when wet=0, since the wash is then a bit-exact
// no-op - mainly relevant to CT8guiTracksLab.scd/CT8guiSynthLab.scd, the
// only two places that ever trigger \kick with wet above 0.
    snd = ~allpassWash.(snd, wet, level);
    ~auxSend.(snd, auxBusA, auxAmtA, auxBusB, auxAmtB);
    DetectSilence.ar(Mix.ar(snd), doneAction: 2);
    Out.ar(out, snd);
}).add;

// Drone chord: four simultaneous MIDI notes, eight slightly detuned sine
// oscillators each. detune=1 is in tune; detune=0 allows up to +/- one
// semitone per voice (named the same way as, but unrelated in code to, the
// separately-reviewed ~droneCluster idea - that one hasn't been added).
// note1-4 are plain control args, not read from ~currentChord in here - a
// UGen graph function runs once in sclang, at .add time, so `~currentChord`
// referenced directly in this body would freeze whatever chord happened to
// be current at THAT moment forever, never updating per note (this is what
// broke "always play the notes from currentChord" - the fix lives in
// ~buildPolyPattern, CT8tracks.scd, which reads ~currentChord fresh every
// event and passes it in live as these four args instead). wet/level are
// this synth's own tiny built-in ~allpassWash tail (CT8synths.scd's own
// bullet - same convention as every other instrument's), defaulting to a
// no-op like always; attack/sustain/release/amp defaults per feedback
// (was too soft and slow).
SynthDef(\droneChord, {
    |out=0,
     note1=48, note2=52, note3=55, note4=60,
     amp=1.5,
     attack=0.012, sustain=0.12, release=5,
     detune=10,
     driftRate=0.15, driftDepth=5,
     wet=0, level=2,
     auxBusA=0, auxAmtA=0, auxBusB=0, auxAmtB=0|

    var notes, voices, sig, env;
    notes = [note1, note2, note3, note4];
    voices = notes.collect { |note|
        var frequency = note.midicps;
        Splay.ar(Array.fill(8, {
            var offset, drift, cents, oscillatorFreq;
            offset = Rand(-1.0, 1.0) * detune;
            drift = LFNoise2.kr(
                Rand(0.5, 1.5) * driftRate
            ) * driftDepth;
            cents = offset + drift;
            // Convert cents to frequency
            oscillatorFreq = frequency * (2 ** (cents / 1200));
            SinOsc.ar(
                oscillatorFreq,
                Rand(0, 2pi),
                0.125
            )
        }))
    };
    sig = Mix.new(voices) * 0.25;
// Curve -4 (numeric), not the literal \exp symbol - \exp's curve formula is
// a*(b/a)^phase, which divides by the segment's OWN START level; this
// envelope's attack segment starts at 0, so \exp here produced NaN on
// every note, poisoning the shared hardware output bus every other track
// also sums into and silencing everything, not just this synth (per
// feedback: "everything works until i try to play a dronechord - then all
// sound stops"). -4 is SuperCollider's own safe approximation of an
// exponential shape for envelopes that touch 0 - the same reason
// Env.perc's own default curve is -4, not \exp.
    env = EnvGen.kr(
        Env.linen(attack, sustain, release, 1, -4),
        doneAction: 2
    );
    sig = sig * env * amp;
    sig = ~allpassWash.(sig, wet, level);
    ~auxSend.(sig, auxBusA, auxAmtA, auxBusB, auxAmtB);
    Out.ar(out, sig);
}).add;

// Shimmer pad: PinkNoise excitation through a 5-voice DynKlank resonator
// bank, one resonance per chord tone. note1-5 are plain control args, not
// a hardcoded myChord/~currentChord read in here - same reasoning as
// \droneChord's own note1-4 (see that SynthDef's comment, above): a UGen
// graph function runs once in sclang, at .add time, so reading
// ~currentChord directly in this body would freeze whatever chord was
// current at THAT moment forever. ~buildPolyPattern (CT8tracks.scd) feeds
// ~currentChord in live instead, one independent ~chordNoteInRange pick
// per voice - which already picks a random octave within HT1's own Pitch
// range, so there's no separate octave-randomizing step in here on top of
// that (an earlier draft had one, via plain-language `.choose` - removed,
// since stacking another octave shift on top of an already range-picked
// note could push it back outside that range).
// Every OTHER random element below is UGen-rate (Rand/ExpRand), not the
// plain-language `.rand2`/`exprand`/`.choose` an earlier draft used -
// those only ever evaluate once, in sclang, at .add time (the exact same
// freezing issue as a direct ~currentChord read, just easier to miss),
// so every voice's little Hz-domain jitter/ring time/LFNoise2 rate would
// otherwise have been fixed forever rather than re-rolling fresh each
// time a new note plays. Array.fill, not `{...}.dup(numvoices)` (another
// thing an earlier draft used) - .dup on a Function duplicates the
// UNEVALUATED closure, not its result, so the array ends up full of
// Function objects instead of numbers; Array.fill actually calls the
// block once per voice.
SynthDef(\shimmerPad, { |out=0, amp=0.125,
    note1=60, note2=63, note3=67, note4=71, note5=72,
    atk=2.0, sus=1.0, rel=5.0,
    wet=0, level=1,
    auxBusA=0, auxAmtA=0, auxBusB=0, auxAmtB=0|
    var sig, freqs, envs, env, rings, numvoices, notes, totalTime;

    numvoices = 5;
    notes = [note1, note2, note3, note4, note5];
    totalTime = atk + sus + rel;
    freqs = notes.collect(_.midicps) + Array.fill(numvoices, { Rand(-1.5, 1.5) });
    rings = Array.fill(numvoices, { ExpRand(totalTime * 0.6, totalTime) });
    envs = Array.fill(numvoices, { LFNoise2.kr(ExpRand(0.8, 3.5)).range(0.05, 1.0) });
 // sig = PinkNoise.ar(numvoices.reciprocal ! 2);
    sig = PinkNoise.ar(0.05 ! 2);
    sig = DynKlank.ar(`[freqs, envs, rings], sig) * 0.51;
// Curve -4 (numeric) on all three segments, not the literal \exp symbol -
// same NaN pitfall as \droneChord's own envelope, above: \exp's a*(b/a)^phase
// formula divides by the segment's start level, and this envelope's attack
// segment starts at 0 (silencing everything downstream, not just this
// synth, once that NaN hits the shared output bus). -4 is SC's own safe
// exponential-ish shape for envelopes touching 0.
    env = EnvGen.kr(Env.new([0, 1, 1, 0], [atk, sus, rel], [-4, -4, -4]), doneAction: 2);
    sig = sig * env * amp;
    sig = ~allpassWash.(sig, wet, level);
    ~auxSend.(sig, auxBusA, auxAmtA, auxBusB, auxAmtB);
    Out.ar(out, sig);
}).add;


// `{...} ! size` (4 places, originally) duplicates the UNEVALUATED function
// `size` times, not `size` independent results - the exact same bug already
// found and fixed in \shimmerPad (CT8synths.scd's own bullet) - so every
// one of the 20 "voices" below was actually hearing the SAME random saw
// mix, the SAME noise signal, and the SAME base pan position, not 20
// independent ones. Array.fill(size, {...}), which \drone (just above)
// already uses for its own near-identical 20-voice design, actually calls
// the block once per voice - per feedback ("check it out... fix the
// output"). `detune` is declared but never read anywhere in this body -
// flagged, not silently wired in, since guessing how it should affect the
// saw spread is a creative call, not a bug fix.
SynthDef(\rumble, {
    |out = 0, freq = 60, detune = 0.5, pan = 0, amp = 0.1,
     speed = 1.99, density = 1, tone = 0.25, blur = 2,
     wet=0, level=1, auxBusA=0, auxAmtA=0, auxBusB=0, auxAmtB=0|
    var sig;
    var size = 20;
    var trig = Impulse.ar(
        Array.fill(size, { rrand(1.0, 15.0) }) * density
    );

	sig = Array.fill(size, {
        var sawFreqs;
        sawFreqs = Array.fill(5, {
			freq + Rand(100,1000)
        });
        Mix(Saw.ar(sawFreqs)) / 20;
    });

// pink noise added to the signal - not each saw!!
	sig = (sig + (Array.fill(size, { PinkNoise.ar }))/2);

// Each wave gets its own moving filter, envelope and modulation
    sig = sig.collect({ arg sig, x;
        var bpfreq = exprand(50.0, 16000) * tone;
        var bpfrq =
            0.1 *
            SinOsc.ar((x + 1) * (1/153) * speed)
            .exprange(0.1, 4) *  blur;
        sig = BPF.ar(sig, bpfreq, bpfrq) * 34;
        sig = BPF.ar(sig, bpfreq, bpfrq) * 4;
        sig = sig * EnvGen.ar( Env([0, 1, 0], [0.8, 0.8]),  trig[x] );
        sig = sig.fold2(
            LFNoise0.kr(
                (1/23) * (x + 1) * speed
            ).range(0.01, 8)
        ) * 4;
        sig = sig *
            SinOsc.ar(
                (1/800) * (x + 1) * speed
            ).range(0.01, 1);
    });
    // Slowly moving random stereo positions; combine all 20 voices
	//needs envlope that kind of pulses based on start of row/col
    sig = Pan2.ar(
        sig,
        (
            Array.fill(size, { rrand(-1.0, 1.0) }) *
            SinOsc.ar(
                (1/132) * (1..size) * speed
            ).range(0, 1)
        ),
        amp
    ).mean;
    sig = ~allpassWash.(sig, wet, level);
    ~auxSend.(sig, auxBusA, auxAmtA, auxBusB, auxAmtB);
    Out.ar(out, sig);
}).add;

// Rumble Carrier: \rumble's own 20-voice texture (identical
// sound-generating chain, copied verbatim, including its own unrelated
// per-voice envelope/texture shaping - EnvGen.ar(Env([0,1,0],[0.8,0.8]),
// trig[x]) stays untouched, that's part of the texture itself) wrapped in
// the same carrier role \noiseCarrier plays (see that SynthDef's own
// bullet, above, and ~buildFxPattern's own bullet, CT8tracks.scd, for the
// full two-synth/bus/Group design) - writes its raw, continuous signal to
// a private bus instead of hardware output; \fxPulse is what shapes it
// and actually makes it audible. Added for FXT1/FXT2 per feedback ("to
// hard to hear with noise... lets do it with rumble. add rumble to both
// FX tracks"), answering \rumble's own hand-written comment just above
// ("needs envlope that kind of pulses based on start of row/col").
SynthDef(\rumbleCarrier, {
    |out=0, freq=60, detune=0.5,
     speed=1.99, density=1, tone=0.25, blur=2, masterDur=2|
    var env = EnvGen.kr(Env([0, 1, 1, 0], [0.1, masterDur, 1], -4), doneAction: 2);
    var sig;
    var size = 20;
    var trig = Impulse.ar(
        Array.fill(size, { rrand(1.0, 15.0) }) * density
    );

    sig = Array.fill(size, {
        var sawFreqs;
        sawFreqs = Array.fill(5, {
            freq + Rand(100, 1000)
        });
        Mix(Saw.ar(sawFreqs)) / 20;
    });

    sig = (sig + (Array.fill(size, { PinkNoise.ar }))/2);

    sig = sig.collect({ arg sig, x;
        var bpfreq = exprand(50.0, 16000) * tone;
        var bpfrq =
            0.1 *
            SinOsc.ar((x + 1) * (1/153) * speed)
            .exprange(0.1, 4) *  blur;
        sig = BPF.ar(sig, bpfreq, bpfrq) * 34;
        sig = BPF.ar(sig, bpfreq, bpfrq) * 4;
        sig = sig * EnvGen.ar( Env([0, 1, 0], [0.8, 0.8]),  trig[x] );
        sig = sig.fold2(
            LFNoise0.kr(
                (1/23) * (x + 1) * speed
            ).range(0.01, 8)
        ) * 4;
        sig = sig *
            SinOsc.ar(
                (1/800) * (x + 1) * speed
            ).range(0.01, 1);
    });
    sig = Pan2.ar(
        sig,
        (
            Array.fill(size, { rrand(-1.0, 1.0) }) *
            SinOsc.ar(
                (1/132) * (1..size) * speed
            ).range(0, 1)
        ),
        1
    ).mean;
    Out.ar(out, sig * env);
}).add;

// Allpass reverb: a second, simpler reverb option alongside \ELIreverb - a
// straight dry/wet allpass-chain wash rather than \ELIreverb's comb+allpass
// design. Renamed from \labReverb (its name in the sound lab) since it's now
// a permanent, general-purpose synth here, not lab-specific.
SynthDef(\allpassReverb, { |in=0, out=0, wet=0.4, level=0.6|
    var dry = In.ar(in, 2);
    var fx = dry;
    10.do { fx = AllpassN.ar(fx, 0.05, [Rand(0, 0.05), Rand(0, 0.05)], 1) };
    Out.ar(out, XFade2.ar(dry, fx, wet.linlin(0, 1, -1, 1)) * level);
}).add;

};

// Hot reload: after startup, evaluating this whole file sends any edited
// SynthDefs to the already-running server.  Before startup, CT8main does it.
if(s.serverRunning and: { ~revBus.notNil }) {
    ~installSynthDefs.value;
};
"CT8 synth definitions loaded.".postln;
)
