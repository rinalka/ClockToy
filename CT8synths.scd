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
// SYNTHDEFS
// Keep SynthDef creation in a function.  CT8main calls this only after the
// server has booted and ~revBus exists.  Evaluating this file again while the
// project is running also installs edited SynthDefs immediately.
~installSynthDefs = {

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
        dynamic = 0.25;


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
    Out.ar(out, ~allpassWash.(snd * env, wet, level));
}).add;

// ---------------------------------------------------------------------------
// HAT - short metallic cymbal tick
// ---------------------------------------------------------------------------
SynthDef(\hat, {
    |amp = 0.2, pan = 0, out = 0, freq = 4200, noiseFreq = 1000, wet = 0, level = 1|

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

    Out.ar(out, snd);
}).add;

//Synth(\hat, [ \amp, 1.9,\freq, 200, \noiseFreq, 1000]);

// ---------------------------------------------------------------------------
// CYMBAL - classic 6-square-wave metallic cymbal (808/909-style technique)
// ---------------------------------------------------------------------------
SynthDef(\cym, {|t_trig = 1, out=0, basefreq = 300, len = 0.25, amp=1, pan = 0, wet = 0, level = 1|

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
	Out.ar(out, signal);
}).add;
//Synth(\cym, [\basefreq, 1500, \len, 1]);


// ---------------------------------------------------------------------------
// bass drum better
// ---------------------------------------------------------------------------
SynthDef(\baseD, {|t_trig = 1, basefreq = 55, rq = 0.1, overdrive = 2, samplen = 100, amp = 1, pan = 0, out = 0, wet = 0, level = 1|
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
		out=0, fx=0, fxsend=(-25), wet=0, level=1;
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
SynthDef(\lead, { |out=0, freq=440, dur=2, amp=0.7, pan=0,
    wobblelow=0.3, wobblehigh=1|
    var atk = 0.5;
    var env = EnvGen.kr(Env([0, 1, 1, 0], [atk, (dur-atk).max(0.01), 10]), doneAction: 2);
    var freqenv = EnvGen.kr(Env([0.7, 1, 1], [0.3, dur]));
    var sharpness = freq.cpsmidi.linlin(0, 127, 1, 15);
    var wobble = SinOsc.kr(6).range(wobblelow, wobblehigh);
    var sig = RLPF.ar(
        LFSaw.ar(freqenv * freq * LFNoise1.kr(1).range(0.995, 1.005)),
        freq * sharpness, LFNoise1.kr(3).range(0.2, 0.5), wobble
    );
    10.do { sig = AllpassN.ar(sig, 0.05, [Rand(0, 0.05), Rand(0, 0.05)], 1) };
    Out.ar(out, amp * env * Pan2.ar(sig / 10, pan));
}).add;

// Seq: pulse wave through a swept lowpass, with an optional pitch glide at
// the start of each note - a short plucky sequencer voice.
SynthDef(\seq, { |out=0, freq=660, dur=0.5, amp=0.25, pan=0,
    glissdir=1, gliss=0.1|
    var laggliss = Lag.kr(gliss, 0.1);
    var env = EnvGen.kr(Env.perc(0.01, 2), doneAction: 2);
    var freqenv = EnvGen.kr(Env([
        1 + (glissdir * laggliss), 1 - (glissdir * laggliss), 1, 1
    ], [0.07, 0.07, 1]));
    var filtenv = EnvGen.kr(Env([0.5, 1, 1], [0.15, dur]));
    var sig = LPF.ar(Pulse.ar(freqenv * freq), freq * filtenv * 3);
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
    beaterAtt=0.01, beaterRel=0.3, wet=0, level=1|
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
     amp=0.8,
     attack=0.012, sustain=0.12, release=5,
     detune=10,
     driftRate=0.15, driftDepth=5,
     wet=0, level=2|

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
    env = EnvGen.kr(
        Env.linen(attack, sustain, release, 1, \sine),
        doneAction: 2
    );
    sig = sig * env * amp;
    sig = ~allpassWash.(sig, wet, level);
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
SynthDef(\shimmerPad, { |out=0, amp=0.25,
    note1=60, note2=63, note3=67, note4=71, note5=72,
    wet=0, level=1|
    var sig, freqs, envs, env, rings, numvoices, notes;
    var atk=2.0, sus=1.0, rel=5.0, totalTime;

    numvoices = 5;
    notes = [note1, note2, note3, note4, note5];
    totalTime = atk + sus + rel;
    freqs = notes.collect(_.midicps) + Array.fill(numvoices, { Rand(-1.5, 1.5) });
    rings = Array.fill(numvoices, { ExpRand(totalTime * 0.6, totalTime) });
    envs = Array.fill(numvoices, { LFNoise2.kr(ExpRand(0.8, 3.5)).range(0.05, 1.0) });
    sig = PinkNoise.ar(numvoices.reciprocal ! 2);
    sig = DynKlank.ar(`[freqs, envs, rings], sig);
    env = EnvGen.kr(Env.new([0, 1, 1, 0], [atk, sus, rel], [\sin, \lin, -4]), doneAction: 2);
    sig = sig * env * amp;
    sig = ~allpassWash.(sig, wet, level);
    Out.ar(out, sig);
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
