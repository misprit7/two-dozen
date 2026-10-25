import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/frac.dart';
import 'engine/generator.dart';
import 'games.dart';

const List<Color> themeColors = [
  Colors.deepOrange,
  Colors.cyan,
  Colors.purple,
  Colors.lime,
  Colors.indigo,
  Colors.pink,
];

enum TargetTier {
  easy('Easy'),
  medium('Medium'),
  hard('Hard'),
  expert('Expert');

  final String label;
  const TargetTier(this.label);
}

class AppSettings {
  final SharedPreferences _prefs;

  AppSettings(this._prefs);

  int getIntSetting(String key, int defaultValue) {
    return _prefs.getInt(key) ?? defaultValue;
  }

  bool getBoolSetting(String key, bool defaultValue) {
    return _prefs.getBool(key) ?? defaultValue;
  }

  double getDoubleSetting(String key, double defaultValue) {
    return _prefs.getDouble(key) ?? defaultValue;
  }

  String getStringSetting(String key, String defaultValue) {
    return _prefs.getString(key) ?? defaultValue;
  }

  bool hasSetting(String key) => _prefs.containsKey(key);

  Future<void> setIntSetting(String key, int value) async {
    await _prefs.setInt(key, value);
  }

  Future<void> setBoolSetting(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  Future<void> setDoubleSetting(String key, double value) async {
    await _prefs.setDouble(key, value);
  }

  Future<void> setStringSetting(String key, String value) async {
    await _prefs.setString(key, value);
  }
}

class Settings {
  /// Puzzle difficulty range as percentiles: 0 = easiest hand, 1 = hardest.
  double minDifficulty = 0;
  double maxDifficulty = 1;
  bool timerEnabled = true;
  bool darkMode = false;
  Color themeColor = Colors.deepOrange;
  String target = '24';
  bool randomTarget = false;
  TargetTier targetTier = TargetTier.easy;
  int cards = 4;
  bool useAll = true;

  Settings copy() => Settings()
    ..minDifficulty = minDifficulty
    ..maxDifficulty = maxDifficulty
    ..timerEnabled = timerEnabled
    ..darkMode = darkMode
    ..themeColor = themeColor
    ..target = target
    ..randomTarget = randomTarget
    ..targetTier = targetTier
    ..cards = cards
    ..useAll = useAll;

  Frac get fixedTarget => Frac.tryParse(target) ?? classicTarget;

  /// "Use all cards" is only offered for hands small enough to search fully.
  bool get effectiveUseAll => useAll && cards <= maxUseAllCards;

  bool get isClassicMode => !randomTarget && isClassic(fixedTarget, cards, effectiveUseAll);

  /// Changes to anything in this key mean the current puzzle no longer fits.
  String get puzzleKey =>
      '${randomTarget ? 'random:${targetTier.name}' : fixedTarget}|$cards|$effectiveUseAll|$minDifficulty|$maxDifficulty';
}

Settings readSettings(AppSettings appSettings) {
  Settings ret = Settings();
  if (appSettings.hasSetting('minPercentile')) {
    ret.minDifficulty = appSettings.getDoubleSetting('minPercentile', 0);
    ret.maxDifficulty = appSettings.getDoubleSetting('maxPercentile', 1);
  } else {
    // Older versions stored indices into the 24 games list.
    ret.minDifficulty = appSettings.getIntSetting('minDifficulty', 0) / games.length;
    ret.maxDifficulty = appSettings.getIntSetting('maxDifficulty', games.length) / games.length;
  }
  ret.minDifficulty = ret.minDifficulty.clamp(0.0, 1.0);
  ret.maxDifficulty = ret.maxDifficulty.clamp(ret.minDifficulty, 1.0);
  ret.themeColor = Color(appSettings.getIntSetting('themeColor', Colors.deepOrange.toARGB32()));
  ret.timerEnabled = appSettings.getBoolSetting('timerEnabled', true);
  ret.darkMode = appSettings.getBoolSetting('darkMode', false);
  ret.target = appSettings.getStringSetting('target', '24');
  if (Frac.tryParse(ret.target) == null) ret.target = '24';
  ret.randomTarget = appSettings.getBoolSetting('randomTarget', false);
  ret.targetTier = TargetTier.values[appSettings.getIntSetting('targetTier', 0).clamp(0, TargetTier.values.length - 1)];
  ret.cards = appSettings.getIntSetting('cards', 4).clamp(minCards, maxCards);
  ret.useAll = appSettings.getBoolSetting('useAll', true);

  if (!themeColors.map((c) => c.toARGB32()).contains(ret.themeColor.toARGB32())) {
    ret.themeColor = themeColors[0];
  }

  return ret;
}

void saveSettings(AppSettings appSettings, Settings s) {
  appSettings.setDoubleSetting('minPercentile', s.minDifficulty);
  appSettings.setDoubleSetting('maxPercentile', s.maxDifficulty);
  appSettings.setIntSetting('themeColor', s.themeColor.toARGB32());
  appSettings.setBoolSetting('timerEnabled', s.timerEnabled);
  appSettings.setBoolSetting('darkMode', s.darkMode);
  appSettings.setStringSetting('target', s.target);
  appSettings.setBoolSetting('randomTarget', s.randomTarget);
  appSettings.setIntSetting('targetTier', s.targetTier.index);
  appSettings.setIntSetting('cards', s.cards);
  appSettings.setBoolSetting('useAll', s.useAll);
}

class ColorSelector extends StatelessWidget {
  final ValueChanged<Color> onSelect;
  final Color selected;

  const ColorSelector({super.key, required this.onSelect, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      children: themeColors.map((color) {
        final isSelected = color.toARGB32() == selected.toARGB32();
        return GestureDetector(
          onTap: () => onSelect(color),
          child: Container(
            margin: const EdgeInsets.all(6.0),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(
                color: isSelected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                width: 3.0,
              ),
              borderRadius: BorderRadius.circular(10.0),
            ),
            child: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
          ),
        );
      }).toList(),
    );
  }
}

/// Full-screen settings editor; pops with the edited [Settings] on save.
class SettingsPage extends StatefulWidget {
  final Settings initialSettings;

  const SettingsPage({super.key, required this.initialSettings});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Settings _settings;
  late TextEditingController _targetController;
  String? _targetError;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings.copy();
    _targetController = TextEditingController(text: _settings.target);
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  void _setTarget(String text) {
    final f = Frac.tryParse(text);
    setState(() {
      if (f == null) {
        _targetError = 'Enter a number like 24, -5, 7/3 or 2.5';
      } else if (f.n.abs() > 99999 || f.d > 1000) {
        _targetError = 'That target is too large';
      } else {
        _targetError = null;
        _settings.target = f.toString();
      }
    });
  }

  void _save() {
    if (_targetError != null && !_settings.randomTarget) return;
    Navigator.of(context).pop(_settings);
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String percent(double v) => '${(v * 100).round()}%';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _section('Target'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Fixed'), icon: Icon(Icons.flag)),
                ButtonSegment(value: true, label: Text('Random'), icon: Icon(Icons.casino)),
              ],
              selected: {_settings.randomTarget},
              onSelectionChanged: (s) => setState(() => _settings.randomTarget = s.first),
            ),
          ),
          const SizedBox(height: 16),
          if (!_settings.randomTarget) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _targetController,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: InputDecoration(
                  labelText: 'Target number',
                  helperText: 'e.g. 24, −5, 7/3 or 2.5',
                  errorText: _targetError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: _setTarget,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                children: ['24', '10', '100', '1/2', '2025'].map((t) {
                  return ActionChip(
                    label: Text(t),
                    onPressed: () {
                      _targetController.text = t;
                      _setTarget(t);
                    },
                  );
                }).toList(),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<TargetTier>(
                segments: TargetTier.values.map((t) => ButtonSegment(value: t, label: Text(t.label))).toList(),
                selected: {_settings.targetTier},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _settings.targetTier = s.first),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Each puzzle gets a new target. Harder tiers pick targets that are '
                  'rarer and need more involved solutions, like large numbers or fractions.'),
            ),
          ],
          _section('Cards'),
          ListTile(
            title: const Text('Number of cards'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: _settings.cards > minCards ? () => setState(() => --_settings.cards) : null,
                ),
                Text('${_settings.cards}', style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _settings.cards < maxCards ? () => setState(() => ++_settings.cards) : null,
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Must use every card'),
            subtitle: Text(_settings.cards > maxUseAllCards
                ? 'Available with up to $maxUseAllCards cards'
                : _settings.useAll
                    ? 'Combine all cards into the target'
                    : 'Reach the target using any of the cards'),
            value: _settings.effectiveUseAll,
            onChanged: _settings.cards > maxUseAllCards ? null : (v) => setState(() => _settings.useAll = v),
          ),
          _section('Puzzle difficulty'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: RangeSlider(
              values: RangeValues(_settings.minDifficulty, _settings.maxDifficulty),
              divisions: 20,
              labels: RangeLabels(percent(_settings.minDifficulty), percent(_settings.maxDifficulty)),
              onChanged: (v) => setState(() {
                if (v.end - v.start < 0.05) return;
                _settings.minDifficulty = v.start;
                _settings.maxDifficulty = v.end;
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Easiest'),
                const Spacer(),
                Text('${percent(_settings.minDifficulty)} – ${percent(_settings.maxDifficulty)}'),
                const Spacer(),
                const Text('Hardest'),
              ],
            ),
          ),
          _section('Display'),
          SwitchListTile(
            title: const Text('Show timer'),
            value: _settings.timerEnabled,
            onChanged: (v) => setState(() => _settings.timerEnabled = v),
          ),
          SwitchListTile(
            title: const Text('Dark mode'),
            value: _settings.darkMode,
            onChanged: (v) => setState(() => _settings.darkMode = v),
          ),
          ColorSelector(
            selected: _settings.themeColor,
            onSelect: (c) => setState(() => _settings.themeColor = c),
          ),
        ],
      ),
    );
  }
}
