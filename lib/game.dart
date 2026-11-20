import 'dart:convert';
import 'dart:math';

/// A beginner job the player can apply for.
class Job {
  final String name;
  final String icon;
  final int pay; // $ per shift
  final int requiredExp;

  const Job(this.name, this.icon, this.pay, this.requiredExp);
}

const List<Job> jobs = [
  Job('Cleaner', '🧹', 40, 0),
  Job('Dishwasher', '🍽️', 45, 0),
  Job('Car Washer', '🚗', 50, 1),
  Job('Delivery Helper', '📦', 60, 2),
  Job('Shop Assistant', '🛍️', 70, 3),
  Job('Construction Helper', '🏗️', 80, 4),
];

Job jobByName(String name) => jobs.firstWhere((j) => j.name == name);

/// Pure game state and rules (no UI, no storage) so it can be tested.
class Game {
  static const int maxShiftsPerYear = 5;
  static const int yearlyExpenses = 400;
  static const double luckyAcceptChance = 0.2;

  int age;
  int money;
  int experience;
  String? jobName;
  int shiftsThisYear;
  Set<String> rejected;
  String message;

  final Random _rng;

  Game({
    this.age = 18,
    this.money = 0,
    this.experience = 0,
    this.jobName,
    this.shiftsThisYear = 0,
    Set<String>? rejected,
    this.message = 'Welcome! Apply for a job to start earning.',
    Random? rng,
  })  : rejected = rejected ?? <String>{},
        _rng = rng ?? Random();

  Job? get job => jobName == null ? null : jobByName(jobName!);

  int get shiftsLeft => maxShiftsPerYear - shiftsThisYear;

  /// Apply for a job. Meets requirements = accepted; otherwise a small chance.
  String apply(Job j) {
    if (job != null) {
      return message = 'You already have a job. Quit it first.';
    }
    if (rejected.contains(j.name)) {
      return message = 'Rejected for ${j.name} this year. Try again after your birthday.';
    }
    final meetsRequirements = experience >= j.requiredExp;
    final accepted = meetsRequirements || _rng.nextDouble() < luckyAcceptChance;
    if (accepted) {
      jobName = j.name;
      return message = '🎉 Accepted! You are now a ${j.name} (\$${j.pay} per shift).';
    }
    rejected.add(j.name);
    return message = '❌ Rejected by the ${j.name} employer. Gain more experience first.';
  }

  /// Work one shift: salary is paid and experience grows.
  String work() {
    final current = job;
    if (current == null) {
      return message = 'You have no job. Apply for one first.';
    }
    if (shiftsLeft <= 0) {
      return message = 'No shifts left this year. Age up to continue.';
    }
    money += current.pay;
    experience += 1;
    shiftsThisYear += 1;
    return message = '💵 Salary paid: +\$${current.pay}. Experience +1.';
  }

  String quitJob() {
    if (job == null) return message = 'You do not have a job.';
    final old = jobName;
    jobName = null;
    return message = 'You quit your job as $old.';
  }

  /// One year passes: expenses are paid and the yearly limits reset.
  String ageUp() {
    age += 1;
    money -= yearlyExpenses;
    shiftsThisYear = 0;
    rejected.clear();
    return message = '🎂 You are now $age. Yearly expenses: -\$$yearlyExpenses.';
  }

  Map<String, dynamic> toJson() => {
        'age': age,
        'money': money,
        'experience': experience,
        'jobName': jobName,
        'shiftsThisYear': shiftsThisYear,
        'rejected': rejected.toList(),
        'message': message,
      };

  /// Returns null if the saved data is missing or corrupt.
  static Game? fromJsonString(String source) {
    try {
      final map = jsonDecode(source) as Map<String, dynamic>;
      final name = map['jobName'] as String?;
      if (name != null && !jobs.any((j) => j.name == name)) return null;
      return Game(
        age: map['age'] as int,
        money: map['money'] as int,
        experience: map['experience'] as int,
        jobName: name,
        shiftsThisYear: map['shiftsThisYear'] as int,
        rejected: (map['rejected'] as List).cast<String>().toSet(),
        message: map['message'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode(toJson());
}
