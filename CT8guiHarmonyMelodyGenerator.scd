// ============================================================================
// CT8guiHarmonyMelodyGenerator.scd
// CLOCKTOY - HARMONY + MELODY GENERATOR WINDOW (HT1-HT4, MT1-MT2) - SKELETON
// ============================================================================
//
// Same two-pane per-track block layout as CT8guiPercGenerator.scd's
// "Percussion + Bass Generator" window - left pane: Mix/Vol/Dry/Rev vertical
// Sliders; right pane: Name + on-off square + Source + Instrument on row 1,
// "Dur Pat"/"Pit Pat"/"Accents" column headers, Pattern/Pitch/Volume menus
// (all the same width) on row 2, and a matching-width Percent/RangeSlider
// under each on row 3 - copied here as a starting skeleton for HT1-4/MT1-2,
// per explicit request ("we will rework it step at a time").
//
// Deliberately NOT yet wired into ~buildHarmonyPattern/~buildMelodyPattern
// (CT8tracks.scd) - those two are still their own bespoke, chord-based
// builders, untouched by this file. Every control here besides on/off and
// MT1's own Volume row reads and writes a brand new set of placeholder
// globals (~hmX, below) that don't affect playback yet - this window's job
// for now is just to exist with the right shape; what each control should
// actually DO for a chord-aware harmony/melody track is a later step. The
// on/off button IS real, though: same ~trackEnabled[name]/~syncTrackPlayer
// every other window's on/off button already uses, and shows orange (not
// red/green, same convention CT8guiAdjust.scd's own buttons use) for
// HT2-4/MT2, which have no builder yet - HT1/MT1 are the only two of these
// six with a real builder right now. MT1's Volume menu/RangeSlider is also
// real now - ~buildMelodyPattern reads ~hmVolumeMode[\MT1]/
// ~hmVolumeLevels[\MT1] directly (same Fixed/Alternate convention
// ~buildBassTrackPattern uses for BT1/BT2), since per feedback a melody
// track should be structured the same way a bass track is - single note,
// same volume handling - not just "single note, hardcoded amp".
//
// One shared closure (makeHmTrackSection) builds all six tracks, rather
// than splitting into separate harmony/melody versions the way
// percussion/bass needed to - HT1-4 and MT1-2 are identical in shape for
// now; split them apart once (if) their actual controls diverge.
//
// Moved here from the Clock Toy Adjust window (CT8guiAdjust.scd), which
// used to have HT1-4/MT1-2's on/off buttons in its own "Harm"/"Mel" rows -
// only MT3/MT4 are left there now.
//


(

~hmTrackNames = [\HT1, \HT2, \HT3, \HT4, \MT1, \MT2];
~hmSource = ~hmSource ? ();
~hmInstrument = ~hmInstrument ? ();
~hmPattern = ~hmPattern ? ();
~hmPitchMode = ~hmPitchMode ? ();
~hmBasePitch = ~hmBasePitch ? ();
~hmVolumeMode = ~hmVolumeMode ? ();
~hmVolumeLevels = ~hmVolumeLevels ? ();
~hmWet = ~hmWet ? ();
~hmLevel = ~hmLevel ? ();
~hmSplitPercent = ~hmSplitPercent ? ();
// HT1-4 default to Row scan, MT1-2 to Column scan - the same identity
// ~buildHarmonyPattern (HT1)/~buildMelodyPattern (MT1) already have today,
// even though this Source menu doesn't drive them yet.
~hmSourceDefaults = (HT1: \row, HT2: \row, HT3: \row, HT4: \row, MT1: \col, MT2: \col);
// \fm for every one of these six, matching HT1/MT1's real instrument today.
~hmInstrumentDefaults = (HT1: \fm, HT2: \fm, HT3: \fm, HT4: \fm, MT1: \fm, MT2: \fm);
~hmTrackNames.do { |name|
    ~hmSource[name] = ~hmSource[name] ? ~hmSourceDefaults[name];
    ~hmInstrument[name] = ~hmInstrument[name] ? ~hmInstrumentDefaults[name];
    ~hmPattern[name] = ~hmPattern[name] ? \everyBeat;
    ~hmPitchMode[name] = ~hmPitchMode[name] ? \fixed;
    ~hmBasePitch[name] = ~hmBasePitch[name] ? [60, 60];
    ~hmVolumeMode[name] = ~hmVolumeMode[name] ? \fixed;
    ~hmVolumeLevels[name] = ~hmVolumeLevels[name] ? [0.2, 0.2];
    ~hmWet[name] = ~hmWet[name] ? 0;
    ~hmLevel[name] = ~hmLevel[name] ? 1;
    ~hmSplitPercent[name] = ~hmSplitPercent[name] ? 33;
};

// Forcibly resets one track's whole config back to these same original
// defaults - mirrors ~resetPercConfig/~resetBassConfig (CT8tracks.scd),
// same reason (see either one's own comment).
~resetHmConfig = { |name|
    ~hmSource[name] = ~hmSourceDefaults[name];
    ~hmInstrument[name] = ~hmInstrumentDefaults[name];
    ~hmPattern[name] = \everyBeat;
    ~hmPitchMode[name] = \fixed;
    ~hmBasePitch[name] = [60, 60];
    ~hmVolumeMode[name] = \fixed;
    ~hmVolumeLevels[name] = [0.2, 0.2];
    ~hmWet[name] = 0;
    ~hmLevel[name] = 1;
    ~hmSplitPercent[name] = 33;
};

~makeHarmonyMelodyGeneratorWindow = {
    var statusText, applyNow, makeHmTrackSection;
    var hmGenWidth = 640;
// 1360 -> 1060: each block shrank by 50px (190 -> 140, from the
// Mix/Vol/Dry/Rev sliders going 130 -> 90) - 50 * 6 blocks = 300px saved
// overall. Mirrors CT8guiPercGenerator.scd's own identical change.
    var hmGenHeight = 1060;
    var hmGenBounds = Rect(700, 40, hmGenWidth, hmGenHeight);

    if(~hmGeneratorWindow.notNil) { ~hmGeneratorWindow.close };

    ~hmGeneratorWindow = Window("Harmony + Melody Generator", hmGenBounds, resizable: true, border: true)
        .front
        .alwaysOnTop_(true);
    ~hmGeneratorWindow.view.background = Color(0.13, 0.14, 0.16);
    ~hmGeneratorWindow.view.decorator = FlowLayout(~hmGeneratorWindow.view.bounds, 12@12, 8@8);

// Same shape as ~makePercGeneratorWindow's own applyNow - rebuilds/
// restarts every track together so a manual "apply now" never leaves one
// track out of phase with the rest.
    applyNow = {
        ~stopPbinds.value;
        ~updatePbinds.value;
        ~restartPbinds.value;
        ~rebuildFlashPatterns.value;
        ~restartFlashPlayers.value;
        statusText.string_("Applied.");
    };

    StaticText(~hmGeneratorWindow, 600@26).string_("HARMONY + MELODY GENERATOR (HT1-HT4, MT1-MT2)")
        .font_(Font("Arial", 15, true)).stringColor_(Color.white);
    statusText = StaticText(~hmGeneratorWindow, 600@20)
        .string_("Skeleton copy of the Percussion + Bass layout - only on/off is wired to playback so far.")
        .stringColor_(Color(0.7, 0.85, 0.75));
    ~hmGeneratorWindow.view.decorator.nextLine;

// Builds one track's full control block - identical shape to
// CT8guiPercGenerator.scd's makeTrackSection (see that file for the
// RangeSlider/explicit-Rect notes this copies verbatim), wired to ~hmX[name]
// instead of ~percX[name].
    makeHmTrackSection = { |name|
        var trackContainer, trackColor, labelColor = Color.black;
        var leftPane, rightPane;
        var mixSlider, volSlider, sendASlider, sendBSlider;
        var onOffButton, sourceMenu, instrumentMenu, patternMenu, pitchMenu, volumeMenu;
        var patternSubView, pitchSubView, volumeSubView;
        var percentSlider, percentReadout, updatePatternPercentVisibility;
        var pitchRangeSlider, pitchRangeReadout, updatePitchRangeReadout;
        var volumeRangeSlider, volumeRangeReadout, updateVolumeRangeReadout;
        var isBuilt = ~trackBuilders[name].notNil;
        var unbuiltColor = Color.new255(255, 165, 0);
        var patternSymbols = [
            \firstBeat, \everyBeat, \startOnly,
            \random8thPercent, \random8thLastBar, \random8thLastRowCol,
            \random3rdPercent, \random3rdLastBar, \random3rdLastRowCol,
            \random4to3Percent, \random4to3LastBar, \random4to3LastRowCol,
            \randomSkip
        ];
// "Random" dropped from every label - mirrors CT8guiPercGenerator.scd's own
// patternLabelsFor (kept in sync even though this window isn't wired to
// playback yet).
        var patternLabelsFor = { |source|
            [
                "First beat only", "Every beat",
                "Start of " ++ (if(source == \row) { "Row" } { "Col" }),
                "1/8th %", "1/8th (last of bar)", "1/8th (last of row/col)",
                "1/3 %", "1/3 (last of bar)", "1/3 (last of row/col)",
                "4/3 %", "4/3 (last of bar)", "4/3 (last of row/col)",
                "Skip %"
            ]
        };

        trackColor = Color.rand(0.7);
// Shrunk from 190 along with leftPane/rightPane and the Mix/Vol/Dry/Rev
// sliders below (130 -> 90, ~30% shorter, per feedback) - mirrors
// CT8guiPercGenerator.scd's own identical change.
        trackContainer = CompositeView(~hmGeneratorWindow, 600@140).background_(trackColor);
        ~hmGeneratorWindow.view.decorator.nextLine;

// LEFT PANE: 4 vertical Sliders. Mix/Vol are a tiny built-in reverb tail,
// same role as ~percWet/~percLevel (CT8synths.scd's \wet/\level convention)
// - but not actually connected to any SynthDef yet, since nothing here
// plays a sound of its own. Dry/Rev (placeholders, do nothing yet) mirror
// the Percussion + Bass Generator's own.
// x=484, not 6 - see CT8guiPercGenerator.scd's own leftPane comment for
// why (empirically mirrored child positioning). Slightly darker background
// than the rest of the block, built component-wise rather than
// `trackColor * 0.8` - Color has no `*` operator for a plain number, and
// that crashed the whole window build instantly, on the very first track.
        leftPane = CompositeView(trackContainer, Rect(484, 6, 110, 128)).background_(
            Color.new(trackColor.red * 0.8, trackColor.green * 0.8, trackColor.blue * 0.8, trackColor.alpha)
        );
        leftPane.decorator = FlowLayout(leftPane.bounds, 4@4, 4@4);

        StaticText(leftPane, 20@14).string_("Mix").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("Vol").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("Dry").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("Rev").stringColor_(labelColor);
        leftPane.decorator.nextLine;

        mixSlider = Slider(leftPane, 20@90)
            .value_(~hmWet[name])
            .action_({ |sl|
                ~hmWet[name] = sl.value;
                statusText.string_("Changed (not yet wired to playback).");
            });
        volSlider = Slider(leftPane, 20@90)
            .value_(~hmLevel[name])
            .action_({ |sl|
                ~hmLevel[name] = sl.value;
                statusText.string_("Changed (not yet wired to playback).");
            });
        sendASlider = Slider(leftPane, 20@90);
        sendBSlider = Slider(leftPane, 20@90);

// RIGHT PANE.
// x=6, not 124 - mirror image of leftPane's own x, same reason.
        rightPane = CompositeView(trackContainer, Rect(6, 6, 470, 128)).background_(trackColor);
        rightPane.decorator = FlowLayout(rightPane.bounds, 6@6, 4@4);

// ROW 1: on/off IS real - same ~trackEnabled[name]/~syncTrackPlayer every
// other on/off button in the project uses - shown orange (not red/green)
// when this track has no builder yet (HT2-4/MT2 right now), same
// convention CT8guiAdjust.scd's own buttons use.
        StaticText(rightPane, 48@22).string_(name.asString)
            .font_(Font("Arial", 13, true)).stringColor_(labelColor);
        onOffButton = Button(rightPane, 24@24)
            .states_(
                if(isBuilt) {
                    [[" ", Color.black, Color.red], [" ", Color.black, Color.green]]
                } {
                    [[" ", Color.black, unbuiltColor], [" ", Color.black, unbuiltColor]]
                }
            )
            .value_(if(~trackEnabled[name] == false) { 0 } { 1 })
            .action_({ |b|
                ~trackEnabled[name] = (b.value == 1);
                ~syncTrackPlayer.(name);
            });
        StaticText(rightPane, 26@22).string_("Src").stringColor_(labelColor);
        sourceMenu = PopUpMenu(rightPane, 55@22)
            .items_(["Row", "Col"])
            .value_([\row, \col].indexOf(~hmSource[name]) ? 0)
            .action_({ |m|
                ~hmSource[name] = [\row, \col][m.value];
                patternMenu.items_(patternLabelsFor.(~hmSource[name]));
                patternMenu.value_(patternSymbols.indexOf(~hmPattern[name]) ? 1);
                statusText.string_("Changed (not yet wired to playback).");
            });
        StaticText(rightPane, 30@22).string_("Inst").stringColor_(labelColor);
        instrumentMenu = PopUpMenu(rightPane, 80@22)
            .items_(["fm", "plucking"])
            .value_([\fm, \plucking].indexOf(~hmInstrument[name]) ? 0)
            .action_({ |m|
                ~hmInstrument[name] = [\fm, \plucking][m.value];
                statusText.string_("Changed (not yet wired to playback).");
            });
        rightPane.decorator.nextLine;

// Column headers, directly above Pattern/Pitch/Volume below.
        StaticText(rightPane, 120@16).string_("Dur Pat").stringColor_(labelColor);
        StaticText(rightPane, 120@16).string_("Pit Pat").stringColor_(labelColor);
        StaticText(rightPane, 120@16).string_("Accents").stringColor_(labelColor);
        rightPane.decorator.nextLine;

// ROW 2: Pattern/Pitch/Volume, all the same width (120).
        patternMenu = PopUpMenu(rightPane, 120@22)
            .items_(patternLabelsFor.(~hmSource[name]))
            .value_(patternSymbols.indexOf(~hmPattern[name]) ? 1)
            .action_({ |m|
                ~hmPattern[name] = patternSymbols[m.value];
                updatePatternPercentVisibility.value;
                statusText.string_("Changed (not yet wired to playback).");
            });
        pitchMenu = PopUpMenu(rightPane, 120@22)
            .items_(["Fixed", "Rising at start", "Random"])
            .value_([\fixed, \rising, \random].indexOf(~hmPitchMode[name]) ? 0)
            .action_({ |m|
                ~hmPitchMode[name] = [\fixed, \rising, \random][m.value];
                statusText.string_("Changed (not yet wired to playback).");
            });
        volumeMenu = PopUpMenu(rightPane, 120@22)
            .items_(["Fixed", "Alternate"])
            .value_([\fixed, \alternate].indexOf(~hmVolumeMode[name]) ? 0)
            .action_({ |m|
                ~hmVolumeMode[name] = [\fixed, \alternate][m.value];
                statusText.string_("Changed (not yet wired to playback).");
            });
        rightPane.decorator.nextLine;

// ROW 3: one fixed-width (120), no-decorator sub-view per menu above - see
// CT8guiPercGenerator.scd's own ROW 3 comment for why (RangeSlider needs
// an explicit Rect, not a bare width@height Point, to position/size
// itself correctly inside a parent's auto-layout).
        patternSubView = CompositeView(rightPane, 120@40).background_(trackColor);
        pitchSubView = CompositeView(rightPane, 120@40).background_(trackColor);
        volumeSubView = CompositeView(rightPane, 120@40).background_(trackColor);

        percentSlider = Slider(patternSubView, Rect(2, 2, 116, 18))
            .value_(~hmSplitPercent[name] / 100)
            .action_({ |sl|
                var v = (sl.value * 100).round(1);
                ~hmSplitPercent[name] = v;
                percentReadout.string_(v.asString ++ "%");
                statusText.string_("Changed (not yet wired to playback).");
            });
        percentReadout = StaticText(patternSubView, Rect(2, 21, 116, 16))
            .string_(~hmSplitPercent[name].round(1).asString ++ "%").stringColor_(labelColor);
        updatePatternPercentVisibility = {
            var pattern = ~hmPattern[name];
            var isPercentPattern = #[
                \random8thPercent, \random3rdPercent, \random4to3Percent, \randomSkip
            ].includes(pattern);
            percentSlider.visible_(isPercentPattern);
            percentReadout.visible_(isPercentPattern);
        };
        updatePatternPercentVisibility.value;

// Pitch range, in plain MIDI notes (0-127) - not chord-aware yet, unlike
// BT1/BT2's own Random pitch mode, which already reads ~currentRange
// (CT8harmonySelect.scd). Hooking this up to the shared chord system is
// exactly the kind of "rework" step planned for later.
        pitchRangeSlider = RangeSlider(pitchSubView, Rect(2, 2, 116, 18))
            .lo_(~hmBasePitch[name][0].linlin(0, 127, 0, 1))
            .hi_(~hmBasePitch[name][1].linlin(0, 127, 0, 1));
        pitchRangeReadout = StaticText(pitchSubView, Rect(2, 21, 116, 16)).stringColor_(labelColor);
        updatePitchRangeReadout = {
            pitchRangeReadout.string_(
                ~hmBasePitch[name][0].round(1).asString ++ " - " ++ ~hmBasePitch[name][1].round(1).asString
            );
        };
        pitchRangeSlider.action_({ |rs|
            ~hmBasePitch[name] = [rs.lo.linlin(0, 1, 0, 127), rs.hi.linlin(0, 1, 0, 127)];
            updatePitchRangeReadout.value;
            statusText.string_("Changed (not yet wired to playback).");
        });
        updatePitchRangeReadout.value;

        volumeRangeSlider = RangeSlider(volumeSubView, Rect(2, 2, 116, 18))
            .lo_(~hmVolumeLevels[name][0].linlin(0, 4, 0, 1))
            .hi_(~hmVolumeLevels[name][1].linlin(0, 4, 0, 1));
        volumeRangeReadout = StaticText(volumeSubView, Rect(2, 21, 116, 16)).stringColor_(labelColor);
        updateVolumeRangeReadout = {
            volumeRangeReadout.string_(
                ~hmVolumeLevels[name][0].round(0.01).asString ++ " - " ++ ~hmVolumeLevels[name][1].round(0.01).asString
            );
        };
        volumeRangeSlider.action_({ |rs|
            ~hmVolumeLevels[name] = [rs.lo.linlin(0, 1, 0, 4), rs.hi.linlin(0, 1, 0, 4)];
            updateVolumeRangeReadout.value;
            statusText.string_("Changed (not yet wired to playback).");
        });
        updateVolumeRangeReadout.value;
    };

    ~hmTrackNames.do(makeHmTrackSection);

    Button(~hmGeneratorWindow, 120@26).states_([["Apply now", Color.black, Color(0.65, 0.85, 0.65)]])
        .action_({ applyNow.value });

    Button(~hmGeneratorWindow, 150@26).states_([["Reset to defaults", Color.black, Color(0.85, 0.55, 0.55)]])
        .action_({
            ~hmTrackNames.do(~resetHmConfig);
            ~makeHarmonyMelodyGeneratorWindow.value;
            ~stopPbinds.value;
            ~updatePbinds.value;
            ~restartPbinds.value;
            ~rebuildFlashPatterns.value;
            ~restartFlashPlayers.value;
        });

    ~hmGeneratorWindow.onClose = { ~hmGeneratorWindow = nil };
};

"ClockToy harmony-melody-generator-window GUI functions loaded.".postln;

)
