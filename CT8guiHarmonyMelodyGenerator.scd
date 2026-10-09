// ============================================================================
// CT8guiHarmonyMelodyGenerator.scd
// CLOCKTOY - HARMONY + MELODY GENERATOR WINDOW (HT1-HT4, MT1-MT2) - SKELETON
// ============================================================================
//
// Two different kinds of block live in this one window, per feedback - the
// project now groups its tracks into three families by how many notes each
// one ever sounds at once (see CT8tracks.scd's MONO TRACK CONFIG section
// for the full naming rationale): Perc (PT1-4, unaffected), mono - one note
// at a time - for the "Note" tracks (BT1/BT2/MT1/MT2), and poly - a chord
// at a time - for the Harmony tracks (HT1-4):
//
// HT1-4 (makePolyTrackSection) are still the original skeleton - deliberately
// NOT yet wired into ~buildPolyPattern (CT8tracks.scd; HT1 is still its
// own bespoke, chord-based builder, untouched by this file). Every control
// here besides on/off reads and writes a placeholder global (~polyX, below)
// that doesn't affect playback yet - this part of the window's job for now
// is just to exist with the right shape. The on/off button IS real,
// though: same ~trackEnabled[name]/~syncTrackPlayer every other window's
// on/off button already uses, and shows orange (not red/green, same
// convention CT8guiAdjust.scd's own buttons use) for all four of HT1-4,
// which have no builder yet.
//
// MT1/MT2 (makeMonoTrackSection) are real, full Note tracks now - no
// longer a melody-specific builder of their own (~buildMelodyPattern is
// gone) or a separate ~polyX config - BT1/BT2/MT1/MT2 are four
// interchangeable Note tracks sharing one structure, one builder
// (~buildMonoTrackPattern), and one set of config globals (~monoX,
// CT8tracks.scd's MONO TRACK CONFIG section), differing only in which
// options each one happens to be set to. makeMonoTrackSection is therefore a
// near-exact copy of CT8guiPercGenerator.scd's own makeMonoTrackSection -
// same controls, same ~monoX[name] globals, just parented to THIS window
// instead, since MT1/MT2's blocks stay physically in the Harmony + Melody
// Generator window (per feedback, "I do not want to change ... the
// layouts") even though they're no longer conceptually "melody" tracks -
// the TRACK names (BT1/BT2/MT1/MT2) and this window's own layout stay put;
// only the globals'/functions' own names changed, from ~bassX/
// ~buildBassTrackPattern to ~monoX/~buildMonoTrackPattern. MT2 defaults to
// on (~trackEnabled[\MT2], CT8main.scd) and to Col scan (MT1 defaults to
// Row) - per feedback.
//
// Moved here from the Clock Toy Adjust window (CT8guiAdjust.scd), which
// used to have HT1-4/MT1-2's on/off buttons in its own "Harm"/"Mel" rows -
// only MT3/MT4 are left there now.
//


(

// MT1/MT2 dropped from this list - they're real Note tracks now, sharing
// ~monoX config (CT8tracks.scd) instead of this file's own placeholder
// ~polyX - see this file's own header comment.
~polyTrackNames = [\HT1, \HT2, \HT3, \HT4];
~polySource = ~polySource ? ();
~polyInstrument = ~polyInstrument ? ();
~polyPattern = ~polyPattern ? ();
~polyPitchMode = ~polyPitchMode ? ();
~polyVolumeMode = ~polyVolumeMode ? ();
~polyVolumeLevels = ~polyVolumeLevels ? ();
~polyWet = ~polyWet ? ();
~polyLevel = ~polyLevel ? ();
~polySplitPercent = ~polySplitPercent ? ();
// HT1-4 default to Row scan - the same identity ~buildPolyPattern (HT1)
// already has today, even though this Source menu doesn't drive it yet.
~polySourceDefaults = (HT1: \row, HT2: \row, HT3: \row, HT4: \row);
// \fm for every one of these four, matching HT1's real instrument today.
~polyInstrumentDefaults = (HT1: \fm, HT2: \fm, HT3: \fm, HT4: \fm);
~polyTrackNames.do { |name|
    ~polySource[name] = ~polySource[name] ? ~polySourceDefaults[name];
    ~polyInstrument[name] = ~polyInstrument[name] ? ~polyInstrumentDefaults[name];
    ~polyPattern[name] = ~polyPattern[name] ? \everyBeat;
    ~polyPitchMode[name] = ~polyPitchMode[name] ? \fixed;
    ~polyVolumeMode[name] = ~polyVolumeMode[name] ? \fixed;
    ~polyVolumeLevels[name] = ~polyVolumeLevels[name] ? [0.2, 0.2];
    ~polyWet[name] = ~polyWet[name] ? 0;
    ~polyLevel[name] = ~polyLevel[name] ? 1;
    ~polySplitPercent[name] = ~polySplitPercent[name] ? 33;
};

// Forcibly resets one track's whole config back to these same original
// defaults - mirrors ~resetPercConfig/~resetMonoConfig (CT8tracks.scd),
// same reason (see either one's own comment).
~resetPolyConfig = { |name|
    ~polySource[name] = ~polySourceDefaults[name];
    ~polyInstrument[name] = ~polyInstrumentDefaults[name];
    ~polyPattern[name] = \everyBeat;
    ~polyPitchMode[name] = \fixed;
    ~polyVolumeMode[name] = \fixed;
    ~polyVolumeLevels[name] = [0.2, 0.2];
    ~polyWet[name] = 0;
    ~polyLevel[name] = 1;
    ~polySplitPercent[name] = 33;
// Also resets ~currentRange[name] (CT8harmonySelect.scd) back to its own
// original default - mirrors ~resetMonoConfig's identical addition
// (CT8tracks.scd) for the same reason: this window's Pitch RangeSlider
// writes straight into ~currentRange[name] now (not a separate
// ~hmBasePitch any more), so this button needs to be able to recover it.
    ~currentRange[name] = [60, 96];
};

~makeHarmonyMelodyGeneratorWindow = {
    var statusText, applyNow, makePolyTrackSection, makeMonoTrackSection;
    var hmGenWidth = 640;
// 1360 -> 1060: each block shrank by 50px (190 -> 140, from the
// Mix/Vol/Dry/Rev sliders going 130 -> 90) - 50 * 6 blocks = 300px saved
// overall. Mirrors CT8guiPercGenerator.scd's own identical change. 1060 ->
// 1124: MT1/MT2's two blocks each grew by 32px (140 -> 172) for the new
// COPY TRACK ROW - same +64px total as CT8guiPercGenerator.scd's own
// window got from BT1/BT2.
    var hmGenHeight = 1124;
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
        .string_("HT1-4 on/off only; MT1/MT2 are real Note tracks, same as BT1/BT2.")
        .stringColor_(Color(0.7, 0.85, 0.75));
    ~hmGeneratorWindow.view.decorator.nextLine;

// Builds one track's full control block - identical shape to
// CT8guiPercGenerator.scd's makeTrackSection (see that file for the
// RangeSlider/explicit-Rect notes this copies verbatim), wired to ~polyX[name]
// instead of ~percX[name].
    makePolyTrackSection = { |name|
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
            .value_(~polyWet[name])
            .action_({ |sl|
                ~polyWet[name] = sl.value;
                statusText.string_("Changed (not yet wired to playback).");
            });
        volSlider = Slider(leftPane, 20@90)
            .value_(~polyLevel[name])
            .action_({ |sl|
                ~polyLevel[name] = sl.value;
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
            .value_([\row, \col].indexOf(~polySource[name]) ? 0)
            .action_({ |m|
                ~polySource[name] = [\row, \col][m.value];
                patternMenu.items_(patternLabelsFor.(~polySource[name]));
                patternMenu.value_(patternSymbols.indexOf(~polyPattern[name]) ? 1);
                statusText.string_("Changed (not yet wired to playback).");
            });
        StaticText(rightPane, 30@22).string_("Inst").stringColor_(labelColor);
        instrumentMenu = PopUpMenu(rightPane, 80@22)
            .items_(["fm", "plucking"])
            .value_([\fm, \plucking].indexOf(~polyInstrument[name]) ? 0)
            .action_({ |m|
                ~polyInstrument[name] = [\fm, \plucking][m.value];
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
            .items_(patternLabelsFor.(~polySource[name]))
            .value_(patternSymbols.indexOf(~polyPattern[name]) ? 1)
            .action_({ |m|
                ~polyPattern[name] = patternSymbols[m.value];
                updatePatternPercentVisibility.value;
                statusText.string_("Changed (not yet wired to playback).");
            });
        pitchMenu = PopUpMenu(rightPane, 120@22)
            .items_(["Fixed", "Random", "Rising"])
            .value_([\fixed, \random, \rising].indexOf(~polyPitchMode[name]) ? 0)
            .action_({ |m|
                ~polyPitchMode[name] = [\fixed, \random, \rising][m.value];
                statusText.string_("Changed (not yet wired to playback).");
            });
        volumeMenu = PopUpMenu(rightPane, 120@22)
            .items_(["Fixed", "Alternate"])
            .value_([\fixed, \alternate].indexOf(~polyVolumeMode[name]) ? 0)
            .action_({ |m|
                ~polyVolumeMode[name] = [\fixed, \alternate][m.value];
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
            .value_(~polySplitPercent[name] / 100)
            .action_({ |sl|
                var v = (sl.value * 100).round(1);
                ~polySplitPercent[name] = v;
                percentReadout.string_(v.asString ++ "%");
                statusText.string_("Changed (not yet wired to playback).");
            });
        percentReadout = StaticText(patternSubView, Rect(2, 21, 116, 16))
            .string_(~polySplitPercent[name].round(1).asString ++ "%").stringColor_(labelColor);
        updatePatternPercentVisibility = {
            var pattern = ~polyPattern[name];
            var isPercentPattern = #[
                \random8thPercent, \random3rdPercent, \random4to3Percent, \randomSkip
            ].includes(pattern);
            percentSlider.visible_(isPercentPattern);
            percentReadout.visible_(isPercentPattern);
        };
        updatePatternPercentVisibility.value;

// Pitch range, in plain MIDI notes (0-127) - writes straight into
// ~currentRange[name] (CT8harmonySelect.scd) now, same as bass's own
// Pitch RangeSlider (CT8guiPercGenerator.scd), rather than the separate,
// now-retired ~hmBasePitch this used to be a pure placeholder for. .round,
// not left as the raw linlin float - ~chordRootInRange/~chordNoteInRange's
// own mod-12 matching need whole-number bounds, same reason bass's own
// slider was fixed to round (see CT8tracks.scd/~resetMonoConfig's own
// comment for what happens if it doesn't: Random/Rising silently go
// permanently silent).
        pitchRangeSlider = RangeSlider(pitchSubView, Rect(2, 2, 116, 18))
            .lo_(~currentRange[name][0].linlin(0, 127, 0, 1))
            .hi_(~currentRange[name][1].linlin(0, 127, 0, 1));
        pitchRangeReadout = StaticText(pitchSubView, Rect(2, 21, 116, 16)).stringColor_(labelColor);
        updatePitchRangeReadout = {
            pitchRangeReadout.string_(
                ~currentRange[name][0].round(1).asString ++ " - " ++ ~currentRange[name][1].round(1).asString
            );
        };
        pitchRangeSlider.action_({ |rs|
            ~currentRange[name] = [
                rs.lo.linlin(0, 1, 0, 127).round, rs.hi.linlin(0, 1, 0, 127).round
            ];
            updatePitchRangeReadout.value;
            statusText.string_("Changed (not yet wired to playback).");
        });
        updatePitchRangeReadout.value;

        volumeRangeSlider = RangeSlider(volumeSubView, Rect(2, 2, 116, 18))
            .lo_(~polyVolumeLevels[name][0].linlin(0, 4, 0, 1))
            .hi_(~polyVolumeLevels[name][1].linlin(0, 4, 0, 1));
        volumeRangeReadout = StaticText(volumeSubView, Rect(2, 21, 116, 16)).stringColor_(labelColor);
        updateVolumeRangeReadout = {
            volumeRangeReadout.string_(
                ~polyVolumeLevels[name][0].round(0.01).asString ++ " - " ++ ~polyVolumeLevels[name][1].round(0.01).asString
            );
        };
        volumeRangeSlider.action_({ |rs|
            ~polyVolumeLevels[name] = [rs.lo.linlin(0, 1, 0, 4), rs.hi.linlin(0, 1, 0, 4)];
            updateVolumeRangeReadout.value;
            statusText.string_("Changed (not yet wired to playback).");
        });
        updateVolumeRangeReadout.value;
    };

    ~polyTrackNames.do(makePolyTrackSection);

// MT1/MT2's own block - a near-exact copy of CT8guiPercGenerator.scd's
// makeMonoTrackSection (see this file's own header comment for why it's
// duplicated here rather than shared some other way), parented to
// ~hmGeneratorWindow instead of ~percGeneratorWindow, otherwise reading/
// writing the exact same ~monoX[name] globals (CT8tracks.scd) BT1/BT2 do.
    makeMonoTrackSection = { |name|
        var trackContainer, trackColor, labelColor = Color.black;
        var leftPane, rightPane;
        var mixSlider, volSlider, sendASlider, sendBSlider;
        var onOffButton, sourceMenu, instrumentMenu, patternMenu, pitchMenu, volumeMenu;
        var patternSubView, pitchSubView, volumeSubView;
        var percentSlider, percentReadout, updatePatternPercentVisibility;
        var pitchRangeSlider, pitchRangeReadout, updatePitchRangeReadout;
        var volumeRangeSlider, volumeRangeReadout, updateVolumeRangeReadout;
// COPY TRACK ROW - see the TRACK COPY section, CT8tracks.scd, for what
// each of these three widgets actually drives (~copyTrackButtonPressed/
// ~copyPlaybackMenuAction/~copyStopPlaybackPressed); refreshCopyUi is this
// track's own redraw closure, registered into ~copyButtonRefreshers so
// ~refreshAllCopyButtons can reach it from anywhere, including from
// BT1/BT2's own copy of this same block in a different window entirely
// (CT8guiPercGenerator.scd).
        var copyButton, copyMenu, copyStopButton, refreshCopyUi;
        var copyChoiceSymbols = [\nextBar, \nextRowCol, \nextBeat];
        var copyMenuLabelsFor = { |source|
            ["Next Bar", "Next " ++ (if(source == \row) { "Row" } { "Col" }), "Next Beat"]
        };
        var patternSymbols = [
            \everyBeat, \startOnly,
            \random8thPercent, \random8thLastBar, \random8thLastRowCol,
            \random3rdPercent, \random3rdLastBar, \random3rdLastRowCol,
            \random4to3Percent, \random4to3LastBar, \random4to3LastRowCol,
            \randomSkip
        ];
        var patternLabelsFor = { |source|
            [
                "Every beat",
                "Start of " ++ (if(source == \row) { "Row" } { "Col" }),
                "1/8th %", "1/8th (last of bar)", "1/8th (last of row/col)",
                "1/3 %", "1/3 (last of bar)", "1/3 (last of row/col)",
                "4/3 %", "4/3 (last of bar)", "4/3 (last of row/col)",
                "Skip %"
            ]
        };
// Pitch menu - normally 8 flat entries, but per feedback the three Arp
// modes each grow into their own sub-variants whenever Dur Pat is one of
// the 1/8th patterns (splitCount == 2 in ~buildMonoTrackPattern,
// CT8tracks.scd - Up/Down/Ran, 9 entries total) or one of the 1/3rd
// patterns (splitCount == 3 - Repeat/Up/Down/Lop, 12 entries total) -
// those are the only two places a split's later note(s) can differ from
// its first. `pitchSymbols` (the var updatePitchMenuItems keeps pointed at
// whichever list is current) is what pitchMenu's own .action_, below,
// actually indexes into - not a fixed literal - so it always matches
// whatever's currently on screen.
        var basePitchSymbols = [
            \fixed, \random, \rising, \falling, \looping,
            \arpRising, \arpFalling, \arpLooping
        ];
        var basePitchLabels = [
            "Fixed", "Random", "Rising", "Falling", "Looping",
            "Arp Rising", "Arp Falling", "Arp Looping"
        ];
        var pitchSymbols18 = [
            \fixed, \random, \rising, \falling, \looping,
            \arpRisingUp, \arpRisingDown, \arpRisingRan,
            \arpFallingUp, \arpFallingDown, \arpFallingRan,
            \arpLoopingUp, \arpLoopingDown, \arpLoopingRan
        ];
        var pitchLabels18 = [
            "Fixed", "Random", "Rising", "Falling", "Looping",
            "Arp Rising Up", "Arp Rising Down", "Arp Rising Ran",
            "Arp Falling Up", "Arp Falling Down", "Arp Falling Ran",
            "Arp Looping Up", "Arp Looping Down", "Arp Looping Ran"
        ];
// The 1/3rd family's own four sub-variants, per feedback - "very similar
// to 1/8 BUT arp rising will repeat the note[: Repeat is its own explicit
// choice, not just a fallback,] and instead of moving by tones/semitones
// where possible[, falling back to a] repeat when not possible[, that's
// what Up/Down/Lop still do, same as 1/8]." See ~buildMonoTrackPattern's
// own splitPitches comment, CT8tracks.scd, for exactly what Repeat/Up/
// Down/Lop each do across a triplet's 3 notes.
        var pitchSymbols13 = [
            \fixed, \random, \rising, \falling, \looping,
            \arpRising3rdRepeat, \arpRising3rdUp, \arpRising3rdDown, \arpRising3rdLop,
            \arpFalling3rdRepeat, \arpFalling3rdUp, \arpFalling3rdDown, \arpFalling3rdLop,
            \arpLooping3rdRepeat, \arpLooping3rdUp, \arpLooping3rdDown, \arpLooping3rdLop
        ];
        var pitchLabels13 = [
            "Fixed", "Random", "Rising", "Falling", "Looping",
            "Arp Rising Repeat", "Arp Rising Up", "Arp Rising Down", "Arp Rising Lop",
            "Arp Falling Repeat", "Arp Falling Up", "Arp Falling Down", "Arp Falling Lop",
            "Arp Looping Repeat", "Arp Looping Up", "Arp Looping Down", "Arp Looping Lop"
        ];
// Collapsing OUT of either extended list (Dur Pat no longer 1/8th- or
// 1/3rd-based) strips a mode like \arpRisingUp or \arpRising3rdLop back
// down to its bare \arpRising, since the base list has none of those
// sub-variant entries to show it as; expanding INTO the 1/8th list
// defaults a bare mode to its own Up variant (first of its three), and
// expanding INTO the 1/3rd list defaults it to Repeat (first of its four,
// and the closest match to the old, pre-this-feature default behavior)
// instead - rather than leaving ~monoPitchMode[name] pointed at a symbol
// the newly-visible list doesn't contain.
        var baseArpOf = { |sym|
            switch(sym,
                \arpRisingUp, { \arpRising }, \arpRisingDown, { \arpRising }, \arpRisingRan, { \arpRising },
                \arpFallingUp, { \arpFalling }, \arpFallingDown, { \arpFalling }, \arpFallingRan, { \arpFalling },
                \arpLoopingUp, { \arpLooping }, \arpLoopingDown, { \arpLooping }, \arpLoopingRan, { \arpLooping },
                \arpRising3rdRepeat, { \arpRising }, \arpRising3rdUp, { \arpRising },
                \arpRising3rdDown, { \arpRising }, \arpRising3rdLop, { \arpRising },
                \arpFalling3rdRepeat, { \arpFalling }, \arpFalling3rdUp, { \arpFalling },
                \arpFalling3rdDown, { \arpFalling }, \arpFalling3rdLop, { \arpFalling },
                \arpLooping3rdRepeat, { \arpLooping }, \arpLooping3rdUp, { \arpLooping },
                \arpLooping3rdDown, { \arpLooping }, \arpLooping3rdLop, { \arpLooping },
                { sym }
            )
        };
        var upVariantOf = { |sym|
            switch(sym,
                \arpRising, { \arpRisingUp },
                \arpFalling, { \arpFallingUp },
                \arpLooping, { \arpLoopingUp },
                { sym }
            )
        };
        var repeatVariantOf = { |sym|
            switch(sym,
                \arpRising, { \arpRising3rdRepeat },
                \arpFalling, { \arpFalling3rdRepeat },
                \arpLooping, { \arpLooping3rdRepeat },
                { sym }
            )
        };
        var pitchSymbols;
        var updatePitchMenuItems;

        trackColor = Color.rand(0.7);
// 140 -> 172, to fit the new COPY TRACK ROW (below) as a fourth row in
// rightPane - see CT8guiPercGenerator.scd's own copy of this same block
// for the full comment.
        trackContainer = CompositeView(~hmGeneratorWindow, 600@172).background_(trackColor);
        ~hmGeneratorWindow.view.decorator.nextLine;

        leftPane = CompositeView(trackContainer, Rect(484, 6, 110, 160)).background_(
            Color.new(trackColor.red * 0.8, trackColor.green * 0.8, trackColor.blue * 0.8, trackColor.alpha)
        );
        leftPane.decorator = FlowLayout(leftPane.bounds, 4@4, 4@4);

        StaticText(leftPane, 20@14).string_("Mix").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("Vol").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("Dry").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("Rev").stringColor_(labelColor);
        leftPane.decorator.nextLine;

        mixSlider = Slider(leftPane, 20@90)
            .value_(~monoWet[name])
            .action_({ |sl|
                ~monoWet[name] = sl.value;
                statusText.string_("Mix updated (live, no rebuild needed).");
            });
        volSlider = Slider(leftPane, 20@90)
            .value_(~monoLevel[name])
            .action_({ |sl|
                ~monoLevel[name] = sl.value;
                statusText.string_("Vol updated (live, no rebuild needed).");
            });
        sendASlider = Slider(leftPane, 20@90);
        sendBSlider = Slider(leftPane, 20@90);

        rightPane = CompositeView(trackContainer, Rect(6, 6, 470, 160)).background_(trackColor);
        rightPane.decorator = FlowLayout(rightPane.bounds, 6@6, 4@4);

        StaticText(rightPane, 48@22).string_(name.asString)
            .font_(Font("Arial", 13, true)).stringColor_(labelColor);
        onOffButton = Button(rightPane, 24@24)
            .states_([
                [" ", Color.black, Color.red],
                [" ", Color.black, Color.green]
            ])
            .value_(if(~trackEnabled[name] == false) { 0 } { 1 })
            .action_({ |b|
                ~trackEnabled[name] = (b.value == 1);
                ~syncTrackPlayer.(name);
            });
        StaticText(rightPane, 26@22).string_("Src").stringColor_(labelColor);
        sourceMenu = PopUpMenu(rightPane, 55@22)
            .items_(["Row", "Col"])
            .value_([\row, \col].indexOf(~monoSource[name]) ? 0)
            .action_({ |m|
                ~monoSource[name] = [\row, \col][m.value];
                patternMenu.items_(patternLabelsFor.(~monoSource[name]));
                patternMenu.value_(patternSymbols.indexOf(~monoPattern[name]) ? 0);
                copyMenu.items_(copyMenuLabelsFor.(~monoSource[name]));
                statusText.string_("Changed - not yet applied.");
            });
        StaticText(rightPane, 30@22).string_("Inst").stringColor_(labelColor);
        instrumentMenu = PopUpMenu(rightPane, 80@22)
            .items_(["fm", "plucking"])
            .value_([\fm, \plucking].indexOf(~monoInstrument[name]) ? 0)
            .action_({ |m|
                ~monoInstrument[name] = [\fm, \plucking][m.value];
                statusText.string_("Changed - not yet applied.");
            });
        rightPane.decorator.nextLine;

        StaticText(rightPane, 120@16).string_("Dur Pat").stringColor_(labelColor);
        StaticText(rightPane, 120@16).string_("Pit Pat").stringColor_(labelColor);
        StaticText(rightPane, 120@16).string_("Accents").stringColor_(labelColor);
        rightPane.decorator.nextLine;

        patternMenu = PopUpMenu(rightPane, 120@22)
            .items_(patternLabelsFor.(~monoSource[name]))
            .value_(patternSymbols.indexOf(~monoPattern[name]) ? 0)
            .action_({ |m|
                ~monoPattern[name] = patternSymbols[m.value];
                updatePatternPercentVisibility.value;
                updatePitchMenuItems.value;
                statusText.string_("Changed - not yet applied.");
            });
        pitchMenu = PopUpMenu(rightPane, 120@22);
        volumeMenu = PopUpMenu(rightPane, 120@22)
            .items_(["Fixed", "Alternate"])
            .value_([\fixed, \alternate].indexOf(~monoVolumeMode[name]) ? 0)
            .action_({ |m|
                ~monoVolumeMode[name] = [\fixed, \alternate][m.value];
                statusText.string_("Changed - not yet applied.");
            });
        rightPane.decorator.nextLine;

        patternSubView = CompositeView(rightPane, 120@40).background_(trackColor);
        pitchSubView = CompositeView(rightPane, 120@40).background_(trackColor);
        volumeSubView = CompositeView(rightPane, 120@40).background_(trackColor);

        percentSlider = Slider(patternSubView, Rect(2, 2, 116, 18))
            .value_(~monoSplitPercent[name] / 100)
            .action_({ |sl|
                var v = (sl.value * 100).round(1);
                ~monoSplitPercent[name] = v;
                percentReadout.string_(v.asString ++ "%");
                statusText.string_("Changed - not yet applied.");
            });
        percentReadout = StaticText(patternSubView, Rect(2, 21, 116, 16))
            .string_(~monoSplitPercent[name].round(1).asString ++ "%").stringColor_(labelColor);
        updatePatternPercentVisibility = {
            var pattern = ~monoPattern[name];
            var isPercentPattern = #[
                \random8thPercent, \random3rdPercent, \random4to3Percent, \randomSkip
            ].includes(pattern);
            percentSlider.visible_(isPercentPattern);
            percentReadout.visible_(isPercentPattern);
        };
        updatePatternPercentVisibility.value;

// Rebuilds pitchMenu's own items_/value_ to whichever of basePitchSymbols/
// pitchSymbols18/pitchSymbols13 fits the CURRENT Dur Pat (see that trio's
// own comment, above, for why), renormalizing ~monoPitchMode[name] across
// the switch via baseArpOf/upVariantOf/repeatVariantOf so it's never left
// pointing at a symbol the now-visible list doesn't contain - always
// collapsing to the bare mode first (baseArpOf handles symbols from
// EITHER extended list) before re-expanding into whichever list is now
// showing, so jumping directly between a 1/8th and a 1/3rd pattern
// normalizes correctly too, not just toggling to/from the base 8. Called
// once here at build time, then again from patternMenu's own .action_,
// above, every time Dur Pat changes.
        updatePitchMenuItems = {
            var is1_8 = #[
                \random8thPercent, \random8thLastBar, \random8thLastRowCol
            ].includes(~monoPattern[name]);
            var is1_3 = #[
                \random3rdPercent, \random3rdLastBar, \random3rdLastRowCol
            ].includes(~monoPattern[name]);
            var mode = baseArpOf.(~monoPitchMode[name]);
            if(is1_8) {
                mode = upVariantOf.(mode);
                pitchSymbols = pitchSymbols18;
                pitchMenu.items_(pitchLabels18);
            } {
                if(is1_3) {
                    mode = repeatVariantOf.(mode);
                    pitchSymbols = pitchSymbols13;
                    pitchMenu.items_(pitchLabels13);
                } {
                    pitchSymbols = basePitchSymbols;
                    pitchMenu.items_(basePitchLabels);
                };
            };
            ~monoPitchMode[name] = mode;
            pitchMenu.value_(pitchSymbols.indexOf(mode) ? 0);
        };
        updatePitchMenuItems.value;
        pitchMenu.action_({ |m|
            ~monoPitchMode[name] = pitchSymbols[m.value];
            statusText.string_("Changed - not yet applied.");
        });

        pitchRangeSlider = RangeSlider(pitchSubView, Rect(2, 2, 116, 18))
            .lo_(~currentRange[name][0].linlin(0, 127, 0, 1))
            .hi_(~currentRange[name][1].linlin(0, 127, 0, 1));
        pitchRangeReadout = StaticText(pitchSubView, Rect(2, 21, 116, 16)).stringColor_(labelColor);
        updatePitchRangeReadout = {
            pitchRangeReadout.string_(
                ~currentRange[name][0].round(1).asString ++ " - " ++ ~currentRange[name][1].round(1).asString
            );
        };
        pitchRangeSlider.action_({ |rs|
            ~currentRange[name] = [
                rs.lo.linlin(0, 1, 0, 127).round, rs.hi.linlin(0, 1, 0, 127).round
            ];
            updatePitchRangeReadout.value;
            statusText.string_("Changed - not yet applied.");
        });
        updatePitchRangeReadout.value;

        volumeRangeSlider = RangeSlider(volumeSubView, Rect(2, 2, 116, 18))
            .lo_(~monoVolumeLevels[name][0].linlin(0, 4, 0, 1))
            .hi_(~monoVolumeLevels[name][1].linlin(0, 4, 0, 1));
        volumeRangeReadout = StaticText(volumeSubView, Rect(2, 21, 116, 16)).stringColor_(labelColor);
        updateVolumeRangeReadout = {
            volumeRangeReadout.string_(
                ~monoVolumeLevels[name][0].round(0.01).asString ++ " - " ++ ~monoVolumeLevels[name][1].round(0.01).asString
            );
        };
        volumeRangeSlider.action_({ |rs|
            ~monoVolumeLevels[name] = [rs.lo.linlin(0, 1, 0, 4), rs.hi.linlin(0, 1, 0, 4)];
            updateVolumeRangeReadout.value;
            statusText.string_("Changed - not yet applied.");
        });
        updateVolumeRangeReadout.value;

// COPY TRACK ROW - see CT8guiPercGenerator.scd's own copy of this same
// block (BT1/BT2) for the full comment; identical here, just wired to
// MT1/MT2 through the same shared globals/functions (CT8tracks.scd).
        rightPane.decorator.nextLine;
        copyButton = Button(rightPane, 85@24)
            .action_({
                if(~copyButtonLabelFor.(name) == "Copy Track") {
                    ~copyTrackButtonPressed.(name);
                } {
                    ~copyPlayButtonPressed.(name);
                };
            });
        StaticText(rightPane, 54@22).string_("Playback").stringColor_(labelColor);
        copyMenu = PopUpMenu(rightPane, 90@22)
            .items_(copyMenuLabelsFor.(~monoSource[name]))
            .action_({ |m|
                ~copyPlaybackMenuAction.(name, ~monoSource[name], copyChoiceSymbols[m.value]);
            });
        copyStopButton = Button(rightPane, 95@24)
            .states_([["Stop Playback", Color.black, Color.grey(0.8)]])
            .action_({ ~copyStopPlaybackPressed.(name) });

        refreshCopyUi = {
            var label = ~copyButtonLabelFor.(name);
            var state = ~copyButtonStateFor.(name);
            copyButton.states_([
                [label, Color.black, Color.grey(0.6)],
                [label, Color.black, Color.new(1.0, 0.55, 0.0)],
                [label, Color.black, Color.green]
            ]);
            copyButton.value_(switch(state, \idle, { 0 }, \copying, { 1 }, \ready, { 2 }));
            copyMenu.enabled_(~copyPlayStartArmed[name]);
            copyStopButton.enabled_(~copyPlaying[name] or: { ~copyPlayStartArmed[name] });
        };
        ~copyButtonRefreshers[name] = refreshCopyUi;
        refreshCopyUi.value;
    };

    [\MT1, \MT2].do(makeMonoTrackSection);

    Button(~hmGeneratorWindow, 120@26).states_([["Apply now", Color.black, Color(0.65, 0.85, 0.65)]])
        .action_({ applyNow.value });

    Button(~hmGeneratorWindow, 150@26).states_([["Reset to defaults", Color.black, Color(0.85, 0.55, 0.55)]])
        .action_({
            ~polyTrackNames.do(~resetPolyConfig);
            [\MT1, \MT2].do(~resetMonoConfig);
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
