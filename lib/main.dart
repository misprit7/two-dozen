import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/frac.dart';
import 'engine/solver.dart';
import 'puzzle_service.dart';
import 'settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(MyApp(appSettings: AppSettings(prefs)));
}

/// Results larger than this are refused to keep arithmetic exact everywhere.
const int _maxMagnitude = 1000000000000;

class MyApp extends StatefulWidget {
  final AppSettings appSettings;
  const MyApp({super.key, required this.appSettings});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeData _currentTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
    useMaterial3: true,
  );

  void _changeTheme(bool darkMode, Color themeColor) {
    Brightness mode = darkMode ? Brightness.dark : Brightness.light;
    setState(() {
      _currentTheme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: themeColor, brightness: mode),
        brightness: mode,
        useMaterial3: true,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    Settings s = readSettings(widget.appSettings);
    _changeTheme(s.darkMode, s.themeColor);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Two Dozen',
      theme: _currentTheme,
      home: GameScreen(appSettings: widget.appSettings, changeTheme: _changeTheme),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GameScreen extends StatefulWidget {
  final AppSettings appSettings;
  final void Function(bool darkMode, Color themeColor) changeTheme;
  const GameScreen({super.key, required this.appSettings, required this.changeTheme});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final PuzzleService _service = PuzzleService();
  Settings _settings = Settings();

  Puzzle? _puzzle;
  bool _loading = true;
  String? _error;
  int _loadToken = 0;

  /// Current cards; null once a card has been combined into another.
  List<Frac?> numbers = [];
  List<(List<Frac?>, int)> history = [];
  int historyPoint = 0;
  int numSelect = -1;
  Op? opSelect;

  late Timer timer;
  int timerSeconds = 0;
  int puzzleStartSeconds = 0;
  int numSolves = 0;
  bool _revealed = false;

  /// Set between solving a puzzle and the next one appearing.
  bool _advancing = false;

  bool get _useAll => _settings.effectiveUseAll;

  @override
  void initState() {
    super.initState();
    _settings = readSettings(widget.appSettings);
    timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      setState(() {
        ++timerSeconds;
      });
    });
    _loadNext();
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  /// Loads the next puzzle. With [showSpinner] false the current board stays up
  /// until the (usually prefetched) puzzle arrives, so there's no visible gap.
  Future<void> _loadNext({bool showSpinner = true}) async {
    final token = ++_loadToken;
    setState(() {
      _error = null;
      if (showSpinner) _loading = true;
    });
    try {
      final puzzle = await _service.next(_settings);
      if (token != _loadToken || !mounted) return;
      setState(() {
        _startPuzzle(puzzle);
        _loading = false;
        _advancing = false;
      });
      _service.prefetch(_settings);
    } on NoPuzzleException catch (e) {
      if (token != _loadToken || !mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _advancing = false;
        _puzzle = null;
      });
    }
  }

  void _startPuzzle(Puzzle p) {
    _puzzle = p;
    numbers = p.hand.map<Frac?>((c) => Frac(c)).toList();
    opSelect = null;
    numSelect = -1;
    history = [(List<Frac?>.from(numbers), -1)];
    historyPoint = 0;
    puzzleStartSeconds = timerSeconds;
    _revealed = false;
  }

  bool get _inputEnabled => _puzzle != null && !_loading && !_advancing;

  void checkFinished() {
    final target = _puzzle!.target;
    final remaining = numbers.whereType<Frac>().toList();
    final solved =
        _useAll ? remaining.length == 1 && remaining.first == target : historyPoint > 0 && remaining.contains(target);
    if (!solved) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _advancing = true;
      if (!_revealed) ++numSolves;
    });
    _loadNext(showSpinner: false);
  }

  void addHistory() {
    if (historyPoint < history.length - 1) {
      history.removeRange(historyPoint + 1, history.length);
    }
    history.add((List<Frac?>.from(numbers), numSelect));
    historyPoint += 1;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  void numberPress(int newSelect) {
    if (!_inputEnabled || numbers[newSelect] == null) {
      return;
    }
    HapticFeedback.selectionClick();
    if (numSelect == newSelect) {
      setState(() {
        numSelect = -1;
        history[historyPoint] = (history[historyPoint].$1, numSelect);
      });
      return;
    }
    if (numSelect == -1 || opSelect == null) {
      setState(() {
        numSelect = newSelect;
        history[historyPoint] = (history[historyPoint].$1, numSelect);
      });
      return;
    }
    final newNum = numbers[newSelect]!;
    final oldNum = numbers[numSelect]!;
    if (newNum.isZero && opSelect == Op.div) {
      _toast("Can't divide by zero");
      return;
    }
    final result = opSelect!.apply(oldNum, newNum);
    if (result.n.abs() > _maxMagnitude || result.d > _maxMagnitude) {
      _toast('That number is too large');
      return;
    }
    setState(() {
      history[historyPoint] = (history[historyPoint].$1, numSelect);
      numbers[newSelect] = result;
      numbers[numSelect] = null;
      opSelect = null;
      numSelect = newSelect;
      addHistory();
    });
    checkFinished();
  }

  void opPress(Op op) {
    if (!_inputEnabled) return;
    HapticFeedback.selectionClick();
    setState(() {
      opSelect = opSelect == op ? null : op;
    });
  }

  void undo() {
    if (!_inputEnabled || historyPoint <= 0) return;
    setState(() {
      --historyPoint;
      numbers = List<Frac?>.from(history[historyPoint].$1);
      numSelect = history[historyPoint].$2;
      opSelect = null;
    });
  }

  void redo() {
    if (!_inputEnabled || historyPoint >= history.length - 1) return;
    setState(() {
      ++historyPoint;
      numbers = List<Frac?>.from(history[historyPoint].$1);
      numSelect = history[historyPoint].$2;
      opSelect = null;
    });
  }

  /// Adds (or multiplies) every remaining card together.
  void combineAll(Op op) {
    if (!_inputEnabled) return;
    final live = [
      for (var i = 0; i < numbers.length; ++i)
        if (numbers[i] != null) i
    ];
    if (live.length < 2) return;
    var result = op == Op.add ? Frac.zero : Frac.one;
    for (final i in live) {
      result = op.apply(result, numbers[i]!);
    }
    if (result.n.abs() > _maxMagnitude || result.d > _maxMagnitude) {
      _toast('That number is too large');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      final dest = numSelect != -1 ? numSelect : live.first;
      for (final i in live) {
        numbers[i] = null;
      }
      numbers[dest] = result;
      numSelect = dest;
      opSelect = null;
      addHistory();
    });
    checkFinished();
  }

  static final _digitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  static final _numpadKeys = [
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  /// Same hotkeys as www.4nums.com: 1–4 pick cards (numpad keys mirror the card
  /// grid), Q W E R pick + − × ÷, A adds all, S multiplies all, Esc undoes and
  /// ` redoes. With more cards, 1–9 pick cards in reading order.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final n = numbers.length;
    final digit = _digitKeys.indexOf(key);
    if (digit >= 0) {
      if (digit < n) numberPress(digit);
      return KeyEventResult.handled;
    }
    final pad = _numpadKeys.indexOf(key);
    if (pad >= 0) {
      // Numpad rows map bottom-up onto the card grid, like a phone keypad flipped.
      final cols = n == 4 ? 2 : 3;
      final rows = (n / cols).ceil();
      final col = pad % 3, rowFromBottom = pad ~/ 3;
      final i = (rows - 1 - rowFromBottom) * cols + col;
      if (col < cols && rowFromBottom < rows && i < n) numberPress(i);
      return KeyEventResult.handled;
    }
    final action = {
      LogicalKeyboardKey.keyQ: () => opPress(Op.add),
      LogicalKeyboardKey.keyW: () => opPress(Op.sub),
      LogicalKeyboardKey.keyE: () => opPress(Op.mul),
      LogicalKeyboardKey.keyR: () => opPress(Op.div),
      LogicalKeyboardKey.keyA: () => combineAll(Op.add),
      LogicalKeyboardKey.keyS: () => combineAll(Op.mul),
      LogicalKeyboardKey.escape: undo,
      LogicalKeyboardKey.backquote: redo,
    }[key];
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  void restartSession() {
    setState(() {
      timerSeconds = 0;
      numSolves = 0;
    });
    _loadNext();
  }

  void _showSolution() {
    final p = _puzzle;
    if (p == null) return;
    setState(() => _revealed = true);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('One solution', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'The most straightforward route the solver found. '
                  'This puzzle won\'t count toward your solves.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                for (final (i, s) in p.solution.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${i + 1}.   ${_fmt(s.a)} ${s.op.symbol} ${_fmt(s.b)} = ${_fmt(s.result)}',
                      style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fmt(Frac f) => f.toString().replaceAll('-', '−');

  void _openSettings() async {
    final newSettings = await Navigator.of(context).push<Settings>(
      MaterialPageRoute(builder: (_) => SettingsPage(initialSettings: _settings)),
    );
    if (newSettings == null) return;
    saveSettings(widget.appSettings, newSettings);
    final puzzleChanged = newSettings.puzzleKey != _settings.puzzleKey;
    setState(() => _settings = newSettings);
    widget.changeTheme(_settings.darkMode, _settings.themeColor);
    if (puzzleChanged) _loadNext();
  }

  void _openHelpDialog() {
    final target = _puzzle?.target ?? _settings.fixedTarget;
    final cards = _settings.cards;
    final goal = _useAll
        ? 'Make the target number using +, −, ×, ÷ and all $cards cards.'
        : 'Make the target number using +, −, ×, ÷ and any of the $cards cards — you don\'t need them all.';
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('How to play'),
          content: SingleChildScrollView(
            child: Text('''
$goal The current target is ${_fmt(target)}.

Tap a card, an operation, then another card to combine them; the result replaces the second card. For example, with [1, 3, 6, 8] and target 24, a solution is (6 − 3) × 8 × 1 = 24.

« and » undo and redo. ++ adds all remaining cards together and ×× multiplies them.

Stuck? The lightbulb shows a solution, and skip deals a new puzzle. Every puzzle is guaranteed to be solvable.
${kIsWeb ? '\nKeyboard (same as 4nums.com): 1–4 or the numpad pick cards (1–9 with more cards), Q W E R pick + − × ÷, A adds all, S multiplies all, Esc undoes, ` redoes.\n' : ''}
In settings you can change the target (including fractions, or a random target at four difficulty levels), the number of cards, and the puzzle difficulty range. For the classic game (24 with four cards) puzzles are ordered by average solve times of all 1362 possible puzzles, measured at www.4nums.com; other games use a difficulty model fitted to that data.'''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  String _clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.inversePrimary,
        title: const Text('Two Dozen'),
        actions: [
          IconButton(icon: const Icon(Icons.help_outline), tooltip: 'How to play', onPressed: _openHelpDialog),
          IconButton(icon: const Icon(Icons.settings), tooltip: 'Settings', onPressed: _openSettings),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            final opSize = min((width - 32 - 3 * 12) / 4, min(84.0, constraints.maxHeight / 9));
            return Column(
              children: [
                const SizedBox(height: 12),
                _buildHeader(theme),
                Expanded(child: _buildBoard(theme)),
                _buildButtonRow([
                  for (final op in Op.values)
                    _GameButton(
                      size: opSize,
                      active: opSelect == op,
                      onPressed: () => opPress(op),
                      child: Text(op.symbol, style: TextStyle(fontSize: opSize * 0.4)),
                    ),
                ]),
                const SizedBox(height: 12),
                _buildButtonRow([
                  _GameButton(
                    size: opSize,
                    onPressed: historyPoint > 0 ? undo : null,
                    child: Text('«', style: TextStyle(fontSize: opSize * 0.4)),
                  ),
                  _GameButton(
                    size: opSize,
                    onPressed: () => combineAll(Op.add),
                    child: Text('++', style: TextStyle(fontSize: opSize * 0.32)),
                  ),
                  _GameButton(
                    size: opSize,
                    onPressed: () => combineAll(Op.mul),
                    child: Text('××', style: TextStyle(fontSize: opSize * 0.32)),
                  ),
                  _GameButton(
                    size: opSize,
                    onPressed: historyPoint < history.length - 1 ? redo : null,
                    child: Text('»', style: TextStyle(fontSize: opSize * 0.4)),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      onPressed: restartSession,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Restart'),
                    ),
                    TextButton.icon(
                      onPressed: _inputEnabled ? _showSolution : null,
                      icon: const Icon(Icons.lightbulb_outline),
                      label: const Text('Solution'),
                    ),
                    TextButton.icon(
                      onPressed: _inputEnabled || _error != null ? () => _loadNext() : null,
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Skip'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final scheme = theme.colorScheme;
    final statStyle = theme.textTheme.headlineMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final target = _puzzle?.target;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _settings.timerEnabled
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.timer_outlined),
                      const SizedBox(width: 6),
                      Text(_clock(timerSeconds), style: statStyle),
                    ])
                  : const SizedBox.shrink(),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 96),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('TARGET',
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onPrimaryContainer, letterSpacing: 1.5)),
                SizedBox(
                  height: 48,
                  child: target == null
                      ? const SizedBox.shrink()
                      : FittedBox(
                          child:
                              FracText(target, fontSize: 40, color: scheme.onPrimaryContainer, weight: FontWeight.bold),
                        ),
                ),
                _DifficultyDots(_puzzle?.percentile, color: scheme.onPrimaryContainer),
              ],
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.emoji_events_outlined),
                const SizedBox(width: 6),
                Text('$numSolves', style: statStyle),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: _openSettings, child: const Text('Open settings')),
            ],
          ),
        ),
      );
    }
    if (_puzzle == null || _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(builder: (context, constraints) {
      final n = numbers.length;
      final cols = n == 4 ? 2 : 3;
      final rows = (n / cols).ceil();
      const gap = 16.0;
      final size = [
        (constraints.maxWidth - 48 - (cols - 1) * gap) / cols,
        (constraints.maxHeight - 32 - (rows - 1) * gap) / rows,
        200.0,
      ].reduce(min);
      return Center(
        child: SizedBox(
          width: cols * size + (cols - 1) * gap,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < n; ++i)
                Opacity(
                  opacity: numbers[i] == null ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: numbers[i] == null,
                    child: _GameButton(
                      size: size,
                      active: numSelect == i,
                      onPressed: () => numberPress(i),
                      child: numbers[i] == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: EdgeInsets.all(size * 0.12),
                              child: FittedBox(child: FracText(numbers[i]!, fontSize: size * 0.36)),
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildButtonRow(List<Widget> buttons) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (i, b) in buttons.indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          b,
        ],
      ],
    );
  }
}

/// Square button used for cards and operations; filled when [active].
class _GameButton extends StatelessWidget {
  final double size;
  final bool active;
  final VoidCallback? onPressed;
  final Widget child;

  const _GameButton({
    required this.size,
    required this.child,
    this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(
      padding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    );
    return SizedBox(
      width: size,
      height: size,
      child: active
          ? FilledButton(onPressed: onPressed, style: style, child: Center(child: child))
          : FilledButton.tonal(onPressed: onPressed, style: style, child: Center(child: child)),
    );
  }
}

/// Renders a number, drawing fractions stacked with a bar.
class FracText extends StatelessWidget {
  final Frac value;
  final double fontSize;
  final Color? color;
  final FontWeight? weight;

  const FracText(this.value, {super.key, required this.fontSize, this.color, this.weight});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: fontSize, color: color, fontWeight: weight, height: 1.1);
    final sign = value.isNegative ? '−' : '';
    if (value.isInteger) return Text('$sign${value.n.abs()}', style: style);
    final small = style.copyWith(fontSize: fontSize * 0.62);
    final barColor = color ?? DefaultTextStyle.of(context).style.color ?? Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sign.isNotEmpty) Text(sign, style: style),
        IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${value.n.abs()}', style: small, textAlign: TextAlign.center),
              Container(height: max(1.5, fontSize * 0.06), color: barColor),
              Text('${value.d}', style: small, textAlign: TextAlign.center),
            ],
          ),
        ),
      ],
    );
  }
}

/// Five dots showing where the current puzzle sits in the difficulty ranking.
class _DifficultyDots extends StatelessWidget {
  final double? percentile;
  final Color color;
  const _DifficultyDots(this.percentile, {required this.color});

  @override
  Widget build(BuildContext context) {
    final filled = percentile == null ? 0 : (percentile! * 5).floor().clamp(0, 4) + 1;
    return Tooltip(
      message: 'Puzzle difficulty',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; ++i)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? color : color.withValues(alpha: 0.25),
              ),
            ),
        ],
      ),
    );
  }
}
