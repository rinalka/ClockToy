// ============================================================================
// CT8guiPercGenerator.scd
// CLOCKTOY - PERCUSSION + BASS GENERATOR WINDOW (PT1-PT4, BT1-BT2)
// ============================================================================
//
// Live control over how all four percussion tracks (PT1/PT2/PT3/PT4) and
// both bass tracks (BT1/BT2) get generated (~buildPercPattern/
// ~buildBassTrackPattern, CT8tracks.scd) - on/off, source scan, instrument,
// which beats sound, and how pitch/volume vary, independently per track.
// Formerly CT8guiPT1Generator.scd/PT1-only; generalized to cover all four
// percussion tracks once ~buildRowPattern (PT1)/~buildColumnPattern (PT2's
// old two-synth-role system)/~buildSnarePattern (PT3's old hand-tuned
// ~snareTemplate) were all replaced by the single parameterized
// ~buildPercPattern, then extended again to add BT1/BT2 at the bottom,
// replacing BT1's old bespoke bar builder and giving BT2 a real one for the
// first time - same per-track-block convention, just a second, shorter list
// of per-track globals (~bassX rather than ~percX) and a smaller instrument/
// pattern/pitch-mode menu, since bass's two instruments (\fm/\plucking)
// aren't percussion's four. The window itself is dark-themed to match
// CT8guiSynthLab.scd, but each track's own block sits on a randomly-rolled
// muted background color (Color.rand(0.7), re-rolled fresh every time this
// window is built - same convention CT8fakeData.scd uses for its Actions
// plotter panel), purely to tell the blocks apart at a glance - label text
// inside each block is black, not white, for contrast against it.
//
// Each track's on/off button (red/green, same convention as the old
// CT8guiAdjust.scd per-track buttons it replaces for PT1-4/BT1-2) sits right
// next to that track's name, rather than in the separate Clock Toy Adjust
// window - PT1-4/BT1-2 are the only tracks controlled from here, so their
// on/off belongs here too, beside everything else about them.
//
// PERCUSSION (PT1-PT4) choices (all read live by ~buildPercPattern, so this
// file owns no generation logic itself, only the per-track globals
// CT8tracks.scd already reads - see PERCUSSION GENERATOR CONFIG in that
// file):
//   Source     - Row scan (~rowPattern/~clockEvents) or Column scan
//                (~colPattern/~columnEvents).
//   Instrument - \baseD, \cym, \hat, or \kick.
//   Wet/Level  - that instrument's own tiny built-in reverb tail (both
//                0-1, ~allpassWash's own dry/wet crossfade and
//                output-level knobs - see CT8synths.scd's \hat \wet/\level
//                comment), separate from the shared ~clockRev send every
//                other track uses. Unlike every other control below, these
//                take effect immediately, live - both read fresh via Pfunc
//                rather than baked into a pre-resolved array, so no
//                rebuild or Apply now click is needed.
//   Pattern    - one flat list (no menu-within-a-menu - see this file's
//                history for why that didn't work out): First beat only /
//                Every beat / Start of Row (or Col, the third item's label
//                tracks whichever Source is currently selected) / Random
//                1/8th % / Random 1/8th (last of bar) / Random 1/8th (last
//                of row/col) / Random 1/3 % / Random 1/3 (last of bar) /
//                Random 1/3 (last of row/col) / Random skip! (~1/4 of
//                beats go silent). The two "%" entries show a Percent box
//                beside the Pattern menu (what fraction of beats split,
//                re-rolled fresh each rebuild - this was the only behavior
//                before, hardcoded at 1/3 for 1/8th and 1/4 for 1/3); the
//                "last of bar"/"last of row-col" entries are deterministic
//                and show nothing extra - every bar's very last beat, or
//                every row/column span's last beat, always splits, no
//                percent involved.
//   Pitch      - Fixed (shows one Pitch box) / Rising at start (shows Base
//                pitch + Pitch step, unchanged) / Random (shows 4 pitch
//                boxes, each hand-set with a random starting value - a
//                future step will turn these into a chord the hit picks
//                from, for now it's just an independent per-hit pick of one
//                of the 4). All values plain Hz, since baseD/cym/hat all
//                take a Hz-based pitch arg, not a scale degree. Which boxes
//                show updates live as you change the Pitch menu. KNOWN
//                ISSUE, deliberately not being chased right now: something
//                about this row is wrong (per feedback) - not investigated,
//                since these three options are getting replaced wholesale
//                once chord-based pitch exists for the non-percussion
//                tracks and comes back around to inform a PT1-4 rework
//                (see CT8tracks.scd's PERCUSSION GENERATOR CONFIG comment).
//   Volume     - Fixed (shows one Volume Slider) / Alternate (shows two,
//                Vol A/Vol B, alternating every sounding hit) - Sliders,
//                not NumberBoxes (per feedback), mapped 0-4 via linlin same
//                as CT8guiAdjust.scd's tempo slider; each slider has its
//                own text readout since Slider has no numeric display of
//                its own. This is the only amp control left for PT1-4 (the
//                old Synth Controls window's per-synth amp slider is gone),
//                but is itself a placeholder, like Pitch above - due for
//                its own rework once chord-based volume/dynamics exist for
//                the non-percussion tracks.
//
// BASS (BT1-BT2) choices (~buildBassTrackPattern, same file) - mostly the
// same shape as percussion's above, so only what's different is called out:
//   Instrument - \fm or \plucking (not baseD/cym/hat/kick).
//   Pattern    - the same nine choices as percussion, minus First beat only
//                (not a useful choice for a bass part, per feedback).
//   Pitch      - only Fixed (one Pitch box, in MIDI note numbers now, not
//                Hz - both \fm/\plucking take a plain \midinote key; a
//                plain, non-chord-aware value) or Random (no extra boxes -
//                picks a tone from the shared ~currentChord
//                (CT8harmonySelect.scd) via ~chordNoteInRange, constrained
//                to a fixed, not-yet-adjustable range "below middle C" -
//                same helper/global HT1/MT1 use, just read once per
//                rebuild rather than live per-hit). No Rising mode -
//                otherwise same placeholder status as percussion's
//                Pitch/Volume above.
//   Volume     - identical to percussion's Fixed/Alternate Slider pair.
//
// A control change only updates its global - it does NOT rebuild/restart
// anything by itself, which would desync that track from every other track
// (the same problem CT8guiTracksLab.scd hit and fixed by waiting for a
// shared rebuild point). It takes effect at the clock's next natural
// rebuild (minute change, source/format toggle) automatically, since
// ~buildPercPattern just reads whatever these globals currently say - or
// click "Apply now" to force that same full-system rebuild immediately.
//


(

~makePercGeneratorWindow = {
    var window, statusText, applyNow, makeTrackSection, makeBassTrackSection;
    var percGenWidth = 640;
// Tall enough for all six blocks (PT1-4 + BT1-2) plus header/buttons -
// resizable:true (unlike the old fixed-size window) in case a shorter
// screen still can't show all of it at once.
    var percGenHeight = 1360;
// Fixed top-left position rather than derived from ~adjustWindow's bounds
// (as this used to be) - at this height, inheriting ~adjustWindow's
// vertical position (itself already offset above the main clock window,
// ~470px down) pushed this window far enough down that most screens can't
// fit it, which some window managers "fix" by shoving the whole window
// upward until it's off-screen at the top instead - hiding the header and
// first block or two. Starting near the actual screen origin leaves the
// most room for this window's own height to work with.
    var percGenBounds = Rect(40, 40, percGenWidth, percGenHeight);

    if(~percGeneratorWindow.notNil) { ~percGeneratorWindow.close };

    ~percGeneratorWindow = Window("Percussion + Bass Generator", percGenBounds, resizable: true, border: true)
        .front
        .alwaysOnTop_(true);
    ~percGeneratorWindow.view.background = Color(0.13, 0.14, 0.16);
    ~percGeneratorWindow.view.decorator = FlowLayout(~percGeneratorWindow.view.bounds, 12@12, 8@8);

// Rebuilds and restarts every track together (same as a natural minute
// rollover would), so a manual "apply this now" never leaves one percussion
// track out of phase with the rest. Also rebuilds/restarts the row/col
// flash players alongside the Pbinds - without this they'd keep running on
// their old schedule while the tracks jump to a fresh quant:1 restart,
// throwing flash and sound out of phase with each other until the next
// natural minute rollover (which already does both together) quietly fixed
// it. Every other full-rebuild trigger in the project (source/format
// toggles, CT8guiAdjust.scd) already does both for the same reason.
    applyNow = {
        ~stopPbinds.value;
        ~updatePbinds.value;
        ~restartPbinds.value;
        ~rebuildFlashPatterns.value;
        ~restartFlashPlayers.value;
        statusText.string_("Applied.");
    };

    StaticText(~percGeneratorWindow, 600@26).string_("PERCUSSION + BASS GENERATOR (PT1-PT4, BT1-BT2)")
        .font_(Font("Arial", 15, true)).stringColor_(Color.white);
    statusText = StaticText(~percGeneratorWindow, 600@20)
        .string_("Changes apply at the next clock update, or click Apply now.")
        .stringColor_(Color(0.7, 0.85, 0.75));
    ~percGeneratorWindow.view.decorator.nextLine;

// Builds one track's full control block (source/instrument/pattern/pitch +
// base pitch/pitch step), wired to that track name's own globals. Returns
// nothing - every control captures `name` in its own action closure, so no
// caller-side bookkeeping is needed.
    makeTrackSection = { |name|
        var trackContainer, trackColor, labelColor = Color.black;
        var onOffButton, sourceMenu, instrumentMenu, patternMenu, pitchMenu, volumeMenu;
        var pitchValuesView, rebuildPitchValues;
        var wetSlider, wetReadout, levelSlider, levelReadout;
        var volumeValuesView, rebuildVolumeValues;
        var percentLabel, percentBox, updatePatternPercentVisibility;
// Index <-> symbol mapping for the Pattern menu, in display order. Index 2's
// label depends on the current Source ("Start of Row"/"Start of Col") -
// patternLabelsFor rebuilds the full item list so that label always matches
// whichever Source is currently selected; patternSymbols never changes, so
// a track's ~percPattern[name] value always maps to a stable index. One
// flat list, not a Pattern menu plus a Variant sub-menu - the double-hit/
// triplet/percent/last-of-bar/last-of-row-col combinations used to hide
// behind an extra menu-within-a-menu, which was both confusing and, per
// feedback, buggy (the sub-menu's controls only ever rendered once).
        var patternSymbols = [
            \firstBeat, \everyBeat, \startOnly,
            \random8thPercent, \random8thLastBar, \random8thLastRowCol,
            \random3rdPercent, \random3rdLastBar, \random3rdLastRowCol,
            \randomSkip
        ];
        var patternLabelsFor = { |source|
            [
                "First beat only", "Every beat",
                "Start of " ++ (if(source == \row) { "Row" } { "Col" }),
                "Random 1/8th %", "Random 1/8th (last of bar)", "Random 1/8th (last of row/col)",
                "Random 1/3 %", "Random 1/3 (last of bar)", "Random 1/3 (last of row/col)",
                "Random skip!"
            ]
        };

// Each track's whole block sits on its own randomly-rolled muted color -
// same Color.rand(0.7) convention CT8fakeData.scd uses for its Actions
// plotter panel - re-rolled fresh every time this window is (re)built,
// not persisted. pitchValuesView (below, still the older remove/recreate
// placeholder - Pitch isn't getting the Slider/visible_ treatment yet, see
// this file's Volume-row comment) shares it rather than the window's own
// dark background, so it blends into the block instead of showing up as a
// contrasting hole.
        trackColor = Color.rand(0.7);
        trackContainer = CompositeView(~percGeneratorWindow, 600@190).background_(trackColor);
        trackContainer.decorator = FlowLayout(trackContainer.bounds, 8@8, 6@6);
        ~percGeneratorWindow.view.decorator.nextLine;

// NAME + ON/OFF: same red/green convention as CT8guiAdjust.scd's old
// per-track buttons (now removed from there - PT1-4's on/off lives here
// instead, beside the name it controls). Every percussion track always has
// a builder (~buildPercPattern), so unlike that old code there's no
// orange/unbuilt case to handle.
        StaticText(trackContainer, 140@22).string_(name.asString)
            .font_(Font("Arial", 13, true)).stringColor_(labelColor);
        onOffButton = Button(trackContainer, 68@24)
            .states_([
                [name.asString, Color.black, Color.red],
                [name.asString, Color.black, Color.green]
            ])
            .value_(if(~trackEnabled[name] == false) { 0 } { 1 })
            .action_({ |b|
                ~trackEnabled[name] = (b.value == 1);
                ~syncTrackPlayer.(name);
            });
        trackContainer.decorator.nextLine;

        StaticText(trackContainer, 55@24).string_("Source").stringColor_(labelColor);
        sourceMenu = PopUpMenu(trackContainer, 80@24)
            .items_(["Row", "Col"])
            .value_([\row, \col].indexOf(~percSource[name]) ? 0)
            .action_({ |m|
                ~percSource[name] = [\row, \col][m.value];
// Relabel the Pattern menu's "Start of Row/Col" entry to match, without
// disturbing the track's actual selected pattern.
                patternMenu.items_(patternLabelsFor.(~percSource[name]));
                patternMenu.value_(patternSymbols.indexOf(~percPattern[name]) ? 1);
                statusText.string_("Changed - not yet applied.");
            });

        StaticText(trackContainer, 75@24).string_("Instrument").stringColor_(labelColor);
// indexOf against the exact same [\baseD, \cym, \hat, \kick] symbol array
// the action below maps back from - was comparing ~percInstrument[name]
// .asString against a separate string-literal items list before, which
// left room for the initial displayed selection to disagree with what
// actually plays; every other menu/dropdown in this file (Source/Pattern/
// Pitch/Volume) already compares symbols directly like this, so
// Instrument matches that same proven pattern instead of being the odd
// one out.
        instrumentMenu = PopUpMenu(trackContainer, 90@24)
            .items_(["baseD", "cym", "hat", "kick"])
            .value_([\baseD, \cym, \hat, \kick].indexOf(~percInstrument[name]) ? 2)
            .action_({ |m|
                ~percInstrument[name] = [\baseD, \cym, \hat, \kick][m.value];
                statusText.string_("Changed - not yet applied.");
            });

// Wet/Level: this instrument's own tiny built-in ~allpassWash tail
// (~percWet[name]/~percLevel[name], \wet/\level args on \baseD/\cym/\hat -
// see CT8synths.scd), not the shared ~clockRev send every other track uses
// (PT1-4 never reached that anyway - see ~buildPercPattern's \fx comment,
// below). Unlike every other control here, these are read live via Pfunc,
// not baked into a pre-resolved array, so they update immediately - no
// rebuild or Apply now needed. Plain Sliders rather than NumberBoxes - both
// are already native 0-1 ranges, no log/exp mapping needed; the readouts
// are plain text mirrors since Slider has no numeric display of its own
// (same reason CT8guiAdjust.scd's tempo slider has its own label).
        StaticText(trackContainer, 24@24).string_("Wet").stringColor_(labelColor);
        wetSlider = Slider(trackContainer, 50@24)
            .value_(~percWet[name])
            .action_({ |sl|
                ~percWet[name] = sl.value;
                wetReadout.string_(sl.value.round(0.01).asString);
                statusText.string_("Wet updated (live, no rebuild needed).");
            });
        wetReadout = StaticText(trackContainer, 26@24)
            .string_(~percWet[name].round(0.01).asString).stringColor_(labelColor);

        StaticText(trackContainer, 30@24).string_("Level").stringColor_(labelColor);
        levelSlider = Slider(trackContainer, 50@24)
            .value_(~percLevel[name])
            .action_({ |sl|
                ~percLevel[name] = sl.value;
                levelReadout.string_(sl.value.round(0.01).asString);
                statusText.string_("Level updated (live, no rebuild needed).");
            });
        levelReadout = StaticText(trackContainer, 26@24)
            .string_(~percLevel[name].round(0.01).asString).stringColor_(labelColor);
        trackContainer.decorator.nextLine;

        StaticText(trackContainer, 55@24).string_("Pattern").stringColor_(labelColor);
        patternMenu = PopUpMenu(trackContainer, 220@24)
            .items_(patternLabelsFor.(~percSource[name]))
            .value_(patternSymbols.indexOf(~percPattern[name]) ? 1)
            .action_({ |m|
                ~percPattern[name] = patternSymbols[m.value];
                updatePatternPercentVisibility.value;
                statusText.string_("Changed - not yet applied.");
            });
// Percent box only matters for the two "%" patterns (\random8thPercent/
// \random3rdPercent) - the four \...LastBar/\...LastRowCol patterns are
// deterministic, nothing to dial in. Built once and toggled with
// .visible_, rather than removed/recreated on every Pattern change like an
// earlier version of this did - that version's controls stopped
// reappearing after the first time, apparently a repaint issue with
// dynamically adding children to an already-laid-out CompositeView rather
// than a logic bug (the remove/rebuild fired every time, it just didn't
// always redraw) - so this sidesteps it entirely by never removing the
// widgets at all.
        percentLabel = StaticText(trackContainer, 16@24).string_("%").stringColor_(labelColor);
        percentBox = NumberBox(trackContainer, 45@24)
            .value_(~percSplitPercent[name])
            .clipLo_(0).clipHi_(100).step_(1)
            .action_({ |box|
                ~percSplitPercent[name] = box.value.clip(0, 100);
                statusText.string_("Changed - not yet applied.");
            });
        trackContainer.decorator.nextLine;

        updatePatternPercentVisibility = {
            var pattern = ~percPattern[name];
            var isPercentPattern = (pattern == \random8thPercent) or: { pattern == \random3rdPercent };
            percentLabel.visible_(isPercentPattern);
            percentBox.visible_(isPercentPattern);
        };
        updatePatternPercentVisibility.value;

// PITCH ROW: pitchValuesView is a fixed-size placeholder whose CONTENTS get
// torn down and rebuilt by rebuildPitchValues whenever the Pitch mode
// changes - Fixed shows one box, Rising shows the original Base pitch/
// Pitch step pair, Random shows all 4 of ~percRandomPitches[name]. Keeping
// the placeholder itself a fixed size means switching modes never reflows
// anything below it.
        StaticText(trackContainer, 40@24).string_("Pitch").stringColor_(labelColor);
        pitchMenu = PopUpMenu(trackContainer, 130@24)
            .items_(["Fixed", "Rising at start", "Random"])
            .value_([\fixed, \rising, \random].indexOf(~percPitchMode[name]) ? 0)
            .action_({ |m|
                ~percPitchMode[name] = [\fixed, \rising, \random][m.value];
                rebuildPitchValues.value;
                statusText.string_("Changed - not yet applied.");
            });
        pitchValuesView = CompositeView(trackContainer, 320@28).background_(trackColor);
        pitchValuesView.decorator = FlowLayout(pitchValuesView.bounds, 2@2, 4@4);
        trackContainer.decorator.nextLine;

        rebuildPitchValues = {
            pitchValuesView.children.do { |c| c.remove };
            switch(~percPitchMode[name],
                \fixed, {
                    StaticText(pitchValuesView, 40@24).string_("Pitch").stringColor_(labelColor);
                    NumberBox(pitchValuesView, 65@24)
                        .value_(~percBasePitch[name])
                        .clipLo_(20).clipHi_(8000)
                        .action_({ |box|
                            ~percBasePitch[name] = box.value.clip(20, 8000);
                            statusText.string_("Changed - not yet applied.");
                        });
                },
                \rising, {
                    StaticText(pitchValuesView, 65@24).string_("Base pitch").stringColor_(labelColor);
                    NumberBox(pitchValuesView, 65@24)
                        .value_(~percBasePitch[name])
                        .clipLo_(20).clipHi_(8000)
                        .action_({ |box|
                            ~percBasePitch[name] = box.value.clip(20, 8000);
                            statusText.string_("Changed - not yet applied.");
                        });
                    StaticText(pitchValuesView, 65@24).string_("Pitch step").stringColor_(labelColor);
                    NumberBox(pitchValuesView, 65@24)
                        .value_(~percPitchStep[name])
                        .clipLo_(0).clipHi_(2000)
                        .action_({ |box|
                            ~percPitchStep[name] = box.value.clip(0, 2000);
                            statusText.string_("Changed - not yet applied.");
                        });
                },
                \random, {
                    4.do { |i|
                        StaticText(pitchValuesView, 14@24).string_((i + 1).asString).stringColor_(labelColor);
                        NumberBox(pitchValuesView, 55@24)
                            .value_(~percRandomPitches[name][i])
                            .clipLo_(20).clipHi_(8000)
                            .action_({ |box|
                                ~percRandomPitches[name][i] = box.value.clip(20, 8000);
                                statusText.string_("Changed - not yet applied.");
                            });
                    };
                }
            );
        };
        rebuildPitchValues.value;

// VOLUME ROW: Fixed shows one Volume Slider; Alternate shows two (Vol A/
// Vol B), which ~buildPercPattern (CT8tracks.scd) alternates between every
// sounding hit. This is the only amp control left for PT1-4, now that the
// old Synth Controls window (and its per-synth amp slider) is gone - but is
// itself a placeholder pending the planned chord-based rework (see
// CT8tracks.scd's PERCUSSION GENERATOR CONFIG comment).
        StaticText(trackContainer, 55@24).string_("Volume").stringColor_(labelColor);
        volumeMenu = PopUpMenu(trackContainer, 110@24)
            .items_(["Fixed", "Alternate"])
            .value_([\fixed, \alternate].indexOf(~percVolumeMode[name]) ? 0)
            .action_({ |m|
                ~percVolumeMode[name] = [\fixed, \alternate][m.value];
                rebuildVolumeValues.value;
                statusText.string_("Changed - not yet applied.");
            });
// volumeValuesView is a fixed-size placeholder, same remove/recreate
// technique the Pitch row above uses (pitchValuesView/rebuildPitchValues) -
// switched to from an earlier .visible_-based version (same idea as the
// Pattern row's Percent box) that, for this row specifically, didn't work:
// with BOTH the Fixed slider AND the two Alternate sliders built as
// siblings directly in trackContainer, the FlowLayout still reserved space
// for whichever set was hidden, so Alternate's two sliders didn't fit on
// the row even though only one set was ever visible at once. Building only
// the currently-needed widgets inside their own fixed-size child container
// (sized to comfortably fit Alternate, the wider of the two) avoids that -
// the parent flow only ever sees this one fixed-width child, regardless of
// what's inside it. Sliders rather than NumberBoxes, per feedback - 0-4
// needs a linlin mapping to/from the Slider's native 0-1, same technique
// CT8guiAdjust.scd's tempo slider already uses for its 60-240 BPM range.
// Volume is a placeholder pending a bigger rework (chord-based pitch/
// volume for the non-percussion tracks is coming first, then PT1-4's pitch
// and volume both get redesigned to match - see CT8tracks.scd's
// PERCUSSION GENERATOR CONFIG comment).
        volumeValuesView = CompositeView(trackContainer, 320@28).background_(trackColor);
        volumeValuesView.decorator = FlowLayout(volumeValuesView.bounds, 2@2, 4@4);
        trackContainer.decorator.nextLine;

        rebuildVolumeValues = {
            volumeValuesView.children.do { |c| c.remove };
            switch(~percVolumeMode[name],
                \fixed, {
                    var readout;
                    StaticText(volumeValuesView, 44@24).string_("Volume").stringColor_(labelColor);
                    Slider(volumeValuesView, 65@24)
                        .value_(~percVolume[name].linlin(0, 4, 0, 1))
                        .action_({ |sl|
                            var v = sl.value.linlin(0, 1, 0, 4);
                            ~percVolume[name] = v;
                            readout.string_(v.round(0.01).asString);
                            statusText.string_("Changed - not yet applied.");
                        });
                    readout = StaticText(volumeValuesView, 32@24)
                        .string_(~percVolume[name].round(0.01).asString).stringColor_(labelColor);
                },
                \alternate, {
                    var readoutA, readoutB;
                    StaticText(volumeValuesView, 36@24).string_("Vol A").stringColor_(labelColor);
                    Slider(volumeValuesView, 65@24)
                        .value_(~percVolumeLevels[name][0].linlin(0, 4, 0, 1))
                        .action_({ |sl|
                            var v = sl.value.linlin(0, 1, 0, 4);
                            ~percVolumeLevels[name][0] = v;
                            readoutA.string_(v.round(0.01).asString);
                            statusText.string_("Changed - not yet applied.");
                        });
                    readoutA = StaticText(volumeValuesView, 32@24)
                        .string_(~percVolumeLevels[name][0].round(0.01).asString).stringColor_(labelColor);

                    StaticText(volumeValuesView, 36@24).string_("Vol B").stringColor_(labelColor);
                    Slider(volumeValuesView, 65@24)
                        .value_(~percVolumeLevels[name][1].linlin(0, 4, 0, 1))
                        .action_({ |sl|
                            var v = sl.value.linlin(0, 1, 0, 4);
                            ~percVolumeLevels[name][1] = v;
                            readoutB.string_(v.round(0.01).asString);
                            statusText.string_("Changed - not yet applied.");
                        });
                    readoutB = StaticText(volumeValuesView, 32@24)
                        .string_(~percVolumeLevels[name][1].round(0.01).asString).stringColor_(labelColor);
                }
            );
        };
        rebuildVolumeValues.value;
    };

    ~percTrackNames.do(makeTrackSection);

// Builds one bass track's full control block - same shape as
// makeTrackSection above (name/on-off, source/instrument/wet/level,
// pattern/percent, pitch, volume), wired to ~bassX[name] (CT8tracks.scd)
// instead of ~percX[name], with the smaller menus BT1/BT2 actually need
// (two instruments, no First-beat-only pattern, two pitch modes instead of
// three, pitch in MIDI notes rather than Hz). Kept as its own closure
// rather than parameterizing makeTrackSection over which global-dictionary
// set/menu-items to use - the two tracks' choices differ enough (instrument
// list, pattern list, pitch units and mode count) that threading all of it
// through one shared function would need about as many parameters as just
// writing the block twice.
    makeBassTrackSection = { |name|
        var trackContainer, trackColor, labelColor = Color.black;
        var onOffButton, sourceMenu, instrumentMenu, patternMenu, pitchMenu, volumeMenu;
        var pitchValuesView, rebuildPitchValues;
        var wetSlider, wetReadout, levelSlider, levelReadout;
        var volumeValuesView, rebuildVolumeValues;
        var percentLabel, percentBox, updatePatternPercentVisibility;
// Same flattened Pattern list as percussion's patternSymbols/patternLabelsFor
// (see makeTrackSection, above), minus \firstBeat - not a useful choice for
// a bass part, per feedback.
        var patternSymbols = [
            \everyBeat, \startOnly,
            \random8thPercent, \random8thLastBar, \random8thLastRowCol,
            \random3rdPercent, \random3rdLastBar, \random3rdLastRowCol,
            \randomSkip
        ];
        var patternLabelsFor = { |source|
            [
                "Every beat",
                "Start of " ++ (if(source == \row) { "Row" } { "Col" }),
                "Random 1/8th %", "Random 1/8th (last of bar)", "Random 1/8th (last of row/col)",
                "Random 1/3 %", "Random 1/3 (last of bar)", "Random 1/3 (last of row/col)",
                "Random skip!"
            ]
        };

        trackColor = Color.rand(0.7);
        trackContainer = CompositeView(~percGeneratorWindow, 600@190).background_(trackColor);
        trackContainer.decorator = FlowLayout(trackContainer.bounds, 8@8, 6@6);
        ~percGeneratorWindow.view.decorator.nextLine;

        StaticText(trackContainer, 140@22).string_(name.asString)
            .font_(Font("Arial", 13, true)).stringColor_(labelColor);
        onOffButton = Button(trackContainer, 68@24)
            .states_([
                [name.asString, Color.black, Color.red],
                [name.asString, Color.black, Color.green]
            ])
            .value_(if(~trackEnabled[name] == false) { 0 } { 1 })
            .action_({ |b|
                ~trackEnabled[name] = (b.value == 1);
                ~syncTrackPlayer.(name);
            });
        trackContainer.decorator.nextLine;

        StaticText(trackContainer, 55@24).string_("Source").stringColor_(labelColor);
        sourceMenu = PopUpMenu(trackContainer, 80@24)
            .items_(["Row", "Col"])
            .value_([\row, \col].indexOf(~bassSource[name]) ? 0)
            .action_({ |m|
                ~bassSource[name] = [\row, \col][m.value];
                patternMenu.items_(patternLabelsFor.(~bassSource[name]));
                patternMenu.value_(patternSymbols.indexOf(~bassPattern[name]) ? 0);
                statusText.string_("Changed - not yet applied.");
            });

        StaticText(trackContainer, 75@24).string_("Instrument").stringColor_(labelColor);
        instrumentMenu = PopUpMenu(trackContainer, 90@24)
            .items_(["fm", "plucking"])
            .value_([\fm, \plucking].indexOf(~bassInstrument[name]) ? 0)
            .action_({ |m|
                ~bassInstrument[name] = [\fm, \plucking][m.value];
                statusText.string_("Changed - not yet applied.");
            });

        StaticText(trackContainer, 24@24).string_("Wet").stringColor_(labelColor);
        wetSlider = Slider(trackContainer, 50@24)
            .value_(~bassWet[name])
            .action_({ |sl|
                ~bassWet[name] = sl.value;
                wetReadout.string_(sl.value.round(0.01).asString);
                statusText.string_("Wet updated (live, no rebuild needed).");
            });
        wetReadout = StaticText(trackContainer, 26@24)
            .string_(~bassWet[name].round(0.01).asString).stringColor_(labelColor);

        StaticText(trackContainer, 30@24).string_("Level").stringColor_(labelColor);
        levelSlider = Slider(trackContainer, 50@24)
            .value_(~bassLevel[name])
            .action_({ |sl|
                ~bassLevel[name] = sl.value;
                levelReadout.string_(sl.value.round(0.01).asString);
                statusText.string_("Level updated (live, no rebuild needed).");
            });
        levelReadout = StaticText(trackContainer, 26@24)
            .string_(~bassLevel[name].round(0.01).asString).stringColor_(labelColor);
        trackContainer.decorator.nextLine;

        StaticText(trackContainer, 55@24).string_("Pattern").stringColor_(labelColor);
        patternMenu = PopUpMenu(trackContainer, 220@24)
            .items_(patternLabelsFor.(~bassSource[name]))
            .value_(patternSymbols.indexOf(~bassPattern[name]) ? 0)
            .action_({ |m|
                ~bassPattern[name] = patternSymbols[m.value];
                updatePatternPercentVisibility.value;
                statusText.string_("Changed - not yet applied.");
            });
        percentLabel = StaticText(trackContainer, 16@24).string_("%").stringColor_(labelColor);
        percentBox = NumberBox(trackContainer, 45@24)
            .value_(~bassSplitPercent[name])
            .clipLo_(0).clipHi_(100).step_(1)
            .action_({ |box|
                ~bassSplitPercent[name] = box.value.clip(0, 100);
                statusText.string_("Changed - not yet applied.");
            });
        trackContainer.decorator.nextLine;

        updatePatternPercentVisibility = {
            var pattern = ~bassPattern[name];
            var isPercentPattern = (pattern == \random8thPercent) or: { pattern == \random3rdPercent };
            percentLabel.visible_(isPercentPattern);
            percentBox.visible_(isPercentPattern);
        };
        updatePatternPercentVisibility.value;

// PITCH ROW: Fixed shows one Pitch box, in MIDI note numbers (not Hz - both
// \fm/\plucking take a plain \midinote key); Random shows nothing extra -
// it just picks a fresh note "below middle C" each hit from a fixed range
// (~bassRandomPitchLo/~bassRandomPitchHi, CT8tracks.scd), not yet
// user-adjustable, same placeholder status as percussion's own Pitch row.
        StaticText(trackContainer, 40@24).string_("Pitch").stringColor_(labelColor);
        pitchMenu = PopUpMenu(trackContainer, 130@24)
            .items_(["Fixed", "Random"])
            .value_([\fixed, \random].indexOf(~bassPitchMode[name]) ? 0)
            .action_({ |m|
                ~bassPitchMode[name] = [\fixed, \random][m.value];
                rebuildPitchValues.value;
                statusText.string_("Changed - not yet applied.");
            });
        pitchValuesView = CompositeView(trackContainer, 320@28).background_(trackColor);
        pitchValuesView.decorator = FlowLayout(pitchValuesView.bounds, 2@2, 4@4);
        trackContainer.decorator.nextLine;

        rebuildPitchValues = {
            pitchValuesView.children.do { |c| c.remove };
            switch(~bassPitchMode[name],
                \fixed, {
                    StaticText(pitchValuesView, 65@24).string_("Base pitch").stringColor_(labelColor);
                    NumberBox(pitchValuesView, 65@24)
                        .value_(~bassBasePitch[name])
                        .clipLo_(0).clipHi_(127)
                        .action_({ |box|
                            ~bassBasePitch[name] = box.value.clip(0, 127);
                            statusText.string_("Changed - not yet applied.");
                        });
                },
                \random, {
                    StaticText(pitchValuesView, 300@24)
                        .string_("Random, below middle C (fixed range).")
                        .stringColor_(labelColor);
                }
            );
        };
        rebuildPitchValues.value;

// VOLUME ROW: identical technique to makeTrackSection's own Volume row -
// see its comment for why this is a remove/recreate placeholder rather
// than two sets of siblings toggled with .visible_.
        StaticText(trackContainer, 55@24).string_("Volume").stringColor_(labelColor);
        volumeMenu = PopUpMenu(trackContainer, 110@24)
            .items_(["Fixed", "Alternate"])
            .value_([\fixed, \alternate].indexOf(~bassVolumeMode[name]) ? 0)
            .action_({ |m|
                ~bassVolumeMode[name] = [\fixed, \alternate][m.value];
                rebuildVolumeValues.value;
                statusText.string_("Changed - not yet applied.");
            });
        volumeValuesView = CompositeView(trackContainer, 320@28).background_(trackColor);
        volumeValuesView.decorator = FlowLayout(volumeValuesView.bounds, 2@2, 4@4);
        trackContainer.decorator.nextLine;

        rebuildVolumeValues = {
            volumeValuesView.children.do { |c| c.remove };
            switch(~bassVolumeMode[name],
                \fixed, {
                    var readout;
                    StaticText(volumeValuesView, 44@24).string_("Volume").stringColor_(labelColor);
                    Slider(volumeValuesView, 65@24)
                        .value_(~bassVolume[name].linlin(0, 4, 0, 1))
                        .action_({ |sl|
                            var v = sl.value.linlin(0, 1, 0, 4);
                            ~bassVolume[name] = v;
                            readout.string_(v.round(0.01).asString);
                            statusText.string_("Changed - not yet applied.");
                        });
                    readout = StaticText(volumeValuesView, 32@24)
                        .string_(~bassVolume[name].round(0.01).asString).stringColor_(labelColor);
                },
                \alternate, {
                    var readoutA, readoutB;
                    StaticText(volumeValuesView, 36@24).string_("Vol A").stringColor_(labelColor);
                    Slider(volumeValuesView, 65@24)
                        .value_(~bassVolumeLevels[name][0].linlin(0, 4, 0, 1))
                        .action_({ |sl|
                            var v = sl.value.linlin(0, 1, 0, 4);
                            ~bassVolumeLevels[name][0] = v;
                            readoutA.string_(v.round(0.01).asString);
                            statusText.string_("Changed - not yet applied.");
                        });
                    readoutA = StaticText(volumeValuesView, 32@24)
                        .string_(~bassVolumeLevels[name][0].round(0.01).asString).stringColor_(labelColor);

                    StaticText(volumeValuesView, 36@24).string_("Vol B").stringColor_(labelColor);
                    Slider(volumeValuesView, 65@24)
                        .value_(~bassVolumeLevels[name][1].linlin(0, 4, 0, 1))
                        .action_({ |sl|
                            var v = sl.value.linlin(0, 1, 0, 4);
                            ~bassVolumeLevels[name][1] = v;
                            readoutB.string_(v.round(0.01).asString);
                            statusText.string_("Changed - not yet applied.");
                        });
                    readoutB = StaticText(volumeValuesView, 32@24)
                        .string_(~bassVolumeLevels[name][1].round(0.01).asString).stringColor_(labelColor);
                }
            );
        };
        rebuildVolumeValues.value;
    };

    StaticText(~percGeneratorWindow, 600@26).string_("BASS GENERATOR (BT1-BT2)")
        .font_(Font("Arial", 14, true)).stringColor_(Color.white);
    ~percGeneratorWindow.view.decorator.nextLine;
    ~bassTrackNames.do(makeBassTrackSection);

    Button(~percGeneratorWindow, 120@26).states_([["Apply now", Color.black, Color(0.65, 0.85, 0.65)]])
        .action_({ applyNow.value });

// Forcibly resets every track's whole config (~resetPercConfig/
// ~resetBassConfig, CT8tracks.scd), then rebuilds this window from scratch
// so every menu/box reflects the reset values, then applies immediately the
// same way Apply now does - a plain re-call of ~makePercGeneratorWindow
// rather than reusing this instance's own applyNow, since that closure
// belongs to the window this button is about to replace.
    Button(~percGeneratorWindow, 150@26).states_([["Reset to defaults", Color.black, Color(0.85, 0.55, 0.55)]])
        .action_({
            ~percTrackNames.do(~resetPercConfig);
            ~bassTrackNames.do(~resetBassConfig);
            ~makePercGeneratorWindow.value;
            ~stopPbinds.value;
            ~updatePbinds.value;
            ~restartPbinds.value;
            ~rebuildFlashPatterns.value;
            ~restartFlashPlayers.value;
        });

    ~percGeneratorWindow.onClose = { ~percGeneratorWindow = nil };
};

"ClockToy percussion-generator-window GUI functions loaded.".postln;

)
