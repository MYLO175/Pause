# Validation

Pause includes portable logic tests plus iOS unit, persistence, and UI tests.

## Coverage

- Calendar-day, daylight-saving, and time-zone boundaries
- Daily goals, streaks, totals, and dial limits
- Timer pause, recovery, overtime, and duplicate-save handling
- SwiftData store reopening and versioned backup validation/merge
- Bundled audio and notification sound resources
- Main meditation, journal, settings, and manual-entry flows

Run the portable suite with `swift test`. Run the complete app suite in Xcode using the **Pause** scheme and an iOS simulator.

## Recorded results

The latest recorded simulator regression run passed 22 tests on iPhone 17e and iPhone 18 Pro Max simulators. The project record also notes a signed build installed in place and launched on a physical iPhone. These results predate later changes to session ending and journal presentation in this repository snapshot, so they are historical results rather than verification of the current commit.

## Remaining device checks

- Confirm ambient audio and the ending signal behave as intended after locking the screen.
- Verify the experimental silent-session ending path with Silent Mode enabled; the muted background-audio stream has not been verified across device and interruption conditions.
- Interrupt an ambient session with another audio source and confirm the session pauses safely.
- Have a human listener assess sound levels and review the VoiceOver experience.
