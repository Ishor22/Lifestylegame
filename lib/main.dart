import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game.dart';

const String _saveKey = 'lifestyle_game_save_v1';

void main() {
  runApp(const LifeGameApp());
}

class LifeGameApp extends StatelessWidget {
  const LifeGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Life: Business Tycoon',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C5CE7)),
        useMaterial3: true,
      ),
      home: const LifeHome(),
    );
  }
}

class LifeHome extends StatefulWidget {
  const LifeHome({super.key});

  @override
  State<LifeHome> createState() => _LifeHomeState();
}

class _LifeHomeState extends State<LifeHome> {
  Game? _game;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Game? loaded;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_saveKey);
      if (raw != null) loaded = Game.fromJsonString(raw);
    } catch (_) {
      // Storage unavailable: start a new life instead of crashing.
    }
    if (!mounted) return;
    setState(() => _game = loaded ?? Game());
  }

  Future<void> _save() async {
    final game = _game;
    if (game == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_saveKey, game.encode());
    } catch (_) {
      // Saving is best-effort.
    }
  }

  /// Runs a game action, then refreshes the UI and saves progress.
  void _act(String Function(Game g) action) {
    final game = _game;
    if (game == null) return;
    setState(() => action(game));
    _save();
  }

  void _newLife() {
    setState(() => _game = Game(message: 'A brand new life begins at 18.'));
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Life: Business Tycoon'),
        centerTitle: true,
        actions: [
          if (game != null)
            IconButton(
              tooltip: 'New life',
              icon: const Icon(Icons.restart_alt),
              onPressed: () => _confirmNewLife(context),
            ),
        ],
      ),
      body: game == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _StatsCard(game: game),
                    const SizedBox(height: 12),
                    _MessageBar(text: game.message),
                    const SizedBox(height: 12),
                    _ActionsCard(
                      game: game,
                      onWork: () => _act((g) => g.work()),
                      onAgeUp: () => _act((g) => g.ageUp()),
                      onQuit: () => _act((g) => g.quitJob()),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Available jobs',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    for (final job in jobs)
                      _JobTile(
                        job: job,
                        game: game,
                        onApply: () => _act((g) => g.apply(job)),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _confirmNewLife(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new life?'),
        content: const Text('Your current progress will be erased.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('New life')),
        ],
      ),
    );
    if (ok == true) _newLife();
  }
}

class _StatsCard extends StatelessWidget {
  final Game game;
  const _StatsCard({required this.game});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final moneyColor = game.money < 0 ? Colors.red.shade300 : Colors.greenAccent.shade100;
    final expProgress = (game.experience / 10).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Age ${game.age}',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Balance', style: TextStyle(fontSize: 13, color: Colors.white70)),
                    Text(
                      game.money < 0 ? '-\$${-game.money}' : '\$${game.money}',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold, color: moneyColor),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text('🎓 Education: None'),
                Text('💼 Job: ${game.job?.name ?? 'Unemployed'}'),
                Text('⭐ Experience: ${game.experience}'),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: expProgress,
                minHeight: 8,
                backgroundColor: Colors.white24,
                color: Colors.amberAccent,
              ),
            ),
            const SizedBox(height: 4),
            const Text('Experience progress (goal: 10)',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _MessageBar extends StatelessWidget {
  final String text;
  const _MessageBar({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(fontSize: 15)),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  final Game game;
  final VoidCallback onWork;
  final VoidCallback onAgeUp;
  final VoidCallback onQuit;

  const _ActionsCard({
    required this.game,
    required this.onWork,
    required this.onAgeUp,
    required this.onQuit,
  });

  @override
  Widget build(BuildContext context) {
    final hasJob = game.job != null;
    final canWork = hasJob && game.shiftsLeft > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              hasJob
                  ? 'Shifts left this year: ${game.shiftsLeft} / ${Game.maxShiftsPerYear}'
                  : 'Apply for a job to unlock shifts.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canWork ? onWork : null,
              icon: const Icon(Icons.work),
              label: Text(hasJob ? 'Work a shift (+\$${game.job!.pay})' : 'Work'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onAgeUp,
              icon: const Icon(Icons.cake),
              label: Text('Age up (-\$${Game.yearlyExpenses} expenses)'),
            ),
            if (hasJob) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onQuit,
                icon: const Icon(Icons.logout),
                label: const Text('Quit job'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  final Job job;
  final Game game;
  final VoidCallback onApply;

  const _JobTile({required this.job, required this.game, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final holdsJob = game.job != null;
    final isCurrent = game.job?.name == job.name;
    final wasRejected = game.rejected.contains(job.name);
    final canApply = !holdsJob && !wasRejected;

    final String buttonLabel;
    if (isCurrent) {
      buttonLabel = 'Current job';
    } else if (wasRejected) {
      buttonLabel = 'Rejected';
    } else {
      buttonLabel = 'Apply';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Text(job.icon, style: const TextStyle(fontSize: 28)),
        title: Text(job.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '\$${job.pay} per shift · needs ${job.requiredExp} experience',
        ),
        trailing: FilledButton(
          onPressed: canApply ? onApply : null,
          child: Text(buttonLabel),
        ),
      ),
    );
  }
}
