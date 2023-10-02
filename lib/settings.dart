import 'package:flutter/material.dart';
import 'games.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final SharedPreferences _prefs;

  AppSettings(this._prefs);

  int getIntSetting(String key, int defaultValue) {
    return _prefs.getInt(key) ?? defaultValue;
  }

  bool getBoolSetting(String key, bool defaultValue) {
    return _prefs.getBool(key) ?? defaultValue;
  }

  Future<void> setIntSetting(String key, int value) async {
    await _prefs.setInt(key, value);
  }

  Future<void> setBoolSetting(String key, bool value) async {
    await _prefs.setBool(key, value);
  }
}

class SettingsPage extends StatefulWidget {
  final AppSettings appSettings;
  final ValueChanged<Settings> onSettingsChanged;
  final Settings initialSettings;

  SettingsPage({
    required this.appSettings,
    required this.onSettingsChanged,
    required this.initialSettings,
  });

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Settings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _settings.minDifficulty = widget.appSettings.getIntSetting('minDifficulty', 0).toDouble();
    _settings.maxDifficulty = widget.appSettings.getIntSetting('maxDifficulty', games.length).toDouble();
    _settings.timerEnabled = widget.appSettings.getBoolSetting('timerEnabled', true);
  }

  void _saveSettings() {
    // Save the current value to settings
    widget.appSettings.setIntSetting('minDifficulty', _settings.minDifficulty.round());
    widget.appSettings.setIntSetting('maxDifficulty', _settings.maxDifficulty.round());
    widget.appSettings.setBoolSetting('timerEnabled', _settings.timerEnabled);
    // Navigator.pop(context); // Close the settings page
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Min difficulty: ${_settings.minDifficulty.toStringAsFixed(0)}'),
          Slider(
            value: _settings.minDifficulty,
            min: 0,
            max: games.length.toDouble(),
            onChanged: (value) {
              setState(() {
                if(value < _settings.maxDifficulty){
                  _settings.minDifficulty = value;
                }
              });
            },
          ),
          Text('Max difficulty: ${_settings.maxDifficulty.toStringAsFixed(0)}'),
          Slider(
            value: _settings.maxDifficulty,
            min: 0,
            max: games.length.toDouble(),
            onChanged: (value) {
              setState(() {
                if(value > _settings.minDifficulty){
                  _settings.maxDifficulty = value;
                }
              });
            },
          ),
          Row(
            children: [
              Checkbox(
                value: _settings.timerEnabled,
                onChanged: (value) {
                  setState(() {
                    _settings.timerEnabled = value ?? false;
                  });
                },
              ),
              Text('Enable timer'),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(); // Close the dialog without saving changes
          },
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            _saveSettings();
            widget.onSettingsChanged(_settings); // Pass new settings back to the main app
            Navigator.of(context).pop(); // Close the dialog and pass new settings
          },
          child: Text('Save'),
        ),
      ],
    );
  }
}

class Settings {
  double minDifficulty = 0.5;
  double maxDifficulty = 0.5;
  bool timerEnabled = true;
  // Settings(this.minDifficulty, this.maxDifficulty, this.timerEnabled);
}