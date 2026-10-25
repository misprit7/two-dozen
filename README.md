# two_dozen

The 24 game, generalized: combine cards with + − × ÷ to hit a target.

- **Classic mode** (target 24, four cards, use all of them): puzzles are ordered by
  the empirically measured average solve times from www.4nums.com (`lib/games.dart`).
- **Any target**: whole numbers, negatives, fractions (`7/3`) or decimals.
- **Random targets** in four tiers (easy → expert).
- **4–9 cards**, optionally without having to use them all.
- Solution hints, skip, undo/redo, timer, dark mode and theme colours.

## Difficulty model

`lib/engine/solver.dart` enumerates every distinct way to make the target (dynamic
programming over sub-multisets of the hand, exact rational arithmetic) and scores a
hand as `−log Σ exp(−cost)` over those derivations plus a few whole-hand terms. Step
costs penalize fractions, negatives, large intermediates and so on. The weights were
fitted so that ranking all 1362 solvable hands for 24 reproduces the measured
ordering as closely as possible (Spearman ρ ≈ 0.85, 0.83 on held-out puzzles), and
the same model ranks hands for any other target.

Random-target tiers come from `tool/calibrate_targets.dart`, which scores a sample of
hands for each candidate target and ranks targets by the median score of the hands
that can make them plus a rarity penalty (−ln of the fraction of hands that can). It
writes `lib/engine/target_tiers.dart`:

```sh
dart compile exe tool/calibrate_targets.dart -o /tmp/calib
for c in "4 all" "4 any" "5 all" "5 any" "6 all" "6 any" "7 any" "8 any" "9 any"; do
  /tmp/calib ${=c} /tmp/$(echo $c | tr ' ' _).json &
done; wait
/tmp/calib --emit /tmp/{4_all,4_any,5_all,5_any,6_all,6_any,7_any,8_any,9_any}.json
```

For 7–9 cards in any-subset mode, solutions are searched among sub-hands of up to
5–6 cards and intermediate values are pruned, to keep generation fast on a phone.

## Running

```sh
flutter test
flutter run -d chrome     # quickest way to try it
flutter run -d <iphone>   # needs Xcode
```
