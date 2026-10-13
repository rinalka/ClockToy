// ============================================================================
// CT8guiSynthLab.scd
// CLOCKTOY - SYNTH LAB WINDOW (standalone sound/parameter audition panel)
// ============================================================================
//
// Incorporated from the user's standalone Ct8synthLab.scd ("Endless Synth
// Sound Lab"). Original behavior preserved - pick an instrument, PLAY NOTE,
// move sliders (live ones apply to the currently-sounding note immediately;
// others take effect on the next note) - but restructured to fit this
// project's conventions so it can run as part of CT8main's startup instead
// of as its own standalone patch:
//   - Wrapped in ~makeSynthLabWindow, called from CT8main.scd alongside the
//     other ~makeXWindow functions, instead of auto-running in its own
//     s.waitForBoot/s.boot block - the server is already booted and running
//     by the time CT8main calls this, so it doesn't need to manage that
//     itself.
//   - The window is now ~synthLabWindow (was a local `window` var) and the
//     cleanup function is ~stopSynthLab (was ~endlessLabStop, and did less -
//     see below), matching how ~adjustWindow/~percGeneratorWindow are tracked and
//     closed on CmdPeriod (CT8main.scd's
//     ~closeWindowsOnCmdPeriod calls ~stopSynthLab too, so it frees this
//     window's private Groups/Bus as well as closing it, not just the
//     window itself).
//   - \drone/\lead/\seq/\noise/\kick/\droneChord/\allpassReverb were moved
//     into CT8synths.scd as permanent, general-purpose synths (their "lab"
//     name prefix dropped) since they're new additions, not already present
//     elsewhere. \plucking/\hat/\cym were NOT moved here as new synths -
//     this project already has those three; duplicating them under new
//     names would just be clutter. Instead this file keeps its own small,
//     already-adapted \labPlucking/\labHat/\labCym variants (bug-fixed
//     versions of the originals, replumbed to this lab's single `out`-per-
//     instrument bus convention rather than the real \plucking's two-output
//     dry+~revBus-send design) purely for standalone auditioning here. Any
//     param added to the real \hat/\cym later (e.g. \wet/\level, their own
//     tiny built-in ~allpassWash tail - see CT8synths.scd) has to be
//     hand-copied into \labHat/\labCym too, same as everything else about
//     this split.
//   - \fm needed the same treatment for a different reason: real \fm's only
//     reverb mechanism is a hardcoded `Out.ar(fx, car * fxsend.dbamp)` send,
//     and this lab's `trigger` never sets `\fx` for any synth - so playing
//     real \fm here directly would leak a quiet but real, unprocessed copy
//     of every note straight to hardware bus 0 (fx's default), bypassing
//     this lab's private reverb bus entirely. \labFm, below, drops
//     `fx`/`fxsend` and gets the same `\wet`/`\level`-driven `~allpassWash`
//     tail as every other \labX variant instead, so it's never a leak risk
//     and reverb here always means the same one thing. Real \fm keeps
//     `fx`/`fxsend` untouched - HT1/MT1/BT1 still depend on it to reach
//     ~clockRev.
//
// Each instrument outputs to this window's own private stereo reverb bus,
// entirely separate from the project's shared ~revBus/~clockRev - playing
// with sounds here never affects or gets mixed into the live clock
// composition.
//


(

~makeSynthLabWindow = {
    var specs, names, selected = \drone, values, controls, menu, panel;
    var revBus, sourceGroup, fxGroup, reverb, active = List.new;
// revWet defaults to 0 now (was 0.4), per feedback - every note played here
// routes through this private reverb Synth unconditionally (it's the ONLY
// path to output, not a parallel send - see `trigger`'s own \out arg,
// below), so a nonzero default here was colouring EVERY instrument's sound
// unconditionally, on top of whatever that instrument's own \wet/\level
// tail (if it has one) was separately set to - "that issue with the
// reverb" that made \droneChord (and anything else) not sound like its own
// true, dry self. Matches the project's universal wet=0/level=1 no-op
// convention everywhere else now; the Wet/dry and Output level sliders,
// below, still exist and still work live if you want to turn it back on.
    var status, rebuild, trigger, makeSlider, synthNames, currentSynth, currentInstrument, revWet = 0, revLevel = 1;
    var populateLiveOverrides;
// Loop: repeatedly retriggers the selected instrument so there's continuous
// sound to tune against - short/percussive synths (hat/cym/baseD/kick) free
// themselves almost instantly, too fast to hear a slider move while one
// note plays, unlike the sustained ones (drone/lead/droneChord).
    var loopButton, loopActive = false, loopInterval = 1, loopTick;
    var loopSpeedSlider, loopSpeedReadout;

// Free a previous lab instance's window/Groups/Bus (if this is a re-run)
// before creating new ones, so repeated hot-reloads don't leave duplicate
// reverbs/groups running.
    if(~stopSynthLab.notNil) { ~stopSynthLab.value };

// A couple of this project's synths adapted for the lab's single-`out`-per-
// instrument convention (see the file header for why these aren't the same
// \plucking/\hat/\cym already in CT8synths.scd).
    SynthDef(\labPlucking, { |out=0, amp=0.2, sAmp=0.5, freq=440,
        pluckDecay=0.35, coef=0.25, pan=0,
        atk=0.001, sus=0.015, rel=0.10, dynamic=0.25|
        var env, excitation, snd;
        env = EnvGen.kr(Env.linen(atk, sus, rel), doneAction: 2);
        excitation = BrownNoise.ar(amp) * EnvGen.kr(Env.perc(0.01, 0.008));
        snd = Pluck.ar(
            excitation, Impulse.kr(0), 0.5,
            freq.reciprocal.clip(0.0001, 0.5), pluckDecay, coef
        );
        snd = LeakDC.ar(snd).clip2;
        snd = Pan2.ar(snd, pan);
// dynamic controls this instrument's reverb-bus send in the lab - the
// shared wet/dry control determines how much reverb is actually heard.
        Out.ar(out, snd * env * sAmp * dynamic);
    }).add;

    SynthDef(\labHat, { |out=0, amp=0.2, pan=0, freq=4200, noiseFreq=1000, wet=0, level=1|
        var env, noise, metal, snd;
        env = Env.perc(0.001, 0.018).ar(Done.freeSelf);
        noise = HPF.ar(WhiteNoise.ar, noiseFreq);
        metal = Mix.ar(
            SinOsc.ar(freq * [1, 1.273809524, 1.690476190, 1.023809524])
        ) * 0.15;
        snd = (noise * 0.75) + metal;
        snd = HPF.ar(snd, 5000);
        snd = snd * env * amp;
        snd = Pan2.ar(snd, pan);
// Same tiny \wet/\level ~allpassWash tail as the real \hat (CT8synths.scd,
// defined there not here since it's a plain helper function, not a
// SynthDef - safe to call directly, unlike reusing a whole real SynthDef)
// - kept in sync by hand with the real one's own signal chain, like every
// other \labX/real pair in this file.
        snd = ~allpassWash.(snd, wet, level);
        Out.ar(out, snd);
    }).add;

    SynthDef(\labCym, { |out=0, basefreq=300, len=0.25, amp=1, pan=0, wet=0, level=1|
        var freqs, signal, pulseEnv;
        freqs = basefreq * [
            1, 1.4823959094229, 1.800048697346,
            2.545458972486, 2.6322863403944, 3.9552471390309
        ];
        pulseEnv = EnvGen.ar(Env([1.0, 0.6], [len], [-0.5]));
        signal = Mix.new(LFPulse.ar(freqs * 4.09));
        signal = (BinaryOpUGen('==', signal, 6.0) * 0.6)
            + (BinaryOpUGen('==', signal, 2.0) * 0.2)
            + (BinaryOpUGen('==', signal, 1.0) * 0.9);
        signal = (signal * pulseEnv)
            + (Mix.new(LFPulse.ar(freqs, width: 0.55)) * 0.9);
        signal = RLPF.ar(signal, 7000, 0.6);
        signal = RHPF.ar(signal, 6800, 1.5);
        signal = RHPF.ar(signal, 6800, 1.5);
        signal = RHPF.ar(signal, 1200, 1.5);
        signal = signal * EnvGen.ar(
            Env([0, 1, 0.4, 0, 0], [0.002, len, 0.05, 0.5], [0, -0.5, 0, -50]),
            doneAction: 2
        );
        signal = [signal, DelayN.ar(signal, 0.005, 0.005)];
        signal = Balance2.ar(signal[0], signal[1], pan) * (amp * 0.4);
// Same \wet/\level ~allpassWash tail as the real \cym - see \labHat above.
        signal = ~allpassWash.(signal, wet, level);
        Out.ar(out, signal);
    }).add;

// Same as real \fm (CT8synths.scd) except \fx/\fxsend (its external send to
// ~clockRev - meaningless here, see this file's header) are dropped in
// favor of \wet/\level - ~allpassWash (CT8synths.scd), matching every other
// \labX variant's own tail (real \fm has never used FreeVerb anywhere -
// this lab-only variant briefly did, by mistake, now fixed). Keep in sync
// by hand with real \fm's own freq/mRatio/cRatio/index/iScale/cAtk/cRel/
// amp/atk/rel/pan if those ever change.
    SynthDef(\labFm, { |freq=500, mRatio=1, cRatio=1, index=1, iScale=5,
        cAtk=4, cRel=(-4), amp=0.2, atk=0.01, rel=3, pan=0, out=0, wet=0, level=1|
        var car, mod, env, iEnv;
        iEnv = EnvGen.kr(Env([index, index * iScale, index], [atk, rel], [cAtk, cRel]));
        env = EnvGen.kr(Env.perc(atk, rel, curve: [cAtk, cRel]), doneAction: 2);
        mod = SinOsc.ar(freq * mRatio, mul: freq * mRatio * iEnv);
        car = SinOsc.ar(freq * cRatio + mod) * env * amp;
        car = Pan2.ar(car, pan);
        car = ~allpassWash.(car, wet, level);
        Out.ar(out, car);
    }).add;

    specs = IdentityDictionary.new;
    specs.put(\drone, [
            [\freq, 110, 30, 1000, \exp], [\dur, 5, 0.2, 20, \lin],
            [\amp, 0.4, 0, 1, \lin], [\pan, 0, -1, 1, \lin],
            [\width, 0.025, 0, 0.2, \lin],
            [\filterRatio, 2, 0.5, 8, \exp]
    ]);
// freq is MIDI now, not Hz (CT8synths.scd's own \lead/\seq bullets - the
// \midi curve means something once the SynthDef itself converts via
// .midicps internally, unlike \droneChord's note1-4 which were already
// MIDI-valued with nothing to change here). Range 30-99, not the full
// 0-127, matching the SynthDef's own internal freq.clip(30, 99) - per
// feedback ("lead needs to limit freq to never go below 30 or above 99"),
// so this slider can't produce an out-of-range value in the first place.
// rel is a real control arg now (CT8synths.scd's own \lead bullet), not a
// hardcoded local var - per feedback ("added a release variable rel to
// lead, can you please see it gets into synthlab").
    specs.put(\lead, [
            [\freq, 69, 30, 99, \midi], [\dur, 2, 0.6, 12, \lin],
            [\amp, 0.7, 0, 1, \lin], [\pan, 0, -1, 1, \lin],
            [\wobblelow, 0.3, 0, 1, \lin], [\wobblehigh, 1, 0, 1, \lin],
            [\rel, 2, 0.01, 20, \exp]
    ]);
    specs.put(\seq, [
            [\freq, 76, 0, 127, \midi], [\dur, 0.5, 0.1, 3, \lin],
            [\amp, 0.25, 0, 1, \lin], [\pan, 0, -1, 1, \lin],
            [\glissdir, 1, -1, 1, \lin], [\gliss, 0.1, 0, 0.7, \lin]
    ]);
    specs.put(\noise, [
            [\dur, 5, 0.2, 20, \lin], [\amp, 0.15, 0, 0.7, \lin],
            [\pan, 0, -1, 1, \lin]
    ]);
// detune has no audible effect yet - declared on the SynthDef but never
// read in its body (CT8synths.scd's own bullet flags this rather than
// guessing how it should wire in); exposed here anyway since every other
// param is, per feedback ("add it to synthlab").
    specs.put(\rumble, [
            [\freq, 60, 20, 500, \exp],
            [\detune, 0.5, 0, 2, \lin],
            [\pan, 0, -1, 1, \lin],
            [\amp, 0.1, 0, 1, \lin],
            [\speed, 1.99, 0.1, 5, \exp],
            [\density, 1, 0.1, 5, \exp],
            [\tone, 0.25, 0, 2, \lin],
            [\blur, 2, 0, 10, \lin],
            [\wet, 0, 0, 1, \lin],
            [\level, 1, 0, 1, \lin]
    ]);
    specs.put(\kick, [
            [\amp, 0.5, 0, 1, \lin], [\pan, 0, -1, 1, \lin],
            [\curve, -4, -12, 0, \lin],
            [\drumAmp, 1, 0, 2, \lin], [\beaterAmp, 0.02, 0, 0.5, \lin],
            [\drumFreq, 50, 25, 200, \exp], [\drumHarmonic, 2, 1, 8, \lin],
            [\drumSweep, 0.02, 0.001, 0.3, \exp],
            [\drumAtt, 0.005, 0.001, 0.1, \exp],
            [\drumRel, 0.4, 0.05, 3, \lin],
            [\drumFilter, 1000, 100, 12000, \exp],
            [\modIndex, 6.5, 0, 20, \lin], [\modFreq, 5, 0.5, 200, \exp],
            [\beaterFreq, 500, 100, 6000, \exp],
            [\beaterHarmonic, 12, 1, 20, \lin],
            [\beaterSweep, 0.03, 0.001, 0.3, \exp],
            [\beaterAtt, 0.01, 0.001, 0.1, \exp],
            [\beaterRel, 0.3, 0.02, 2, \lin],
            [\wet, 0, 0, 1, \lin],
            [\level, 1, 0, 1, \lin]
    ]);
    specs.put(\plucking, [
            [\freq, 440, 50, 2000, \exp],
            [\amp, 0.2, 0, 1, \lin], [\sAmp, 0.5, 0, 1, \lin],
            [\pluckDecay, 0.35, 0.05, 8, \exp],
            [\coef, 0.25, -0.99, 0.99, \lin],
            [\pan, 0, -1, 1, \lin],
            [\atk, 0.001, 0.001, 0.1, \exp],
            [\sus, 0.015, 0.005, 2, \exp],
            [\rel, 0.10, 0.01, 8, \exp],
            [\dynamic, 0.25, 0, 1, \lin]
    ]);
    specs.put(\hat, [
            [\amp, 0.2, 0, 1, \lin], [\pan, 0, -1, 1, \lin],
            [\freq, 4200, 300, 12000, \exp],
            [\noiseFreq, 1000, 100, 12000, \exp],
            [\wet, 0, 0, 1, \lin],
            [\level, 1, 0, 1, \lin]
    ]);
    specs.put(\cym, [
            [\basefreq, 300, 60, 2000, \exp],
            [\len, 0.25, 0.03, 4, \exp],
            [\amp, 1, 0, 2, \lin],
            [\pan, 0, -1, 1, \lin],
            [\wet, 0, 0, 1, \lin],
            [\level, 1, 0, 1, \lin]
    ]);
    specs.put(\baseD, [
            [\basefreq, 55, 20, 2000, \exp],
            [\amp, 1, 0, 4, \lin],
            [\rq, 0.1, 0.01, 2, \exp],
            [\overdrive, 2, 1, 20, \exp],
            [\samplen, 100, 10, 500, \lin],
            [\pan, 0, -1, 1, \lin],
            [\wet, 0, 0, 1, \lin],
            [\level, 1, 0, 1, \lin]
    ]);
// Range chosen wide enough to cover every real-track preset already in the
// project (HT1/MT1/BT1's current values, and old PT3's now-retired
// index=100/cRatio=45.9 snare patch) - not just this SynthDef's own
// defaults - since the point of tuning here is finding values to carry
// into CT8tracks.scd by hand (see CLAUDE.md's \mix bullet for the general
// Lab-to-real workflow).
    specs.put(\fm, [
            [\freq, 500, 20, 2000, \exp],
            [\mRatio, 1, 0.1, 20, \exp],
            [\cRatio, 1, 0.1, 20, \exp],
            [\index, 1, 0.01, 150, \exp],
            [\iScale, 5, 0, 10, \lin],
            [\cAtk, 4, -20, 20, \lin],
            [\cRel, -4, -20, 20, \lin],
            [\amp, 0.2, 0, 2, \lin],
            [\atk, 0.01, 0.001, 2, \exp],
            [\rel, 3, 0.01, 10, \exp],
            [\pan, 0, -1, 1, \lin],
            [\wet, 0, 0, 1, \lin],
            [\level, 1, 0, 1, \lin]
    ]);
// Defaults match the real SynthDef's own (CT8synths.scd), per feedback -
// amp/attack/sustain/release used to lag behind a tuning pass there (was
// 0.2/5/30/10 here vs. the real synth's own values), so auditioning here
// started from a different sound than the live composition actually
// makes. amp doubled twice now (0.2 -> 0.4 -> 0.8, still "too low" after
// the first) - its own upper bound raised to 2 this time (was 0/1) to
// leave real headroom above the new default rather than needing a third
// round. \wet/\level were missing here entirely, even though the real
// SynthDef has had that tail since this same tuning pass - added to
// match every other instrument's own spec entry. `detune` changed meaning
// entirely in a later hand-edit - used to be a 0-1 normalized spread
// (1 = in tune, 0 = up to +/-1 semitone), now a plain +/- cents amount
// (default 10, so +/-10 cents of static per-oscillator detune) - range
// updated to match. `driftRate`/`driftDepth` are new in that same edit (a
// slow LFNoise2 wobble layered on top of the static detune, in Hz and
// cents respectively) and were missing here entirely until now.
    specs.put(\droneChord, [
            [\note1, 48, 0, 127, \midi],
            [\note2, 52, 0, 127, \midi],
            [\note3, 55, 0, 127, \midi],
            [\note4, 60, 0, 127, \midi],
            [\amp, 1.5, 0, 2, \lin],
            [\attack, 0.012, 0.01, 60, \exp],
            [\sustain, 0.12, 0.1, 300, \exp],
            [\release, 5, 0.01, 120, \exp],
            [\detune, 10, 0, 100, \lin],
            [\driftRate, 0.15, 0.01, 5, \exp],
            [\driftDepth, 5, 0, 50, \lin],
            [\wet, 0, 0, 1, \lin],
// level's own default is 2 now (was 1), from the same hand-edit as
// detune/driftRate/driftDepth above - upper bound raised to 3 so the
// slider can actually reach and go past the real current default,
// rather than topping out below it.
            [\level, 2, 0, 3, \lin]
    ]);
// note1-5 are \midi-curve (see makeSlider's own comment, above) for the
// same reason as \droneChord's own note1-4 - a dragged slider should land
// on a clean MIDI note, not a fractional/out-of-tune one.
    specs.put(\shimmerPad, [
            [\note1, 60, 0, 127, \midi],
            [\note2, 63, 0, 127, \midi],
            [\note3, 67, 0, 127, \midi],
            [\note4, 71, 0, 127, \midi],
            [\note5, 72, 0, 127, \midi],
// amp halved per feedback (0.25 -> 0.125).
            [\amp, 0.125, 0, 1, \lin],
// atk/sus/rel used to be hardcoded local vars inside the SynthDef; now real
// control args (CT8synths.scd) so HT1/HT2's own per-chord envelope
// calculation (~buildPolyPattern, CT8tracks.scd) can drive them - these
// three are excluded from this lab's own live-override tracking for
// exactly that reason (see populateLiveOverrides' own comment, above), so
// sliding them here only affects standalone auditioning, same as before.
            [\atk, 2.0, 0.01, 10, \exp],
            [\sus, 1.0, 0.01, 10, \exp],
            [\rel, 5.0, 0.01, 20, \exp],
            [\wet, 0, 0, 1, \lin],
            [\level, 1, 0, 1, \lin]
    ]);
    names = [\drone, \lead, \seq, \noise, \rumble, \kick, \plucking, \hat, \cym, \baseD, \fm, \droneChord, \shimmerPad];

// Maps each entry in `names` to the SynthDef that actually plays it -
// \drone/\lead/\seq/\noise/\rumble/\kick/\droneChord/\baseD are the shared
// synths now in CT8synths.scd (\baseD/\rumble already use a single `out`
// arg with no hardcoded extra reverb-send line, so they're directly
// compatible with this lab's bus convention - no \labBaseD/\labRumble
// variant needed); \plucking/\hat/\cym/
// \fm point to this file's own \labX variants (see the file header for why -
// \fm's is about its fx/fxsend send leaking to hardware output, not a bus-
// convention mismatch like the other three).
    synthNames = IdentityDictionary.new;
    synthNames.put(\drone, \drone);
    synthNames.put(\lead, \lead);
    synthNames.put(\seq, \seq);
    synthNames.put(\noise, \noise);
    synthNames.put(\rumble, \rumble);
    synthNames.put(\kick, \kick);
    synthNames.put(\fm, \labFm);
    synthNames.put(\plucking, \labPlucking);
    synthNames.put(\hat, \labHat);
    synthNames.put(\cym, \labCym);
    synthNames.put(\baseD, \baseD);
    synthNames.put(\droneChord, \droneChord);
    synthNames.put(\shimmerPad, \shimmerPad);
    values = IdentityDictionary.new;
    names.do { |name|
        var d = IdentityDictionary.new;
        specs[name].do { |sp| d[sp[0]] = sp[1] };
        values[name] = d;
    };

    revBus = Bus.audio(s, 2);
    sourceGroup = Group.head(s);
    fxGroup = Group.after(sourceGroup);
    reverb = Synth.head(fxGroup, \allpassReverb,
        [\in, revBus.index, \out, 0, \wet, revWet, \level, revLevel]);

// Full cleanup: close the window (if still open) and free this instance's
// private Groups/Bus. Reassigned here (rather than just once outside this
// function) so it always closes over THIS invocation's actual objects -
// matters because the guard at the top of this function calls whatever the
// PREVIOUS invocation last assigned here.
    ~stopSynthLab = {
        loopActive = false;
        if(~synthLabWindow.notNil) { ~synthLabWindow.onClose = nil; ~synthLabWindow.close };
        if(sourceGroup.notNil) { sourceGroup.free };
        if(fxGroup.notNil) { fxGroup.free };
        if(revBus.notNil) { revBus.free };
        ~synthLabWindow = nil;
        ~stopSynthLab = nil;
    };

    ~synthLabWindow = Window("Endless Synth - Sound Lab v8", Rect(180, 90, 660, 790));
    ~synthLabWindow.alwaysOnTop_(true);
    ~synthLabWindow.view.background = Color(0.13, 0.14, 0.16);
    ~synthLabWindow.view.decorator = FlowLayout(~synthLabWindow.view.bounds, 14@12, 8@8);

    StaticText(~synthLabWindow, 620@30).string_("ENDLESS SYNTH / SOUND LAB")
        .font_(Font("Arial", 19, true)).stringColor_(Color.white);
    StaticText(~synthLabWindow, 620@22).string_("Choose a synth, PLAY NOTE, then move sliders (or set up the next note)")
        .stringColor_(Color(0.8, 0.8, 0.8));

    menu = PopUpMenu(~synthLabWindow, 220@28).items_(names.collect(_.asString))
        .background_(Color.white);
    Button(~synthLabWindow, 120@28).states_([["PLAY NOTE", Color.black, Color(0.65, 0.85, 0.65)]])
        .action_({ trigger.value });
    Button(~synthLabWindow, 120@28).states_([["STOP NOTES", Color.white, Color(0.5, 0.24, 0.24)]])
        .action_({
            sourceGroup.freeAll; active.clear; currentSynth = nil; currentInstrument = nil;
            loopActive = false; loopButton.value = 0;
        });

// Loop: re-fires `trigger` every `loopInterval` seconds while active, so a
// short/percussive note (hat/cym/baseD/kick) keeps sounding instead of
// dying before a slider move can be heard against it. Self-reschedules by
// returning loopInterval from the AppClock-scheduled function (same
// keep-going/return-nil-to-stop idiom as ~checkForNewMinute/~tempoChange in
// CT8guiClock.scd/CT8tracks.scd) and stops itself - rather than relying on
// whoever flips loopActive off to also cancel a pending schedule - the
// instant loopActive goes false, including when the lab itself tears down
// (~stopSynthLab, above).
    loopTick = {
        if(loopActive) { trigger.value };
        if(loopActive) { loopInterval } { nil };
    };
    loopButton = Button(~synthLabWindow, 110@28).states_([
        ["LOOP: OFF", Color.white, Color(0.3, 0.3, 0.3)],
        ["LOOP: ON", Color.black, Color(0.65, 0.85, 0.65)]
    ]).action_({ |b|
        loopActive = (b.value == 1);
        if(loopActive) { AppClock.sched(0, loopTick) };
    });
// Speed, not interval: dragging right makes the loop faster (shorter
// loopInterval), same left-slow/right-fast feel as any other speed
// control, via an exponential mapping over the same 0.05-10 second range
// the old plain NumberBox clipped to (slider 0 -> 10s/slow, slider 1 ->
// 0.05s/fast - inverted from a plain \exp curve, which would run the
// other way). loopSpeedReadout mirrors the actual interval as text, same
// reason every other Slider in this file pairs with one.
    StaticText(~synthLabWindow, 85@28).string_("Loop speed")
        .stringColor_(Color.white);
    loopSpeedSlider = Slider(~synthLabWindow, 80@28)
        .value_((loopInterval / 10).log / (0.05 / 10).log)
        .action_({ |sl|
            loopInterval = 10 * ((0.05 / 10) ** sl.value);
            loopSpeedReadout.string_(loopInterval.round(0.01).asString);
        });
    loopSpeedReadout = StaticText(~synthLabWindow, 45@28)
        .string_(loopInterval.round(0.01).asString).stringColor_(Color.white);

    status = StaticText(~synthLabWindow, 620@22).string_("Ready")
        .stringColor_(Color(0.7, 0.85, 0.75));
    StaticText(~synthLabWindow, 620@24).string_("REVERB (applies to every instrument)")
        .font_(Font("Arial", 13, true)).stringColor_(Color.white);

// Generic labelled slider with live numerical readout. curve == \midi is a
// third option alongside \lin/\exp, per feedback ("change the sliders for
// note 1 to 4 to be in midi") - positions the slider exactly like \lin
// (same toNorm), but rounds every value that comes out of a drag or a
// typed number to the nearest integer, and shows 0 decimals instead of 3 -
// a dragged note1-4 slider used to land on fractional MIDI values (e.g.
// 48.237), which is a real, just slightly-out-of-tune, pitch once
// .midicps'd, not a clean semitone the way picking a note should be.
// isLive (default false, so the Reverb sliders' own two calls below don't
// need updating) - per feedback ("set the text color to red... for any
// controls that are being controlled by clocktoy when it is running"):
// red instead of white for this label when true, i.e. whenever this
// param is one of the ones ~labLiveOverrides is currently pushing into
// the live composition (rebuild's own call, below, is what decides
// that per param).
    makeSlider = { |parent, label, val, min, max, curve, callback, isLive = false|
        var row = CompositeView(parent, 600@29);
        var lbl = StaticText(row, Rect(0, 2, 145, 23)).string_(label.asString)
            .stringColor_(if(isLive) { Color.red } { Color.white });
        var slider = Slider(row, Rect(150, 3, 325, 21));
        var number = NumberBox(row, Rect(485, 2, 100, 24));
        var isMidi = (curve == \midi);
        var toVal = { |x|
            var v = if(curve == \exp) {
                min * ((max/min) ** x)
            } { min + (x * (max-min)) };
            if(isMidi) { v.round } { v };
        };
        var toNorm = { |x| if(curve == \exp) {
            (x/min).log / (max/min).log
        } { (x-min)/(max-min) } };
        number.value = val;
        number.decimals = if(isMidi) { 0 } { 3 };
        slider.value = toNorm.value(val).clip(0, 1);
        slider.action = {
            var v = toVal.value(slider.value);
            number.value = v;
            callback.value(v);
        };
        number.action = {
            var v = number.value.clip(min, max);
            if(isMidi) { v = v.round };
            slider.value = toNorm.value(v);
            number.value = v;
            callback.value(v);
        };
        row;
    };

    makeSlider.value(~synthLabWindow, "Wet / dry", revWet, 0, 1, \lin,
        { |v| revWet = v; reverb.set(\wet, v) });
    makeSlider.value(~synthLabWindow, "Output level", revLevel, 0, 1, \lin,
        { |v| revLevel = v; reverb.set(\level, v) });

    StaticText(~synthLabWindow, 620@24).string_("INSTRUMENT PARAMETERS")
        .font_(Font("Arial", 13, true)).stringColor_(Color.white);
    panel = ScrollView(~synthLabWindow, 620@480);
    panel.background = Color(0.19, 0.20, 0.22);
    panel.hasVerticalScroller = true;
    controls = CompositeView(panel, Rect(0, 0, 605, 475));

    rebuild = {
        var fields = specs[selected];
        controls.children.do { |child| child.remove };
        controls.bounds = Rect(0, 0, 605, (fields.size * 34 + 15).max(475));
        controls.decorator = FlowLayout(controls.bounds, 4@5, 4@5);
        fields.do { |sp|
            var isLive = ~labLiveOverrides[selected].notNil and: { ~labLiveOverrides[selected][sp[0]].notNil };
            makeSlider.value(controls, sp[0], values[selected][sp[0]],
                sp[2], sp[3], sp[4], { |v|
                    values[selected][sp[0]] = v;
// Update the most recently played note if it is still sounding. Envelope
// segment durations and the initial pluck excitation cannot be
// retroactively changed; other controls are live.
                    if(currentSynth.notNil and: { currentInstrument == selected } and: { currentSynth.isPlaying }) {
                        currentSynth.set(sp[0], v);
                    };
// Per feedback ("connect the lab to the running synths"): also push into
// ~labLiveOverrides (CT8tracks.scd's own SYNTH LAB LIVE OVERRIDES
// section) if this exact param is one of the ones currently being
// tracked for this instrument - menu.action, below, is what decides
// that set (never \wet/\level/\noteN - see its own comment). This is
// what actually makes a live track, if one is currently playing this
// instrument, audibly follow this slider.
                    if(~labLiveOverrides[selected].notNil and: { ~labLiveOverrides[selected][sp[0]].notNil }) {
                        ~labLiveOverrides[selected][sp[0]] = v;
                    };
                }, isLive);
        };
    };
    trigger = {
        var args = [\out, revBus.index];
        var note;
        specs[selected].do { |sp| args = args.add(sp[0]).add(values[selected][sp[0]]) };
        note = Synth.head(sourceGroup, synthNames[selected], args);
        note.register;  // NodeWatcher receives /n_end when this note finishes.
        currentSynth = note;
        currentInstrument = selected;
        active.add(note);
        note.onFree({
// An older note must not clear a newer note's controls.
            {
                active.remove(note);
                if(currentSynth === note) {
                    currentSynth = nil;
                    currentInstrument = nil;
                };
            }.defer;
        });
        status.string = "Played " ++ selected.asString;
    };
// Per feedback ("I need a way to tune the presets so lets connect the
// lab to the running synths... I will only run one track with that
// synth in it, will tune it using synthLab, and will record what i
// consider to be reasonable values for a preset"): populate
// ~labLiveOverrides fresh for whichever instrument is now selected,
// clearing every OTHER instrument's own entry at the same time, since
// the intended workflow is tuning ONE instrument's one live track at a
// time, not several at once. Excludes \wet/\level (already their own
// separate, per-track live control - CT8guiPercGenerator.scd/
// CT8guiHarmonyMelodyGenerator.scd's own Mix/Vol sliders) and any
// \noteN key (pitch is its own separate, chord-aware mechanism this
// isn't meant to second-guess) - every other param in this instrument's
// own specs table gets tracked. Shared by menu.action AND the initial
// build at the bottom, below, so the default-selected instrument
// (\drone) gets the exact same treatment as one picked by hand - called
// BEFORE rebuild.value either time, not after, since rebuild's own
// isLive check (per feedback, "set the text color to red... for any
// controls that are being controlled by clocktoy") needs this already
// populated for the CURRENT instrument, or every slider's colour would
// still reflect whichever instrument was selected before (or nothing,
// on the very first build).
    populateLiveOverrides = {
        ~labLiveOverrides = ();
        ~labLiveOverrides[selected] = ();
        specs[selected].do { |sp|
            var key = sp[0];
            var isExcluded = #[\wet, \level].includes(key) or: {
                key.asString.beginsWith("note")
            } or: {
// droneChord/shimmerPad's own attack/sustain/release (or atk/sus/rel) are
// now computed fresh per chord by ~buildPolyPattern (HT1/HT2,
// CT8tracks.scd - "the big change," per feedback) from the beats-until-
// next-chord math, same reasoning as the \wet/\level/noteN exclusions
// above: these already have their own separate live control, so this
// lab's own sliders shouldn't fight it for whichever of HT1/HT2 is
// currently using this instrument.
                #[\droneChord, \shimmerPad].includes(selected) and: {
                    #[\attack, \sustain, \release, \atk, \sus, \rel].includes(key)
                }
            };
            if(isExcluded.not) {
                ~labLiveOverrides[selected][key] = values[selected][key];
            };
        };
    };
    menu.action = {
        selected = names.at(menu.value.asInteger);
        populateLiveOverrides.value;
        rebuild.value;
        status.string = "Tuning " ++ selected.asString ++ " live - "
            ++ ~labLiveOverrides[selected].size ++ " param(s) pushed to the running composition.";
    };
    populateLiveOverrides.value;
    rebuild.value;

    ~synthLabWindow.onClose = { ~stopSynthLab.value };
    ~synthLabWindow.front;
};

"ClockToy synth-lab-window GUI functions loaded.".postln;

)
