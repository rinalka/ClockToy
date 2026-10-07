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
// Each track's on/off button (red/green square, no label - the title
// StaticText beside it already names the track) sits right next to that
// track's name, rather than in the separate Clock Toy Adjust window -
// PT1-4/BT1-2 are the only tracks controlled from here, so their on/off
// belongs here too, beside everything else about them.
//
// Each track's block is split into two side-by-side panes (same overall
// block width/height as before - just divided differently now, rather than
// one flat stack of rows):
//
// LEFT PANE (25% of the block's width) - this instrument's own per-voice
// controls, as 4 vertical Sliders: Mix/Vol (the existing Wet/Level
// controls, ~percWet[name]/~percLevel[name] or ~bassWet[name]/
// ~bassLevel[name] - that instrument's own tiny built-in ~allpassWash tail,
// see CT8synths.scd - renamed/relabeled, not rewired; still read live via
// Pfunc, no rebuild needed) plus two more, Send A/Send B, that don't do
// anything yet - plain Sliders with no backing global, placeholders for a
// future multi-output-channel send feature.
//
// RIGHT PANE (75% of the block's width) - everything else, in three rows:
//   Row 1: Title (the track name) + the on/off square + Source
//          (~percSource[name]/~bassSource[name]: Row or Col scan) +
//          Instrument (~percInstrument[name]: \baseD/\cym/\hat/\kick;
//          ~bassInstrument[name]: \fm/\plucking).
//   Row 2: Pattern/Pitch/Volume menus, all on one row (previously spread
//          across three separate rows, each with its own sub-controls
//          directly beside it - the sub-controls moved below, into their
//          own row, so all three menus can sit together here). Pattern is
//          the same flat list it always was, just with "Random" dropped
//          from every label and a 4/3 "merge 4 beats into 3" family added
//          (First beat only - percussion only/Every beat/Start of Row-or-
//          Col/the six 1/8th-1/3rd split variants/the three 4/3 merge
//          variants/Skip %); Pitch is Fixed/Rising at start/Random for
//          percussion (its own separate Hz-based scheme); Fixed/Random/
//          Rising for bass (chord/scale-based - see ~buildBassTrackPattern's
//          own comment, CT8tracks.scd); Volume is Fixed/Alternate for
//          both.
//   Row 3: one sub-control per menu above, in three same-width columns so
//          each lines up under its own menu:
//            - Under Pattern: a Percent Slider (visible for every "%"-
//              labeled entry - the two 1/8th-1/3rd split percents, the 4/3
//              merge percent, and Skip % - what fraction of beats split/
//              merge/skip, same value/meaning as before, just a Slider now
//              instead of a NumberBox).
//            - Under Pitch: a single dual-handle RangeSlider, replacing
//              Pitch's old per-mode widget set (one box/two boxes/four
//              boxes for Fixed/Rising/Random) - ~percBasePitch[name]/
//              ~currentRange[name] (bass) is now always a [lo, hi] pair,
//              with each Pitch mode just reading it differently (Fixed =
//              hi; Random = anywhere in [lo, hi]; Rising, percussion only =
//              climbs lo toward hi - see ~buildPercPattern's own comment
//              for the exact rule) - so the SAME slider stays visible
//              across every mode, nothing to show/hide.
//            - Under Volume: the same idea, one dual-handle RangeSlider
//              for ~percVolumeLevels[name]/~bassVolumeLevels[name] (now
//              always [lo, hi], 0-4), replacing the old Fixed-Slider-or-
//              two-Alternate-Sliders switch - Fixed reads hi, Alternate
//              alternates hi/lo.
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
// screen still can't show all of it at once. 1360 -> 1060: each block
// shrank by 50px (190 -> 140, from the Mix/Vol/Dry/Rev sliders going 130
// -> 90) - 50 * 6 blocks = 300px saved overall.
    var percGenHeight = 1060;
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

// Builds one track's full control block - two side-by-side panes (left
// 25%/right 75% of the block's width - see this file's header comment),
// wired to that track name's own globals. Returns nothing - every control
// captures `name` in its own action closure, so no caller-side bookkeeping
// is needed.
    makeTrackSection = { |name|
        var trackContainer, trackColor, labelColor = Color.black;
        var leftPane, rightPane;
        var mixSlider, volSlider, sendASlider, sendBSlider;
        var onOffButton, sourceMenu, instrumentMenu, patternMenu, pitchMenu, volumeMenu;
        var patternSubView, pitchSubView, volumeSubView;
        var percentSlider, percentReadout, updatePatternPercentVisibility;
        var pitchRangeSlider, pitchRangeReadout, updatePitchRangeReadout;
        var volumeRangeSlider, volumeRangeReadout, updateVolumeRangeReadout;
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
            \random4to3Percent, \random4to3LastBar, \random4to3LastRowCol,
            \randomSkip
        ];
// "Random" dropped from every label (per feedback) - every percent-driven
// entry's label ends in "%" instead (isPercentPattern, below, shows the
// Percent sub-control for exactly those); the deterministic "(last of
// bar)"/"(last of row/col)" entries don't, since there's no percent to set.
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

// Each track's whole block sits on its own randomly-rolled muted color -
// same Color.rand(0.7) convention CT8fakeData.scd uses for its Actions
// plotter panel - re-rolled fresh every time this window is (re)built, not
// persisted. leftPane/rightPane/the row-3 sub-views all share it rather
// than the window's own dark background, so they blend into the block
// instead of showing up as contrasting holes.
        trackColor = Color.rand(0.7);
// Shrunk from 190 along with leftPane/rightPane and the Mix/Vol/Dry/Rev
// sliders below (130 -> 90, ~30% shorter, per feedback) - the freed-up
// height let every one of the six track blocks (and so the window itself)
// get considerably shorter too.
        trackContainer = CompositeView(~percGeneratorWindow, 600@140).background_(trackColor);
// No decorator on trackContainer itself any more - leftPane/rightPane,
// below, get explicit Rects instead of a bare width@height Point, same
// fix RangeSlider needed: letting trackContainer's own FlowLayout
// auto-place these two ended up swapping their left-right order (leftPane
// landing on the right, rightPane on the left) for reasons that weren't
// worth chasing further once an explicit, unambiguous Rect each sidestepped
// it entirely. margin 6, gap 8 between them, matching the values this file
// used to pass to FlowLayout here.
        ~percGeneratorWindow.view.decorator.nextLine;

// LEFT PANE (~110 of the block's 600 width): 4 vertical Sliders. Mix/Vol are
// this instrument's own tiny built-in ~allpassWash tail
// (~percWet[name]/~percLevel[name], \wet/\level args on \baseD/\cym/\hat/
// \kick - see CT8synths.scd), not the shared ~clockRev send every other
// track uses (PT1-4 never reached that anyway - see ~buildPercPattern's
// \fx comment, below) - read/written live via Pfunc, same as before, just
// renamed (was Wet/Level) and moved here. Dry/Rev don't do anything yet -
// plain Sliders with no backing global, placeholders for a future
// multi-output-channel send feature (eventual dry-signal/reverb-signal
// sends to separate hardware outputs).
// Rect's x here is 484, not 6 - empirically, whatever this Qt build does
// with nested CompositeView positioning displays a child's Rect mirrored
// left-right within its parent (supplying x=6 rendered at the FAR RIGHT
// instead of the left, and rightPane's x=124 rendered at the true left -
// exactly backwards). 484 = 600 (trackContainer width) - 110 (this pane's
// own width) - 6 (the left margin actually wanted) - i.e. the mirror image
// of the position that reads as "x=6" everywhere else in this project.
// Slightly darker than the rest of the block so this pane's own sliders
// read as visually distinct from rightPane, per feedback - built
// component-wise rather than `trackColor * 0.8`, which crashes (Color has
// no `*` operator for a plain number) and was taking down the whole
// window build the instant it ran, on literally the first track.
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
            .value_(~percWet[name])
            .action_({ |sl|
                ~percWet[name] = sl.value;
                statusText.string_("Mix updated (live, no rebuild needed).");
            });
        volSlider = Slider(leftPane, 20@90)
            .value_(~percLevel[name])
            .action_({ |sl|
                ~percLevel[name] = sl.value;
                statusText.string_("Vol updated (live, no rebuild needed).");
            });
        sendASlider = Slider(leftPane, 20@90);
        sendBSlider = Slider(leftPane, 20@90);

// RIGHT PANE (~470 of the block's 600 width): title/on-off/Source/Instrument on
// row 1, Pattern/Pitch/Volume menus together on row 2, and each menu's own
// sub-control in a matching-width column on row 3.
// x=6, not 124 - the mirror image of leftPane's own x, for the same
// reason - see leftPane's comment, just above.
        rightPane = CompositeView(trackContainer, Rect(6, 6, 470, 128)).background_(trackColor);
        rightPane.decorator = FlowLayout(rightPane.bounds, 6@6, 4@4);

// ROW 1: on/off is a plain red/green square now - no label inside it any
// more, since the title beside it already names the track (same track
// always has a builder - ~buildPercPattern - so unlike the even older
// CT8guiAdjust.scd buttons this replaced, there's no orange/unbuilt case
// to handle either).
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
            .value_([\row, \col].indexOf(~percSource[name]) ? 0)
            .action_({ |m|
                ~percSource[name] = [\row, \col][m.value];
// Relabel the Pattern menu's "Start of Row/Col" entry to match, without
// disturbing the track's actual selected pattern.
                patternMenu.items_(patternLabelsFor.(~percSource[name]));
                patternMenu.value_(patternSymbols.indexOf(~percPattern[name]) ? 1);
                statusText.string_("Changed - not yet applied.");
            });
// indexOf against the exact same [\baseD, \cym, \hat, \kick] symbol array
// the action below maps back from, not an .asString comparison - see this
// file's own history for why that distinction matters (CLAUDE.md).
        StaticText(rightPane, 30@22).string_("Inst").stringColor_(labelColor);
        instrumentMenu = PopUpMenu(rightPane, 80@22)
            .items_(["baseD", "cym", "hat", "kick"])
            .value_([\baseD, \cym, \hat, \kick].indexOf(~percInstrument[name]) ? 2)
            .action_({ |m|
                ~percInstrument[name] = [\baseD, \cym, \hat, \kick][m.value];
                statusText.string_("Changed - not yet applied.");
            });
        rightPane.decorator.nextLine;

// Column headers, directly above Pattern/Pitch/Volume below - "Dur Pat"
// (duration pattern)/"Pit Pat" (pitch pattern)/"Accents" (volume/amp
// accenting), per feedback - each exactly 120 wide, same as its own
// menu/sub-view below, so the columns all line up.
        StaticText(rightPane, 120@16).string_("Dur Pat").stringColor_(labelColor);
        StaticText(rightPane, 120@16).string_("Pit Pat").stringColor_(labelColor);
        StaticText(rightPane, 120@16).string_("Accents").stringColor_(labelColor);
        rightPane.decorator.nextLine;

// ROW 2: Pattern/Pitch/Volume, all on one row, all the same width now (per
// feedback) - long Pattern item text (e.g. "Random 1/8th (last of
// row/col)") just clips at this width rather than needing abbreviating;
// same deliberate trade-off for row 3's percent/range sliders below, also
// this width now. Each menu's own sub-widget moved below, into row 3, so
// there's room for all three menus together here.
        patternMenu = PopUpMenu(rightPane, 120@22)
            .items_(patternLabelsFor.(~percSource[name]))
            .value_(patternSymbols.indexOf(~percPattern[name]) ? 1)
            .action_({ |m|
                ~percPattern[name] = patternSymbols[m.value];
                updatePatternPercentVisibility.value;
                statusText.string_("Changed - not yet applied.");
            });
        pitchMenu = PopUpMenu(rightPane, 120@22)
            .items_(["Fixed", "Rising at start", "Random"])
            .value_([\fixed, \rising, \random].indexOf(~percPitchMode[name]) ? 0)
            .action_({ |m|
                ~percPitchMode[name] = [\fixed, \rising, \random][m.value];
                statusText.string_("Changed - not yet applied.");
            });
        volumeMenu = PopUpMenu(rightPane, 120@22)
            .items_(["Fixed", "Alternate"])
            .value_([\fixed, \alternate].indexOf(~percVolumeMode[name]) ? 0)
            .action_({ |m|
                ~percVolumeMode[name] = [\fixed, \alternate][m.value];
                statusText.string_("Changed - not yet applied.");
            });
        rightPane.decorator.nextLine;

// ROW 3: one fixed-width sub-view per menu above, each exactly as wide
// (120) so the rows visually line up. All three deliberately have NO
// decorator - confirmed by testing that RangeSlider does not position/size
// itself correctly when handed a bare width@height Point for a parent's
// layout manager to place automatically; it needs an explicit Rect
// (position AND size) to render right - so the Percent Slider gets the
// same explicit-Rect treatment here too, purely so all three row-3 sliders
// end up genuinely the same width (per feedback), not because the Percent
// Slider itself had the RangeSlider problem.
        patternSubView = CompositeView(rightPane, 120@40).background_(trackColor);
        pitchSubView = CompositeView(rightPane, 120@40).background_(trackColor);
        volumeSubView = CompositeView(rightPane, 120@40).background_(trackColor);

// Under Pattern: a Percent Slider - matters for every "%"-labeled pattern
// (\random8thPercent/\random3rdPercent/\random4to3Percent/\randomSkip - see
// isPercentPattern below), same value/meaning as the old Percent NumberBox,
// just a Slider now (0-1 native, linlin'd to 0-100). The "%" sign is folded
// into the readout text rather than its own separate label, since there's
// no longer room for both beside a full-width slider. \randomSkip now
// shares this same slider/global rather than a fixed, non-adjustable ~1/4.
        percentSlider = Slider(patternSubView, Rect(2, 2, 116, 18))
            .value_(~percSplitPercent[name] / 100)
            .action_({ |sl|
                var v = (sl.value * 100).round(1);
                ~percSplitPercent[name] = v;
                percentReadout.string_(v.asString ++ "%");
                statusText.string_("Changed - not yet applied.");
            });
        percentReadout = StaticText(patternSubView, Rect(2, 21, 116, 16))
            .string_(~percSplitPercent[name].round(1).asString ++ "%").stringColor_(labelColor);
        updatePatternPercentVisibility = {
            var pattern = ~percPattern[name];
            var isPercentPattern = #[
                \random8thPercent, \random3rdPercent, \random4to3Percent, \randomSkip
            ].includes(pattern);
            percentSlider.visible_(isPercentPattern);
            percentReadout.visible_(isPercentPattern);
        };
        updatePatternPercentVisibility.value;

// Under Pitch: one dual-handle RangeSlider, replacing the old per-mode
// widget set (one box/two boxes/four boxes for Fixed/Rising/Random).
// ~percBasePitch[name] is now always [lo, hi] - each Pitch mode just reads
// it differently (Fixed = hi; Random = anywhere in [lo, hi]; Rising =
// climbs lo toward hi - see ~buildPercPattern's own comment,
// CT8tracks.scd), so this ONE slider stays visible across every mode -
// nothing to show/hide here any more. Mapped 20-8000 Hz, the same hard
// bounds the old Pitch NumberBoxes' clipLo/clipHi used.
        pitchRangeSlider = RangeSlider(pitchSubView, Rect(2, 2, 116, 18))
            .lo_(~percBasePitch[name][0].linlin(20, 8000, 0, 1))
            .hi_(~percBasePitch[name][1].linlin(20, 8000, 0, 1));
        pitchRangeReadout = StaticText(pitchSubView, Rect(2, 21, 116, 16)).stringColor_(labelColor);
        updatePitchRangeReadout = {
            pitchRangeReadout.string_(
                ~percBasePitch[name][0].round(1).asString ++ " - " ++ ~percBasePitch[name][1].round(1).asString
            );
        };
        pitchRangeSlider.action_({ |rs|
            ~percBasePitch[name] = [rs.lo.linlin(0, 1, 20, 8000), rs.hi.linlin(0, 1, 20, 8000)];
            updatePitchRangeReadout.value;
            statusText.string_("Changed - not yet applied.");
        });
        updatePitchRangeReadout.value;

// Under Volume: the same idea - ~percVolumeLevels[name] is now always
// [lo, hi], 0-4 (same linlin mapping the old Volume Sliders used),
// replacing the old Fixed-Slider-or-two-Alternate-Sliders switch (and the
// fixed-size-placeholder-container fix that switch needed - see
// CLAUDE.md). Fixed reads hi; Alternate alternates hi/lo.
        volumeRangeSlider = RangeSlider(volumeSubView, Rect(2, 2, 116, 18))
            .lo_(~percVolumeLevels[name][0].linlin(0, 4, 0, 1))
            .hi_(~percVolumeLevels[name][1].linlin(0, 4, 0, 1));
        volumeRangeReadout = StaticText(volumeSubView, Rect(2, 21, 116, 16)).stringColor_(labelColor);
        updateVolumeRangeReadout = {
            volumeRangeReadout.string_(
                ~percVolumeLevels[name][0].round(0.01).asString ++ " - " ++ ~percVolumeLevels[name][1].round(0.01).asString
            );
        };
        volumeRangeSlider.action_({ |rs|
            ~percVolumeLevels[name] = [rs.lo.linlin(0, 1, 0, 4), rs.hi.linlin(0, 1, 0, 4)];
            updateVolumeRangeReadout.value;
            statusText.string_("Changed - not yet applied.");
        });
        updateVolumeRangeReadout.value;
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
        var leftPane, rightPane;
        var mixSlider, volSlider, sendASlider, sendBSlider;
        var onOffButton, sourceMenu, instrumentMenu, patternMenu, pitchMenu, volumeMenu;
        var patternSubView, pitchSubView, volumeSubView;
        var percentSlider, percentReadout, updatePatternPercentVisibility;
        var pitchRangeSlider, pitchRangeReadout, updatePitchRangeReadout;
        var volumeRangeSlider, volumeRangeReadout, updateVolumeRangeReadout;
// Same flattened Pattern list as percussion's patternSymbols/patternLabelsFor
// (see makeTrackSection, above), minus \firstBeat - not a useful choice for
// a bass part, per feedback.
        var patternSymbols = [
            \everyBeat, \startOnly,
            \random8thPercent, \random8thLastBar, \random8thLastRowCol,
            \random3rdPercent, \random3rdLastBar, \random3rdLastRowCol,
            \random4to3Percent, \random4to3LastBar, \random4to3LastRowCol,
            \randomSkip
        ];
// "Random" dropped from every label - see makeTrackSection's own comment,
// above, for why.
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

        trackColor = Color.rand(0.7);
// Shrunk from 190 along with leftPane/rightPane and the Mix/Vol/Dry/Rev
// sliders below (130 -> 90, ~30% shorter, per feedback) - the freed-up
// height let every one of the six track blocks (and so the window itself)
// get considerably shorter too.
        trackContainer = CompositeView(~percGeneratorWindow, 600@140).background_(trackColor);
// No decorator on trackContainer itself - see makeTrackSection's own
// comment for why leftPane/rightPane get explicit Rects instead.
        ~percGeneratorWindow.view.decorator.nextLine;

// LEFT PANE - identical layout/role to makeTrackSection's own left pane,
// just wired to ~bassWet[name]/~bassLevel[name] instead.
// Rect's x here is 484, not 6 - empirically, whatever this Qt build does
// with nested CompositeView positioning displays a child's Rect mirrored
// left-right within its parent (supplying x=6 rendered at the FAR RIGHT
// instead of the left, and rightPane's x=124 rendered at the true left -
// exactly backwards). 484 = 600 (trackContainer width) - 110 (this pane's
// own width) - 6 (the left margin actually wanted) - i.e. the mirror image
// of the position that reads as "x=6" everywhere else in this project.
// Slightly darker than the rest of the block so this pane's own sliders
// read as visually distinct from rightPane, per feedback - built
// component-wise rather than `trackColor * 0.8`, which crashes (Color has
// no `*` operator for a plain number) and was taking down the whole
// window build the instant it ran, on literally the first track.
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
            .value_(~bassWet[name])
            .action_({ |sl|
                ~bassWet[name] = sl.value;
                statusText.string_("Mix updated (live, no rebuild needed).");
            });
        volSlider = Slider(leftPane, 20@90)
            .value_(~bassLevel[name])
            .action_({ |sl|
                ~bassLevel[name] = sl.value;
                statusText.string_("Vol updated (live, no rebuild needed).");
            });
        sendASlider = Slider(leftPane, 20@90);
        sendBSlider = Slider(leftPane, 20@90);

// RIGHT PANE - same three-row shape as makeTrackSection's own right pane.
// x=6, not 124 - the mirror image of leftPane's own x, for the same
// reason - see leftPane's comment, just above.
        rightPane = CompositeView(trackContainer, Rect(6, 6, 470, 128)).background_(trackColor);
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
            .value_([\row, \col].indexOf(~bassSource[name]) ? 0)
            .action_({ |m|
                ~bassSource[name] = [\row, \col][m.value];
                patternMenu.items_(patternLabelsFor.(~bassSource[name]));
                patternMenu.value_(patternSymbols.indexOf(~bassPattern[name]) ? 0);
                statusText.string_("Changed - not yet applied.");
            });
        StaticText(rightPane, 30@22).string_("Inst").stringColor_(labelColor);
        instrumentMenu = PopUpMenu(rightPane, 80@22)
            .items_(["fm", "plucking"])
            .value_([\fm, \plucking].indexOf(~bassInstrument[name]) ? 0)
            .action_({ |m|
                ~bassInstrument[name] = [\fm, \plucking][m.value];
                statusText.string_("Changed - not yet applied.");
            });
        rightPane.decorator.nextLine;

// Column headers - see makeTrackSection's own comment for why these three
// and the menus/sub-views below are all 120 wide.
        StaticText(rightPane, 120@16).string_("Dur Pat").stringColor_(labelColor);
        StaticText(rightPane, 120@16).string_("Pit Pat").stringColor_(labelColor);
        StaticText(rightPane, 120@16).string_("Accents").stringColor_(labelColor);
        rightPane.decorator.nextLine;

        patternMenu = PopUpMenu(rightPane, 120@22)
            .items_(patternLabelsFor.(~bassSource[name]))
            .value_(patternSymbols.indexOf(~bassPattern[name]) ? 0)
            .action_({ |m|
                ~bassPattern[name] = patternSymbols[m.value];
                updatePatternPercentVisibility.value;
                statusText.string_("Changed - not yet applied.");
            });
        pitchMenu = PopUpMenu(rightPane, 120@22)
            .items_(["Fixed", "Random", "Rising"])
            .value_([\fixed, \random, \rising].indexOf(~bassPitchMode[name]) ? 0)
            .action_({ |m|
                ~bassPitchMode[name] = [\fixed, \random, \rising][m.value];
                statusText.string_("Changed - not yet applied.");
            });
        volumeMenu = PopUpMenu(rightPane, 120@22)
            .items_(["Fixed", "Alternate"])
            .value_([\fixed, \alternate].indexOf(~bassVolumeMode[name]) ? 0)
            .action_({ |m|
                ~bassVolumeMode[name] = [\fixed, \alternate][m.value];
                statusText.string_("Changed - not yet applied.");
            });
        rightPane.decorator.nextLine;

        patternSubView = CompositeView(rightPane, 120@40).background_(trackColor);
        pitchSubView = CompositeView(rightPane, 120@40).background_(trackColor);
        volumeSubView = CompositeView(rightPane, 120@40).background_(trackColor);

        percentSlider = Slider(patternSubView, Rect(2, 2, 116, 18))
            .value_(~bassSplitPercent[name] / 100)
            .action_({ |sl|
                var v = (sl.value * 100).round(1);
                ~bassSplitPercent[name] = v;
                percentReadout.string_(v.asString ++ "%");
                statusText.string_("Changed - not yet applied.");
            });
        percentReadout = StaticText(patternSubView, Rect(2, 21, 116, 16))
            .string_(~bassSplitPercent[name].round(1).asString ++ "%").stringColor_(labelColor);
        updatePatternPercentVisibility = {
            var pattern = ~bassPattern[name];
            var isPercentPattern = #[
                \random8thPercent, \random3rdPercent, \random4to3Percent, \randomSkip
            ].includes(pattern);
            percentSlider.visible_(isPercentPattern);
            percentReadout.visible_(isPercentPattern);
        };
        updatePatternPercentVisibility.value;

// Under Pitch: one dual-handle RangeSlider, writing straight into
// ~currentRange[name] (CT8harmonySelect.scd) rather than a separate
// ~bassBasePitch - Fixed reads hi; Random picks anywhere in [lo, hi] via
// ~chordNoteInRange. Mapped 0-127, the full MIDI note range (not just
// "below middle C" - dragging the handles is now how you set that, rather
// than a fixed hardcoded ceiling).
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
// .round here, not left as the raw linlin float - ~chordNoteInRange's own
// mod-12 matching (CT8harmonySelect.scd) needs whole-number bounds or it
// silently returns nil for every Random-mode pick (candidates always comes
// back empty), which then kills this track's Pbind entirely. MIDI notes
// are whole numbers anyway, so this is also just more correct.
            ~currentRange[name] = [
                rs.lo.linlin(0, 1, 0, 127).round, rs.hi.linlin(0, 1, 0, 127).round
            ];
            updatePitchRangeReadout.value;
            statusText.string_("Changed - not yet applied.");
        });
        updatePitchRangeReadout.value;

// Under Volume: identical to makeTrackSection's own Volume RangeSlider,
// just wired to ~bassVolumeLevels[name].
        volumeRangeSlider = RangeSlider(volumeSubView, Rect(2, 2, 116, 18))
            .lo_(~bassVolumeLevels[name][0].linlin(0, 4, 0, 1))
            .hi_(~bassVolumeLevels[name][1].linlin(0, 4, 0, 1));
        volumeRangeReadout = StaticText(volumeSubView, Rect(2, 21, 116, 16)).stringColor_(labelColor);
        updateVolumeRangeReadout = {
            volumeRangeReadout.string_(
                ~bassVolumeLevels[name][0].round(0.01).asString ++ " - " ++ ~bassVolumeLevels[name][1].round(0.01).asString
            );
        };
        volumeRangeSlider.action_({ |rs|
            ~bassVolumeLevels[name] = [rs.lo.linlin(0, 1, 0, 4), rs.hi.linlin(0, 1, 0, 4)];
            updateVolumeRangeReadout.value;
            statusText.string_("Changed - not yet applied.");
        });
        updateVolumeRangeReadout.value;
    };

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
