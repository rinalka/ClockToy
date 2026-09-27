// ============================================================================
// CT8guiReverb.scd
// CLOCKTOY - REVERB CONTROLS WINDOW (CT8)
// ============================================================================
//
// Live control over the persistent reverb processor (~clockRev, running
// \ELIreverb - see CT8synths.scd). Unlike the Synth Controls window's
// per-note synth knobs (read fresh via Pfunc on every trigger), ~clockRev is
// one long-running Synth instance, so these controls call .set directly on
// it, as well as updating ~reverbDec/~reverbLpf/~reverbMix so the value is
// remembered the next time ~clockRev gets (re)created
// (~setStartPbinds, CT8tracks.scd).
//
// Requires ~makeSynthWindow to have already run (this window positions
// itself below it).
//


(

~makeReverbWindow = {
    var decBox, lpfBox, mixBox;
    var reverbWidth = 300;
    var reverbHeight = 90;
    var gap = 10;
// Stack below the Synth Controls window, sharing its left edge.
    var reverbBounds = Rect(
        ~synthWindow.bounds.left,
        ~synthWindow.bounds.top + ~synthWindow.bounds.height + gap,
        reverbWidth,
        reverbHeight
    );

    if(~reverbWindow.notNil) { ~reverbWindow.close };

    ~reverbWindow = Window("Reverb Controls", reverbBounds, resizable: false, border: true)
        .front
        .alwaysOnTop_(true);
    ~reverbWindow.view.decorator = FlowLayout(~reverbWindow.view.bounds, 12@12, 8@8);

    StaticText(~reverbWindow, 34@24).string_("Dec");
    decBox = NumberBox(~reverbWindow, 60@24)
        .value_(~reverbDec)
        .clipLo_(0.1).clipHi_(20).step_(0.1)
        .action_({ |box|
            ~reverbDec = box.value.clip(0.1, 20);
            if(~clockRev.notNil) { ~clockRev.set(\dec, ~reverbDec) };
        });

    StaticText(~reverbWindow, 34@24).string_("LPF");
    lpfBox = NumberBox(~reverbWindow, 60@24)
        .value_(~reverbLpf)
        .clipLo_(200).clipHi_(15000).step_(50)
        .action_({ |box|
            ~reverbLpf = box.value.clip(200, 15000);
            if(~clockRev.notNil) { ~clockRev.set(\lpf, ~reverbLpf) };
        });

    StaticText(~reverbWindow, 34@24).string_("Mix");
    mixBox = NumberBox(~reverbWindow, 60@24)
        .value_(~reverbMix)
        .clipLo_(0).clipHi_(1).step_(0.01)
        .action_({ |box|
            ~reverbMix = box.value.clip(0, 1);
            if(~clockRev.notNil) { ~clockRev.set(\mix, ~reverbMix) };
        });
};

"ClockToy reverb-control-window GUI functions loaded.".postln;

)
