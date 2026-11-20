import 'package:flutter_test/flutter_test.dart';
import 'dart:math';

import 'package:lifestyle_game/game.dart';

void main() {
  group('Game rules', () {
    test('starts at 18 with no money, no job, no experience', () {
      final g = Game();
      expect(g.age, 18);
      expect(g.money, 0);
      expect(g.job, isNull);
      expect(g.experience, 0);
    });

    test('beginner job with no requirement is accepted', () {
      final g = Game(rng: Random(1));
      g.apply(jobByName('Cleaner'));
      expect(g.job?.name, 'Cleaner');
    });

    test('job above experience requirement can be rejected', () {
      // Random(7) gives a value above the 20% lucky chance on its first draw.
      final g = Game(rng: _AlwaysHigh());
      g.apply(jobByName('Construction Helper'));
      expect(g.job, isNull);
      expect(g.rejected, contains('Construction Helper'));
    });

    test('work pays salary, grows experience and respects yearly limit', () {
      final g = Game(jobName: 'Cleaner');
      for (var i = 0; i < Game.maxShiftsPerYear; i++) {
        g.work();
      }
      expect(g.money, 40 * Game.maxShiftsPerYear);
      expect(g.experience, Game.maxShiftsPerYear);
      g.work();
      expect(g.money, 40 * Game.maxShiftsPerYear);
    });

    test('age up charges expenses and resets shifts', () {
      final g = Game(money: 1000, jobName: 'Cleaner', shiftsThisYear: 5);
      g.ageUp();
      expect(g.age, 19);
      expect(g.money, 1000 - Game.yearlyExpenses);
      expect(g.shiftsThisYear, 0);
    });

    test('save and load round-trips', () {
      final g = Game(age: 22, money: 350, experience: 3, jobName: 'Shop Assistant');
      final loaded = Game.fromJsonString(g.encode());
      expect(loaded, isNotNull);
      expect(loaded!.age, 22);
      expect(loaded.money, 350);
      expect(loaded.jobName, 'Shop Assistant');
    });

    test('corrupt save data is rejected', () {
      expect(Game.fromJsonString('not json'), isNull);
    });
  });
}

/// Random that always returns a value well above the lucky-accept chance.
class _AlwaysHigh implements Random {
  @override
  bool nextBool() => true;
  @override
  double nextDouble() => 0.99;
  @override
  int nextInt(int max) => max - 1;
}
