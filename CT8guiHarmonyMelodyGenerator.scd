// ============================================================================
// CT8guiHarmonyMelodyGenerator.scd
// CLOCKTOY - HARMONY + MELODY + FX GENERATOR WINDOW (HT1-HT2, MT1-MT2, FXT1-FXT2)
// ============================================================================
//
// Three different kinds of block live in this one window now - the project
// groups its tracks into families by how many notes/what kind of sound each
// one makes (see CT8tracks.scd's MONO TRACK CONFIG section for the full
// naming rationale): Perc (PT1-4, unaffected), mono - one note at a time -
// for the "Note" tracks (BT1/BT2/MT1/MT2), poly - a chord at a time - for
// the Harmony tracks (HT1/HT2), and now fx - one bar-long pulsing texture
// at a time - for FXT1/FXT2:
//
// HT1/HT2 (makePolyTrackSection) are real, wired-up chord-pad tracks,
// per feedback ("going to change the rules for HT1 and HT2") - restricted
// to the two chord-voicing instruments (\droneChord/\shimmerPad), three Dur
// Pat choices, four Pit Pat choices, and no Accents/Volume at all (see
// ~buildPolyPattern's own header comment, CT8tracks.scd, for the full
// design). HT3/HT4 are GONE now, not just untouched - per feedback ("going
// to take HT3 and HT4 and rename them FXT1 and FXT2"), those two track
// slots are now FXT1/FXT2 instead (~trackNames, CT8tracks.scd), a wholly
// different family, not a mere rename - see makeFxTrackSection, below, and
// ~buildFxPattern's own header comment (CT8tracks.scd) for the full design.
// makePolyTrackSection's own `isRestricted` flag is now always true (only
// HT1/HT2 are left in ~polyTrackNames), so its `isRestricted.not` branches
// are dead code, kept rather than ripped out purely to minimize churn.
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
~polyTrackNames = [\HT1, \HT2];
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
~polySourceDefaults = (HT1: \row, HT2: \row);
// HT1/HT2 default to \droneChord now - restricted to \droneChord/
// \shimmerPad only, per feedback (~buildPolyPattern, CT8tracks.scd); HT3/
// HT4 keep \fm, the original skeleton's own default, since they're
// untouched.
~polyInstrumentDefaults = (HT1: \droneChord, HT2: \droneChord);
~polyTrackNames.do { |name|
    var isRestricted = #[\HT1, \HT2].includes(name);
    ~polySource[name] = ~polySource[name] ? ~polySourceDefaults[name];
    ~polyInstrument[name] = ~polyInstrument[name] ? ~polyInstrumentDefaults[name];
// Migrates a value left over from before this split (e.g. HT1 still set to
// \fm from an earlier session) back onto a valid restricted choice, rather
// than silently feeding \fm a Pbind shaped for \droneChord/\shimmerPad's
// note1-N args - same reasoning for Pattern/Pitch below.
    if(isRestricted and: { #[\droneChord, \shimmerPad].includes(~polyInstrument[name]).not }) {
        ~polyInstrument[name] = ~polyInstrumentDefaults[name];
    };
    ~polyPattern[name] = ~polyPattern[name] ? (if(isRestricted) { \firstBeat } { \everyBeat });
    if(isRestricted and: { #[\firstBeat, \halfway, \startOnly].includes(~polyPattern[name]).not }) {
        ~polyPattern[name] = \firstBeat;
    };
    ~polyPitchMode[name] = ~polyPitchMode[name] ? \fixed;
    if(isRestricted and: { #[\fixed, \random, \rising, \falling].includes(~polyPitchMode[name]).not }) {
        ~polyPitchMode[name] = \fixed;
    };
    ~polyVolumeMode[name] = ~polyVolumeMode[name] ? \fixed;
    ~polyVolumeLevels[name] = ~polyVolumeLevels[name] ? [0.2, 0.2];
    ~polyWet[name] = ~polyWet[name] ? 0;
    ~polyLevel[name] = ~polyLevel[name] ? 1;
    ~polySplitPercent[name] = ~polySplitPercent[name] ? 33;
};

// Forcibly resets one track's whole config back to these same original
// defaults - mirrors ~resetPercConfig/~resetMonoConfig (CT8tracks.scd),
// same reason (see either one's own comment). isRestricted-aware for
// Pattern, same as the init loop above.
~resetPolyConfig = { |name|
    var isRestricted = #[\HT1, \HT2].includes(name);
    ~polySource[name] = ~polySourceDefaults[name];
    ~polyInstrument[name] = ~polyInstrumentDefaults[name];
    ~polyPattern[name] = if(isRestricted) { \firstBeat } { \everyBeat };
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
    var statusText, applyNow, makePolyTrackSection, makeMonoTrackSection, makeFxTrackSection;
    var hmGenWidth = 640;
// 1360 -> 1060: each block shrank by 50px (190 -> 140, from the
// Mix/Vol/Dry/Rev sliders going 130 -> 90) - 50 * 6 blocks = 300px saved
// overall. Mirrors CT8guiPercGenerator.scd's own identical change. 1060 ->
// 1124: MT1/MT2's two blocks each grew by 32px (140 -> 172) for the
// COPY TRACK ROW - same +64px total as CT8guiPercGenerator.scd's own
// window got from BT1/BT2. 1124 -> 1316: all six blocks grew by one more
// Send A/Send B target-effect row - HT1-4's own four blocks by 32px each
// (140 -> 172), MT1/MT2's own two by 32px each on top of their already-172
// height (172 -> 204) - "mixer phase" per feedback, same +192px total as
// CT8guiPercGenerator.scd's own window just got. 1316 -> 1346: HT3/HT4's
// own two 172px blocks are gone (FXT1/FXT2 replace them, per feedback -
// "going to take HT3 and HT4 and rename them FXT1 and FXT2"), but FXT1/
// FXT2 get their own two new 172px blocks plus one new section header -
// net +30px. 1346 -> 1410: FXT1/FXT2's own two blocks each grew by 32px
// (172 -> 204) for the new "2nd Vol" row (rumble's second-layer volume,
// per feedback).
    var hmGenHeight = 1410;
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
        var sendAEffectMenu, sendBEffectMenu;
        var onOffButton, sourceMenu, instrumentMenu, patternMenu, pitchMenu, volumeMenu;
        var patternSubView, pitchSubView, volumeSubView;
        var percentSlider, percentReadout, updatePatternPercentVisibility;
        var pitchRangeSlider, pitchRangeReadout, updatePitchRangeReadout;
        var volumeRangeSlider, volumeRangeReadout, updateVolumeRangeReadout;
        var isBuilt = ~trackBuilders[name].notNil;
// HT1/HT2 only - the new, restricted chord-pad rules (~buildPolyPattern's
// own header comment, CT8tracks.scd, has the full design). HT3/HT4 fall
// through to every branch below unchanged from the original skeleton.
        var isRestricted = #[\HT1, \HT2].includes(name);
        var unbuiltColor = Color.new255(255, 165, 0);
// "Changed." for HT1/HT2 (these controls are real now); the original
// "not yet wired to playback" wording stays for HT3/HT4.
        var changedMsg = if(isRestricted) { "Changed." } { "Changed (not yet wired to playback)." };
        var patternSymbols = if(isRestricted) {
            [\firstBeat, \halfway, \startOnly]
        } {
            [
                \firstBeat, \everyBeat, \startOnly,
                \random8thPercent, \random8thLastBar, \random8thLastRowCol,
                \random3rdPercent, \random3rdLastBar, \random3rdLastRowCol,
                \random4to3Percent, \random4to3LastBar, \random4to3LastRowCol,
                \randomSkip
            ]
        };
// "Random" dropped from every label - mirrors CT8guiPercGenerator.scd's own
// patternLabelsFor (kept in sync even though HT3/HT4's own list isn't wired
// to playback yet).
        var patternLabelsFor = { |source|
            if(isRestricted) {
                ["First beat only", "Half way", "First of " ++ (if(source == \row) { "Row" } { "Col" })]
            } {
                [
                    "First beat only", "Every beat",
                    "Start of " ++ (if(source == \row) { "Row" } { "Col" }),
                    "1/8th %", "1/8th (last of bar)", "1/8th (last of row/col)",
                    "1/3 %", "1/3 (last of bar)", "1/3 (last of row/col)",
                    "4/3 %", "4/3 (last of bar)", "4/3 (last of row/col)",
                    "Skip %"
                ]
            }
        };
// \fm/\plucking dropped as choices for HT1/HT2 - restricted to the two
// instruments that actually manage a chord voicing as one unit.
        var instrumentSymbols = if(isRestricted) { [\droneChord, \shimmerPad] } { [\fm, \plucking, \droneChord, \shimmerPad] };
        var instrumentLabels = if(isRestricted) { ["droneChord", "shimmerPad"] } { ["fm", "plucking", "droneChord", "shimmerPad"] };
        var pitchSymbols = if(isRestricted) { [\fixed, \random, \rising, \falling] } { [\fixed, \random, \rising] };
        var pitchLabels = if(isRestricted) { ["Fixed", "Random", "Rising", "Falling"] } { ["Fixed", "Random", "Rising"] };

        trackColor = Color.rand(0.7);
// Shrunk from 190 along with leftPane/rightPane and the Mix/Vol/Dry/Rev
// sliders below (130 -> 90, ~30% shorter, per feedback) - mirrors
// CT8guiPercGenerator.scd's own identical change. 140 -> 172, for the new
// Send A/Send B target row (below, "mixer phase" per feedback). Kept at
// 172 for HT1/HT2 even though they lose the Accents column/row 3 widget -
// just leaves blank space there, simpler than a second height to track.
        trackContainer = CompositeView(~hmGeneratorWindow, 600@172).background_(trackColor);
        ~hmGeneratorWindow.view.decorator.nextLine;

// LEFT PANE: 4 vertical Sliders. Mix/Vol are a tiny built-in reverb tail,
// same role as ~percWet/~percLevel (CT8synths.scd's \wet/\level convention)
// - but not actually connected to any SynthDef yet, since nothing here
// plays a sound of its own. Send A/Send B, unlike Mix/Vol, ARE real now -
// every track's aux sends are keyed by plain track name
// (~sendAAmt[name]/~sendBAmt[name], CT8tracks.scd's own AUX SENDS
// section), not by instrument, so they work for HT1-4 exactly the same
// as every other track family, regardless of Mix/Vol's own separate,
// still-unwired status here.
// x=484, not 6 - see CT8guiPercGenerator.scd's own leftPane comment for
// why (empirically mirrored child positioning). Slightly darker background
// than the rest of the block, built component-wise rather than
// `trackColor * 0.8` - Color has no `*` operator for a plain number, and
// that crashed the whole window build instantly, on the very first track.
        leftPane = CompositeView(trackContainer, Rect(484, 6, 110, 160)).background_(
            Color.new(trackColor.red * 0.8, trackColor.green * 0.8, trackColor.blue * 0.8, trackColor.alpha)
        );
        leftPane.decorator = FlowLayout(leftPane.bounds, 4@4, 4@4);

        StaticText(leftPane, 20@14).string_("Mix").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("Vol").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("SdA").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("SdB").stringColor_(labelColor);
        leftPane.decorator.nextLine;

        mixSlider = Slider(leftPane, 20@90)
            .value_(~polyWet[name])
            .action_({ |sl|
                ~polyWet[name] = sl.value;
                statusText.string_("Changed (live, no rebuild needed).");
            });
        volSlider = Slider(leftPane, 20@90)
            .value_(~polyLevel[name])
            .action_({ |sl|
                ~polyLevel[name] = sl.value;
                statusText.string_("Changed (live, no rebuild needed).");
            });
        sendASlider = Slider(leftPane, 20@90)
            .value_(~sendAAmt[name])
            .action_({ |sl|
                ~sendAAmt[name] = sl.value;
                statusText.string_("Send A updated (live, no rebuild needed).");
            });
        sendBSlider = Slider(leftPane, 20@90)
            .value_(~sendBAmt[name])
            .action_({ |sl|
                ~sendBAmt[name] = sl.value;
                statusText.string_("Send B updated (live, no rebuild needed).");
            });

// RIGHT PANE. Height 160, not 128, to fit the new Send A/Send B
// target-effect row (below).
// x=6, not 124 - mirror image of leftPane's own x, same reason.
        rightPane = CompositeView(trackContainer, Rect(6, 6, 470, 160)).background_(trackColor);
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
                patternMenu.value_(patternSymbols.indexOf(~polyPattern[name]) ? 0);
                statusText.string_(changedMsg);
            });
        StaticText(rightPane, 30@22).string_("Inst").stringColor_(labelColor);
// \droneChord/\shimmerPad are real, wired-up choices for HT1/HT2 now, per
// feedback (~buildPolyPattern, CT8tracks.scd, dispatches on
// ~polyInstrument[name]) - \fm/\plucking dropped entirely for these two
// (restricted to chord-voicing instruments only); HT3/HT4 keep the
// original four-item list, still unwired.
        instrumentMenu = PopUpMenu(rightPane, 80@22)
            .items_(instrumentLabels)
            .value_(instrumentSymbols.indexOf(~polyInstrument[name]) ? 0)
            .action_({ |m|
                ~polyInstrument[name] = instrumentSymbols[m.value];
                statusText.string_(if(isRestricted) { "Changed - applies at next rebuild or Apply now." } { "Changed - not yet applied." });
            });
        rightPane.decorator.nextLine;

// Column headers, directly above Pattern/Pitch/(Volume) below - no Accents
// column at all for HT1/HT2 ("we can remove accents," per feedback).
        StaticText(rightPane, 120@16).string_("Dur Pat").stringColor_(labelColor);
        StaticText(rightPane, 120@16).string_("Pit Pat").stringColor_(labelColor);
        if(isRestricted.not) {
            StaticText(rightPane, 120@16).string_("Accents").stringColor_(labelColor);
        };
        rightPane.decorator.nextLine;

// ROW 2: Pattern/Pitch/(Volume), all the same width (120).
        patternMenu = PopUpMenu(rightPane, 120@22)
            .items_(patternLabelsFor.(~polySource[name]))
            .value_(patternSymbols.indexOf(~polyPattern[name]) ? 0)
            .action_({ |m|
                ~polyPattern[name] = patternSymbols[m.value];
                if(updatePatternPercentVisibility.notNil) { updatePatternPercentVisibility.value };
                statusText.string_(changedMsg);
            });
        pitchMenu = PopUpMenu(rightPane, 120@22)
            .items_(pitchLabels)
            .value_(pitchSymbols.indexOf(~polyPitchMode[name]) ? 0)
            .action_({ |m|
                ~polyPitchMode[name] = pitchSymbols[m.value];
                statusText.string_(changedMsg);
            });
        if(isRestricted.not) {
            volumeMenu = PopUpMenu(rightPane, 120@22)
                .items_(["Fixed", "Alternate"])
                .value_([\fixed, \alternate].indexOf(~polyVolumeMode[name]) ? 0)
                .action_({ |m|
                    ~polyVolumeMode[name] = [\fixed, \alternate][m.value];
                    statusText.string_(changedMsg);
                });
        };
        rightPane.decorator.nextLine;

// ROW 3: one fixed-width (120), no-decorator sub-view per menu above - see
// CT8guiPercGenerator.scd's own ROW 3 comment for why (RangeSlider needs
// an explicit Rect, not a bare width@height Point, to position/size
// itself correctly inside a parent's auto-layout). No Percent sub-control
// for HT1/HT2 at all - none of their three Dur Pat choices are
// percent-driven, unlike HT3/HT4's full thirteen-entry list. No Volume
// sub-view either, for the same reason as the Accents column above.
        patternSubView = CompositeView(rightPane, 120@40).background_(trackColor);
        pitchSubView = CompositeView(rightPane, 120@40).background_(trackColor);
        if(isRestricted.not) {
            volumeSubView = CompositeView(rightPane, 120@40).background_(trackColor);
        };

        if(isRestricted.not) {
            percentSlider = Slider(patternSubView, Rect(2, 2, 116, 18))
                .value_(~polySplitPercent[name] / 100)
                .action_({ |sl|
                    var v = (sl.value * 100).round(1);
                    ~polySplitPercent[name] = v;
                    percentReadout.string_(v.asString ++ "%");
                    statusText.string_(changedMsg);
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
        };

// Pitch range, in plain MIDI notes (0-127) - writes straight into
// ~currentRange[name] (CT8harmonySelect.scd) now, same as bass's own
// Pitch RangeSlider (CT8guiPercGenerator.scd), rather than the separate,
// now-retired ~hmBasePitch this used to be a pure placeholder for. .round,
// not left as the raw linlin float - ~chordRootInRange/~chordNoteInRange's
// own mod-12 matching need whole-number bounds, same reason bass's own
// slider was fixed to round (see CT8tracks.scd/~resetMonoConfig's own
// comment for what happens if it doesn't: Random/Rising silently go
// permanently silent). Kept for both restricted/unrestricted - every Pit
// Pat choice on either side needs it (Rising/Falling's own range-boundary
// wrap included, for HT1/HT2).
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
            statusText.string_(changedMsg);
        });
        updatePitchRangeReadout.value;

        if(isRestricted.not) {
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
                statusText.string_(changedMsg);
            });
            updateVolumeRangeReadout.value;
        };

// Send A/Send B's own target-effect menus - see
// CT8guiPercGenerator.scd's makeTrackSection for the full comment. Real
// and working, unlike Mix/Vol above - see leftPane's own comment.
        rightPane.decorator.nextLine;
        StaticText(rightPane, 54@22).string_("Snd A ->").stringColor_(labelColor);
        sendAEffectMenu = PopUpMenu(rightPane, 100@22)
            .items_(~auxEffectNames)
            .value_(~sendAEffect[name] ? 0)
            .action_({ |m|
                ~sendAEffect[name] = m.value;
                statusText.string_("Send A target updated (live, no rebuild needed).");
            });
        StaticText(rightPane, 54@22).string_("Snd B ->").stringColor_(labelColor);
        sendBEffectMenu = PopUpMenu(rightPane, 100@22)
            .items_(~auxEffectNames)
            .value_(~sendBEffect[name] ? 0)
            .action_({ |m|
                ~sendBEffect[name] = m.value;
                statusText.string_("Send B target updated (live, no rebuild needed).");
            });
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
        var sendAEffectMenu, sendBEffectMenu;
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
// 140 -> 172, for the COPY TRACK ROW as a fourth row in rightPane; 172 ->
// 204, for the Send A/Send B target row (below, "mixer phase" per
// feedback) as a fifth - see CT8guiPercGenerator.scd's own copy of this
// same block for the full comment.
        trackContainer = CompositeView(~hmGeneratorWindow, 600@204).background_(trackColor);
        ~hmGeneratorWindow.view.decorator.nextLine;

        leftPane = CompositeView(trackContainer, Rect(484, 6, 110, 192)).background_(
            Color.new(trackColor.red * 0.8, trackColor.green * 0.8, trackColor.blue * 0.8, trackColor.alpha)
        );
        leftPane.decorator = FlowLayout(leftPane.bounds, 4@4, 4@4);

        StaticText(leftPane, 20@14).string_("Mix").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("Vol").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("SdA").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("SdB").stringColor_(labelColor);
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
        sendASlider = Slider(leftPane, 20@90)
            .value_(~sendAAmt[name])
            .action_({ |sl|
                ~sendAAmt[name] = sl.value;
                statusText.string_("Send A updated (live, no rebuild needed).");
            });
        sendBSlider = Slider(leftPane, 20@90)
            .value_(~sendBAmt[name])
            .action_({ |sl|
                ~sendBAmt[name] = sl.value;
                statusText.string_("Send B updated (live, no rebuild needed).");
            });

        rightPane = CompositeView(trackContainer, Rect(6, 6, 470, 192)).background_(trackColor);
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

// Send A/Send B's own target-effect menus - see
// CT8guiPercGenerator.scd's makeTrackSection for the full comment.
        rightPane.decorator.nextLine;
        StaticText(rightPane, 54@22).string_("Snd A ->").stringColor_(labelColor);
        sendAEffectMenu = PopUpMenu(rightPane, 100@22)
            .items_(~auxEffectNames)
            .value_(~sendAEffect[name] ? 0)
            .action_({ |m|
                ~sendAEffect[name] = m.value;
                statusText.string_("Send A target updated (live, no rebuild needed).");
            });
        StaticText(rightPane, 54@22).string_("Snd B ->").stringColor_(labelColor);
        sendBEffectMenu = PopUpMenu(rightPane, 100@22)
            .items_(~auxEffectNames)
            .value_(~sendBEffect[name] ? 0)
            .action_({ |m|
                ~sendBEffect[name] = m.value;
                statusText.string_("Send B target updated (live, no rebuild needed).");
            });
    };

    [\MT1, \MT2].do(makeMonoTrackSection);

    StaticText(~hmGeneratorWindow, 600@24).string_("FX GENERATOR (FXT1-FXT2)")
        .font_(Font("Arial", 14, true)).stringColor_(Color.white);
    ~hmGeneratorWindow.view.decorator.nextLine;

// FXT1/FXT2's own block - the new bar-long-pulsing-texture family, per
// feedback ("going to take HT3 and HT4 and rename them FXT1 and FXT2").
// Simpler than HT1/HT2's own block in one way still: no Pit Pat (neither
// \rumble nor \noise exposes a pitched, chord-aware arg the way
// \droneChord/\shimmerPad do) and no Accents (~fxLevel/~fxWet, in
// leftPane, are already live volume controls, same role Mix/Vol play
// everywhere else - no separate amp slider needed). Source (Row/Col) IS
// here now, alongside all three Dur Pat choices (First beat only/First of
// row-col/Every beat) - per feedback ("have the dur pat choices be first
// beat only, first of row/col, every beat") - see ~buildFxPattern's own
// comment, CT8tracks.scd, for how the irregular row/col case is actually
// driven. "2nd Vol" (row 4) is new too, per feedback - only actually
// audible when Instrument is \rumble (~buildFxPattern's own second-layer
// design, CT8tracks.scd), but shown regardless of which instrument is
// selected, same as every other control here.
    makeFxTrackSection = { |name|
        var trackContainer, trackColor, labelColor = Color.black;
        var leftPane, rightPane;
        var mixSlider, volSlider, sendASlider, sendBSlider;
        var sendAEffectMenu, sendBEffectMenu;
        var onOffButton, sourceMenu, instrumentMenu, patternMenu;
        var percentSlider, percentReadout, layerLevelSlider, layerLevelReadout;
        var instrumentSymbols = [\rumble, \noise];
        var instrumentLabels = ["rumble", "noise"];
        var patternSymbols = [\firstBeat, \startOnly, \everyBeat];
// Label tracks whichever Source is selected, same "Start of Row/Col"
// convention every other family's own Dur Pat menu already uses.
        var patternLabelsFor = { |source|
            [
                "First beat only",
                "First of " ++ (if(source == \row) { "Row" } { "Col" }),
                "Every beat"
            ]
        };

        trackColor = Color.rand(0.7);
// 172 -> 204, for the new "2nd Vol" row (rumble's second-layer volume,
// per feedback) - same +32px-per-new-row convention every other block in
// this project already uses.
        trackContainer = CompositeView(~hmGeneratorWindow, 600@204).background_(trackColor);
        ~hmGeneratorWindow.view.decorator.nextLine;

        leftPane = CompositeView(trackContainer, Rect(484, 6, 110, 192)).background_(
            Color.new(trackColor.red * 0.8, trackColor.green * 0.8, trackColor.blue * 0.8, trackColor.alpha)
        );
        leftPane.decorator = FlowLayout(leftPane.bounds, 4@4, 4@4);

        StaticText(leftPane, 20@14).string_("Mix").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("Vol").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("SdA").stringColor_(labelColor);
        StaticText(leftPane, 20@14).string_("SdB").stringColor_(labelColor);
        leftPane.decorator.nextLine;

        mixSlider = Slider(leftPane, 20@90)
            .value_(~fxWet[name])
            .action_({ |sl|
                ~fxWet[name] = sl.value;
                statusText.string_("Changed (live, no rebuild needed).");
            });
        volSlider = Slider(leftPane, 20@90)
            .value_(~fxLevel[name])
            .action_({ |sl|
                ~fxLevel[name] = sl.value;
                statusText.string_("Changed (live, no rebuild needed).");
            });
        sendASlider = Slider(leftPane, 20@90)
            .value_(~sendAAmt[name])
            .action_({ |sl|
                ~sendAAmt[name] = sl.value;
                statusText.string_("Send A updated (live, no rebuild needed).");
            });
        sendBSlider = Slider(leftPane, 20@90)
            .value_(~sendBAmt[name])
            .action_({ |sl|
                ~sendBAmt[name] = sl.value;
                statusText.string_("Send B updated (live, no rebuild needed).");
            });

        rightPane = CompositeView(trackContainer, Rect(6, 6, 470, 192)).background_(trackColor);
        rightPane.decorator = FlowLayout(rightPane.bounds, 6@6, 4@4);

        StaticText(rightPane, 48@22).string_(name.asString)
            .font_(Font("Arial", 13, true)).stringColor_(labelColor);
        onOffButton = Button(rightPane, 24@24)
            .states_([[" ", Color.black, Color.red], [" ", Color.black, Color.green]])
            .value_(if(~trackEnabled[name] == false) { 0 } { 1 })
            .action_({ |b|
                ~trackEnabled[name] = (b.value == 1);
                ~syncTrackPlayer.(name);
            });
        StaticText(rightPane, 26@22).string_("Src").stringColor_(labelColor);
        sourceMenu = PopUpMenu(rightPane, 55@22)
            .items_(["Row", "Col"])
            .value_([\row, \col].indexOf(~fxSource[name]) ? 0)
            .action_({ |m|
                ~fxSource[name] = [\row, \col][m.value];
                patternMenu.items_(patternLabelsFor.(~fxSource[name]));
                patternMenu.value_(patternSymbols.indexOf(~fxPattern[name]) ? 0);
                statusText.string_("Changed - applies at next rebuild or Apply now.");
            });
        StaticText(rightPane, 30@22).string_("Inst").stringColor_(labelColor);
        instrumentMenu = PopUpMenu(rightPane, 80@22)
            .items_(instrumentLabels)
            .value_(instrumentSymbols.indexOf(~fxInstrument[name]) ? 0)
            .action_({ |m|
                ~fxInstrument[name] = instrumentSymbols[m.value];
                statusText.string_("Changed - applies at next rebuild or Apply now.");
            });
        rightPane.decorator.nextLine;

        StaticText(rightPane, 70@22).string_("Dur Pat").stringColor_(labelColor);
        patternMenu = PopUpMenu(rightPane, 120@22)
            .items_(patternLabelsFor.(~fxSource[name]))
            .value_(patternSymbols.indexOf(~fxPattern[name]) ? 0)
            .action_({ |m|
                ~fxPattern[name] = patternSymbols[m.value];
                statusText.string_("Changed - applies at next rebuild or Apply now.");
            });
        rightPane.decorator.nextLine;

        StaticText(rightPane, 70@22).string_("Pulse %").stringColor_(labelColor);
        percentSlider = Slider(rightPane, 120@22)
            .value_(~fxPulsePercent[name] / 100)
            .action_({ |sl|
                var v = (sl.value * 100).round(1);
                ~fxPulsePercent[name] = v;
                percentReadout.string_(v.asString ++ "%");
                statusText.string_("Changed - applies at next rebuild or Apply now.");
            });
        percentReadout = StaticText(rightPane, 50@22)
            .string_(~fxPulsePercent[name].round(1).asString ++ "%").stringColor_(labelColor);
        rightPane.decorator.nextLine;

// Only actually audible when Instrument is \rumble (~buildFxPattern's own
// comment, CT8tracks.scd, has the full "second layer" design) - shown
// regardless of which instrument is selected, same as every other
// control here, rather than hiding/disabling it when it wouldn't apply.
        StaticText(rightPane, 70@22).string_("2nd Vol").stringColor_(labelColor);
        layerLevelSlider = Slider(rightPane, 120@22)
            .value_(~fxLayerLevel[name])
            .action_({ |sl|
                ~fxLayerLevel[name] = sl.value;
                layerLevelReadout.string_(sl.value.round(0.01).asString);
                statusText.string_("Changed (live, no rebuild needed).");
            });
        layerLevelReadout = StaticText(rightPane, 50@22)
            .string_(~fxLayerLevel[name].round(0.01).asString).stringColor_(labelColor);
        rightPane.decorator.nextLine;

        StaticText(rightPane, 54@22).string_("Snd A ->").stringColor_(labelColor);
        sendAEffectMenu = PopUpMenu(rightPane, 100@22)
            .items_(~auxEffectNames)
            .value_(~sendAEffect[name] ? 0)
            .action_({ |m|
                ~sendAEffect[name] = m.value;
                statusText.string_("Send A target updated (live, no rebuild needed).");
            });
        StaticText(rightPane, 54@22).string_("Snd B ->").stringColor_(labelColor);
        sendBEffectMenu = PopUpMenu(rightPane, 100@22)
            .items_(~auxEffectNames)
            .value_(~sendBEffect[name] ? 0)
            .action_({ |m|
                ~sendBEffect[name] = m.value;
                statusText.string_("Send B target updated (live, no rebuild needed).");
            });
    };

    ~fxTrackNames.do(makeFxTrackSection);

    Button(~hmGeneratorWindow, 120@26).states_([["Apply now", Color.black, Color(0.65, 0.85, 0.65)]])
        .action_({ applyNow.value });

    Button(~hmGeneratorWindow, 150@26).states_([["Reset to defaults", Color.black, Color(0.85, 0.55, 0.55)]])
        .action_({
            ~polyTrackNames.do(~resetPolyConfig);
            [\MT1, \MT2].do(~resetMonoConfig);
            ~fxTrackNames.do(~resetFxConfig);
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
