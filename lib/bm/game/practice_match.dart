import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../design/bm_theme.dart';

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.category,
    required this.difficulty,
    required this.text,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String id;
  final String category;
  final String difficulty;
  final String text;
  final List<String> options;
  final int correctIndex;
  final String explanation;
}

/// Original development question set. The production target is 5,000 reviewed
/// questions held server-side; this bank is the local practice set only.
const kPracticeQuestions = <QuizQuestion>[
  QuizQuestion(
    id: 'q001',
    category: 'Science',
    difficulty: 'Easy',
    text: 'Which planet is known as the Red Planet?',
    options: ['Earth', 'Mars', 'Jupiter', 'Venus'],
    correctIndex: 1,
    explanation: 'Iron oxide dust on Mars gives it a reddish appearance.',
  ),
  QuizQuestion(
    id: 'q002',
    category: 'Geography',
    difficulty: 'Easy',
    text: 'What is the capital of France?',
    options: ['Berlin', 'Madrid', 'Paris', 'Rome'],
    correctIndex: 2,
    explanation: 'Paris has been the French capital since 987 AD.',
  ),
  QuizQuestion(
    id: 'q003',
    category: 'Space',
    difficulty: 'Medium',
    text: 'Which planet has the most moons?',
    options: ['Jupiter', 'Saturn', 'Uranus', 'Neptune'],
    correctIndex: 1,
    explanation: 'Saturn overtook Jupiter with 274 confirmed moons.',
  ),
  QuizQuestion(
    id: 'q004',
    category: 'History',
    difficulty: 'Medium',
    text: 'In which year did the Berlin Wall fall?',
    options: ['1987', '1989', '1991', '1993'],
    correctIndex: 1,
    explanation: 'The wall opened on 9 November 1989.',
  ),
  QuizQuestion(
    id: 'q005',
    category: 'Music',
    difficulty: 'Easy',
    text: 'How many strings does a standard violin have?',
    options: ['Four', 'Five', 'Six', 'Seven'],
    correctIndex: 0,
    explanation: 'G, D, A and E.',
  ),
  QuizQuestion(
    id: 'q006',
    category: 'Animals',
    difficulty: 'Easy',
    text: 'What is the largest land animal?',
    options: ['Giraffe', 'African elephant', 'Hippopotamus', 'Rhinoceros'],
    correctIndex: 1,
    explanation: 'African elephants can weigh over six tonnes.',
  ),
  QuizQuestion(
    id: 'q007',
    category: 'Mathematics',
    difficulty: 'Medium',
    text: 'What is the value of 7 squared plus 5 squared?',
    options: ['64', '74', '84', '94'],
    correctIndex: 1,
    explanation: '49 + 25 = 74.',
  ),
  QuizQuestion(
    id: 'q008',
    category: 'Technology',
    difficulty: 'Medium',
    text: 'What does the "S" in HTTPS stand for?',
    options: ['Secure', 'Standard', 'Server', 'Static'],
    correctIndex: 0,
    explanation: 'HTTPS is HTTP over TLS, the secure variant.',
  ),
  QuizQuestion(
    id: 'q009',
    category: 'Literature',
    difficulty: 'Easy',
    text: 'Who wrote "Romeo and Juliet"?',
    options: [
      'Charles Dickens',
      'William Shakespeare',
      'Jane Austen',
      'Oscar Wilde'
    ],
    correctIndex: 1,
    explanation: 'Shakespeare wrote the tragedy around 1595.',
  ),
  QuizQuestion(
    id: 'q010',
    category: 'Food',
    difficulty: 'Easy',
    text: 'Which spice is the most expensive by weight?',
    options: ['Vanilla', 'Saffron', 'Cardamom', 'Cinnamon'],
    correctIndex: 1,
    explanation: 'Saffron is hand-harvested from crocus flowers.',
  ),
  QuizQuestion(
    id: 'q011',
    category: 'Sport',
    difficulty: 'Medium',
    text: 'How many players are on the field per football team?',
    options: ['Nine', 'Ten', 'Eleven', 'Twelve'],
    correctIndex: 2,
    explanation: 'Eleven including the goalkeeper.',
  ),
  QuizQuestion(
    id: 'q012',
    category: 'World Capitals',
    difficulty: 'Medium',
    text: 'What is the capital of Australia?',
    options: ['Sydney', 'Melbourne', 'Canberra', 'Perth'],
    correctIndex: 2,
    explanation: 'Canberra was purpose-built as the capital.',
  ),
  QuizQuestion(
    id: 'q013',
    category: 'Nature',
    difficulty: 'Easy',
    text: 'Which gas do plants absorb for photosynthesis?',
    options: ['Oxygen', 'Carbon dioxide', 'Nitrogen', 'Hydrogen'],
    correctIndex: 1,
    explanation: 'Plants convert CO2 and water into glucose using light.',
  ),
  QuizQuestion(
    id: 'q014',
    category: 'Movies',
    difficulty: 'Medium',
    text: 'Which film introduced the character Ellen Ripley?',
    options: ['Blade Runner', 'Alien', 'The Thing', 'Predator'],
    correctIndex: 1,
    explanation: 'Ripley first appeared in Ridley Scott\'s Alien (1979).',
  ),
  QuizQuestion(
    id: 'q015',
    category: 'Mythology',
    difficulty: 'Hard',
    text: 'In Greek myth, who flew too close to the sun?',
    options: ['Icarus', 'Perseus', 'Orpheus', 'Theseus'],
    correctIndex: 0,
    explanation: 'Icarus\'s wax wings melted when he ignored his father.',
  ),
  QuizQuestion(
    id: 'q016',
    category: 'Geography',
    difficulty: 'Hard',
    text: 'Which country has the most time zones?',
    options: ['Russia', 'France', 'United States', 'China'],
    correctIndex: 1,
    explanation:
        'France spans 12 time zones thanks to its overseas territories.',
  ),
  QuizQuestion(
    id: 'q017',
    category: 'British Culture',
    difficulty: 'Medium',
    text: 'Which London landmark houses the Crown Jewels?',
    options: [
      'Buckingham Palace',
      'Tower of London',
      'Westminster Abbey',
      'St Paul\'s'
    ],
    correctIndex: 1,
    explanation: 'The Crown Jewels are kept in the Tower of London.',
  ),
  QuizQuestion(
    id: 'q018',
    category: 'Science',
    difficulty: 'Hard',
    text: 'What is the most abundant element in the universe?',
    options: ['Hydrogen', 'Helium', 'Oxygen', 'Carbon'],
    correctIndex: 0,
    explanation: 'Hydrogen makes up roughly three quarters of normal matter.',
  ),
  QuizQuestion(
    id: 'q019',
    category: 'Art',
    difficulty: 'Medium',
    text: 'Who painted the ceiling of the Sistine Chapel?',
    options: ['Raphael', 'Michelangelo', 'Leonardo da Vinci', 'Caravaggio'],
    correctIndex: 1,
    explanation: 'Michelangelo painted it between 1508 and 1512.',
  ),
  QuizQuestion(
    id: 'q020',
    category: 'Video Games',
    difficulty: 'Medium',
    text: 'Which company created the Mario franchise?',
    options: ['Sega', 'Sony', 'Nintendo', 'Atari'],
    correctIndex: 2,
    explanation: 'Nintendo introduced Mario in 1981.',
  ),
  QuizQuestion(
    id: 'q021',
    category: 'General Knowledge',
    difficulty: 'Easy',
    text: 'How many sides does a hexagon have?',
    options: ['Five', 'Six', 'Seven', 'Eight'],
    correctIndex: 1,
    explanation: 'A hexagon has six sides.',
  ),
  QuizQuestion(
    id: 'q022',
    category: 'History',
    difficulty: 'Expert',
    text: 'Which treaty ended the First World War?',
    options: [
      'Treaty of Versailles',
      'Treaty of Paris',
      'Treaty of Vienna',
      'Treaty of Ghent'
    ],
    correctIndex: 0,
    explanation: 'Signed in 1919 at the Palace of Versailles.',
  ),
  QuizQuestion(
    id: 'q023',
    category: 'Popular Culture',
    difficulty: 'Easy',
    text: 'What does "app" short for?',
    options: ['Application', 'Apparatus', 'Approach', 'Appendix'],
    correctIndex: 0,
    explanation: 'Short for application software.',
  ),
  QuizQuestion(
    id: 'q024',
    category: 'Television',
    difficulty: 'Medium',
    text: 'What is the standard frame rate of cinema film?',
    options: ['24 fps', '25 fps', '30 fps', '48 fps'],
    correctIndex: 0,
    explanation: '24 frames per second is the classic cinema standard.',
  ),
  QuizQuestion(
    id: 'q025',
    category: 'Space',
    difficulty: 'Hard',
    text: 'What is the name of the galaxy nearest to the Milky Way?',
    options: ['Andromeda', 'Triangulum', 'Sombrero', 'Whirlpool'],
    correctIndex: 0,
    explanation: 'Andromeda is about 2.5 million light years away.',
  ),
  QuizQuestion(
    id: 'q026',
    category: 'Animals',
    difficulty: 'Medium',
    text: 'Which mammal is the only one capable of true flight?',
    options: ['Flying squirrel', 'Bat', 'Sugar glider', 'Colugo'],
    correctIndex: 1,
    explanation: 'Bats are the only mammals with powered flight.',
  ),
  QuizQuestion(
    id: 'q027',
    category: 'Science',
    difficulty: 'Medium',
    text: 'What is the chemical symbol for gold?',
    options: ['Go', 'Gd', 'Au', 'Ag'],
    correctIndex: 2,
    explanation: 'Au comes from the Latin aurum.',
  ),
  QuizQuestion(
    id: 'q028',
    category: 'Sport',
    difficulty: 'Hard',
    text: 'How many points is a try worth in rugby union?',
    options: ['Three', 'Four', 'Five', 'Seven'],
    correctIndex: 2,
    explanation: 'A try is five points, with two extra for a conversion.',
  ),
  QuizQuestion(
    id: 'q029',
    category: 'Food',
    difficulty: 'Medium',
    text: 'Which fruit is the main ingredient of guacamole?',
    options: ['Avocado', 'Lime', 'Tomato', 'Mango'],
    correctIndex: 0,
    explanation: 'Avocado gives guacamole its base and texture.',
  ),
  QuizQuestion(
    id: 'q030',
    category: 'Geography',
    difficulty: 'Easy',
    text: 'Which ocean is the largest?',
    options: ['Atlantic', 'Indian', 'Arctic', 'Pacific'],
    correctIndex: 3,
    explanation: 'The Pacific covers about a third of the planet.',
  ),
];

class Contestant {
  Contestant({
    required this.name,
    required this.isHuman,
    required this.color,
  });

  final String name;
  final bool isHuman;
  final Color color;

  int score = 0;
  int totalScore = 0;
  int energy = 5;
  bool eliminated = false;
  int correct = 0;
  int wrong = 0;

  String get initial => name.isEmpty ? '?' : name[0].toUpperCase();
}

enum MatchPhase { buzzing, answering, reveal, roundComplete, finished }

class RoundConfig {
  const RoundConfig({
    required this.number,
    required this.title,
    required this.questions,
    required this.answerSeconds,
    required this.correctPoints,
    required this.wrongPoints,
    required this.fastBonus,
    required this.fastThreshold,
    required this.eliminate,
  });

  final int number;
  final String title;
  final int questions;
  final int answerSeconds;
  final int correctPoints;
  final int wrongPoints;
  final int fastBonus;
  final double fastThreshold;
  final int eliminate;
}

const kRounds = <RoundConfig>[
  RoundConfig(
    number: 1,
    title: 'The Qualifier',
    questions: 8,
    answerSeconds: 10,
    correctPoints: 2,
    wrongPoints: -1,
    fastBonus: 0,
    fastThreshold: 0,
    eliminate: 2,
  ),
  RoundConfig(
    number: 2,
    title: 'Speed Surge',
    questions: 6,
    answerSeconds: 7,
    correctPoints: 3,
    wrongPoints: -2,
    fastBonus: 1,
    fastThreshold: 3.5,
    eliminate: 2,
  ),
  RoundConfig(
    number: 3,
    title: 'Master Duel',
    questions: 15,
    answerSeconds: 10,
    correctPoints: 0,
    wrongPoints: 0,
    fastBonus: 0,
    fastThreshold: 0,
    eliminate: 0,
  ),
];

/// Local, single-device practice match implementing all three Buzz Masters
/// rounds. It is deliberately NOT a networked match: opponents are clearly
/// CPU-driven and no results are written to a server.
class PracticeMatch extends ChangeNotifier {
  PracticeMatch()
      : this._(
          cpuEnabled: true,
          startingRound: 1,
          activeContestantIndices: null,
          startingSuddenDeath: false,
        );

  @visibleForTesting
  PracticeMatch.forTesting({
    int startingRound = 1,
    Set<int>? activeContestantIndices,
    bool startingSuddenDeath = false,
  }) : this._(
          cpuEnabled: false,
          startingRound: startingRound,
          activeContestantIndices: activeContestantIndices,
          startingSuddenDeath: startingSuddenDeath,
        );

  PracticeMatch._({
    required bool cpuEnabled,
    required int startingRound,
    required Set<int>? activeContestantIndices,
    required bool startingSuddenDeath,
  }) : _cpuEnabled = cpuEnabled {
    contestants = [
      Contestant(name: 'Alex', isHuman: true, color: BmColors.seatColors[0]),
      Contestant(name: 'Sophie', isHuman: false, color: BmColors.seatColors[1]),
      Contestant(name: 'Jordan', isHuman: false, color: BmColors.seatColors[2]),
      Contestant(name: 'Emma', isHuman: false, color: BmColors.seatColors[3]),
      Contestant(name: 'Liam', isHuman: false, color: BmColors.seatColors[4]),
      Contestant(name: 'Chloe', isHuman: false, color: BmColors.seatColors[5]),
    ];
    roundIndex = startingRound - 1;
    if (activeContestantIndices != null) {
      for (var i = 0; i < contestants.length; i++) {
        contestants[i].eliminated = !activeContestantIndices.contains(i);
      }
    }
    suddenDeath = startingSuddenDeath;
    _shuffleBag();
    _beginRound();
  }

  final bool _cpuEnabled;
  late final List<Contestant> contestants;

  final _random = Random();
  final List<QuizQuestion> _bag = [];
  int _bagIndex = 0;

  RoundConfig get config => kRounds[roundIndex];
  int roundIndex = 0;
  int questionNumber = 1;
  int questionsPlayed = 0;

  MatchPhase phase = MatchPhase.buzzing;
  QuizQuestion? question;
  int correctIndex = 0;
  int? activeIndex;
  int? selectedIndex;
  int? revealedIndex;
  int? buzzedIndex;
  bool humanLockedOut = false;
  bool suddenDeath = false;
  bool _retryBuzz = false;

  double timeLeft = 4;
  double total = 4;
  String? lastResult;

  /// Human player's buzz time in seconds, used for the fast-answer bonus.
  double _answerStartedAt = 0;
  double _elapsed = 0;

  final Set<int> _lockedOut = {};
  double _cpuThink = 0;
  Timer? _ticker;

  List<Contestant> get active =>
      contestants.where((c) => !c.eliminated).toList();
  Contestant get human => contestants.first;
  bool get isFinished => phase == MatchPhase.finished;
  bool get canBuzz =>
      phase == MatchPhase.buzzing &&
      !humanLockedOut &&
      !contestants.first.eliminated;

  Contestant? get winner => phase == MatchPhase.finished
      ? active.isEmpty
          ? null
          : active.first
      : null;

  void _shuffleBag() {
    final list = [...kPracticeQuestions]..shuffle(_random);
    _bag
      ..clear()
      ..addAll(list);
    _bagIndex = 0;
  }

  QuizQuestion _nextQuestion() {
    if (_bagIndex >= _bag.length) _shuffleBag();
    return _bag[_bagIndex++];
  }

  void _beginRound() {
    for (final c in contestants) {
      c.score = 0;
    }
    if (config.number == 3) {
      for (final c in contestants) {
        c.energy = 5;
      }
    }
    questionNumber = 1;
    questionsPlayed = 0;
    _lockedOut.clear();
    _prepareQuestion();
    _startTicker();
  }

  void _prepareQuestion() {
    final q = _nextQuestion();
    // Shuffle the answer order so the correct letter varies each time.
    final indexed = q.options.asMap().entries.toList()..shuffle(_random);
    question = QuizQuestion(
      id: q.id,
      category: q.category,
      difficulty: q.difficulty,
      text: q.text,
      options: indexed.map((e) => e.value).toList(),
      correctIndex: indexed.indexWhere((e) => e.key == q.correctIndex),
      explanation: q.explanation,
    );
    correctIndex = question!.correctIndex;
    phase = MatchPhase.buzzing;
    activeIndex = null;
    selectedIndex = null;
    revealedIndex = null;
    buzzedIndex = null;
    lastResult = null;
    humanLockedOut = false;
    _lockedOut.clear();
    timeLeft = 4.0;
    total = 4.0;
    _elapsed = 0;
    _cpuThink = 0.8 + _random.nextDouble() * 2.0;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  /// Advances the match clock in 0.1s steps. Used by gameplay tests only.
  @visibleForTesting
  void advanceSecondsForTesting(double seconds) {
    final steps = (seconds / 0.1).round();
    for (var i = 0; i < steps && !isFinished; i++) {
      _tick();
    }
  }

  void _tick() {
    if (isFinished) return;
    _elapsed += 0.1;
    timeLeft = (timeLeft - 0.1).clamp(0, 999);

    switch (phase) {
      case MatchPhase.buzzing:
        if (!_cpuEnabled) {
          if (timeLeft <= 0) _noBuzz();
          break;
        }
        _cpuThink -= 0.1;
        if (_cpuThink <= 0) {
          _cpuBuzz();
        } else if (timeLeft <= 0) {
          _noBuzz();
        }
        break;
      case MatchPhase.answering:
        if (activeIndex != null && !contestants[activeIndex!].isHuman) {
          if (_cpuEnabled) {
            _cpuThink -= 0.1;
            if (_cpuThink <= 0) _cpuAnswers(contestants[activeIndex!]);
          }
        } else if (timeLeft <= 0) {
          _resolve(null, timedOut: true);
        }
        break;
      case MatchPhase.reveal:
        if (timeLeft <= 0) {
          if (_retryBuzz) {
            _reopenBuzz();
          } else {
            _advance();
          }
        }
        break;
      case MatchPhase.roundComplete:
      case MatchPhase.finished:
        break;
    }
    notifyListeners();
  }

  void _cpuBuzz() {
    final eligible = active
        .where((c) => !_lockedOut.contains(contestants.indexOf(c)))
        .where((c) => !c.isHuman)
        .toList();
    if (eligible.isEmpty) {
      if (timeLeft > 0) {
        _cpuThink = 5;
        return;
      }
      _noBuzz();
      return;
    }
    final pick = eligible[_random.nextInt(eligible.length)];
    _beginAnswer(contestants.indexOf(pick));
  }

  void _noBuzz() {
    phase = MatchPhase.reveal;
    revealedIndex = correctIndex;
    lastResult = 'No one buzzed in time';
    timeLeft = 2;
    total = 2;
  }

  /// Called by the UI when the human taps the buzzer.
  void buzz() {
    if (!canBuzz) return;
    _beginAnswer(0);
    notifyListeners();
  }

  void _beginAnswer(int index) {
    // Each newly selected contestant gets a fresh attempt. Failed attempts are
    // recorded in _lockedOut; the previous attempt's retry flag must not leak.
    _retryBuzz = false;
    phase = MatchPhase.answering;
    activeIndex = index;
    buzzedIndex = index;
    selectedIndex = null;
    revealedIndex = null;
    timeLeft = config.answerSeconds.toDouble();
    total = timeLeft;
    _answerStartedAt = _elapsed;
    _cpuThink = 1.4 + _random.nextDouble() * 2.2;
  }

  void submitAnswer(int optionIndex) {
    if (phase != MatchPhase.answering) return;
    if (activeIndex == null) return;
    _resolve(optionIndex);
    notifyListeners();
  }

  void _cpuAnswers(Contestant cpu) {
    // CPU accuracy: 70% in rounds 1-2, 62% in the duel.
    final accuracy = config.number == 3 ? 0.62 : 0.70;
    final isRight = _random.nextDouble() < accuracy;
    int choice = correctIndex;
    if (!isRight) {
      final wrongOptions =
          [0, 1, 2, 3].where((i) => i != correctIndex).toList();
      choice = wrongOptions[_random.nextInt(wrongOptions.length)];
    }
    _resolve(choice);
  }

  void _resolve(int? answer, {bool timedOut = false}) {
    final index = activeIndex;
    if (index == null) return;
    final contestant = contestants[index];
    final isCorrect = answer != null && answer == correctIndex;
    final elapsed = _elapsed - _answerStartedAt;

    selectedIndex = answer;
    revealedIndex = correctIndex;

    if (config.number == 3) {
      _resolveDuel(contestant, isCorrect);
      if (_retryBuzz) {
        phase = MatchPhase.reveal;
        timeLeft = 1.4;
        total = 1.4;
        return;
      }
    } else if (isCorrect) {
      contestant.score += config.correctPoints;
      contestant.correct += 1;
      if (config.fastBonus > 0 &&
          elapsed <= config.fastThreshold &&
          contestant.isHuman) {
        contestant.score += config.fastBonus;
      }
      lastResult = '${contestant.name} scores ${config.correctPoints}';
    } else {
      if (!timedOut) {
        contestant.score += config.wrongPoints;
        contestant.wrong += 1;
      }
      lastResult = timedOut
          ? '${contestant.name} timed out'
          : '${contestant.name} answers wrong (${config.wrongPoints})';
      // A wrong answer re-opens the buzzer for the remaining contestants.
      if (!timedOut && _lockedOut.length < active.length - 1) {
        _lockedOut.add(index);
        _retryBuzz = true;
        phase = MatchPhase.reveal;
        timeLeft = 1.4;
        total = 1.4;
        return;
      }
    }

    _retryBuzz = false;
    phase = MatchPhase.reveal;
    timeLeft = 1.8;
    total = 1.8;
  }

  void _reopenBuzz() {
    _retryBuzz = false;
    phase = MatchPhase.buzzing;
    activeIndex = null;
    selectedIndex = null;
    revealedIndex = null;
    buzzedIndex = null;
    humanLockedOut = _lockedOut.contains(0);
    timeLeft = 4.0;
    total = 4.0;
    _cpuThink = 0.8 + _random.nextDouble() * 2.0;
  }

  void _resolveDuel(Contestant contestant, bool isCorrect) {
    final opponent = contestants.firstWhere(
      (c) => !c.eliminated && c != contestant,
      orElse: () => contestant,
    );
    if (isCorrect) {
      contestant.correct += 1;
      if (suddenDeath) {
        opponent.eliminated = true;
        lastResult = '${contestant.name} wins sudden death!';
      } else {
        opponent.energy = (opponent.energy - 1).clamp(0, 5);
        lastResult = '${contestant.name} hits — ${opponent.name} loses energy';
      }
    } else {
      contestant.wrong += 1;
      lastResult = '${contestant.name} misses — ${opponent.name} may strike';
      final index = contestants.indexOf(contestant);
      if (_lockedOut.length < active.length - 1) {
        _lockedOut.add(index);
        _retryBuzz = true;
      }
    }
  }

  void _advance() {
    final duel = config.number == 3;

    if (duel) {
      final finalists = active;
      if (finalists.length < 2 || finalists.any((c) => c.energy <= 0)) {
        _finishDuel();
        return;
      }
      questionsPlayed += 1;
      if (questionsPlayed >= 15) suddenDeath = true;
      questionNumber += 1;
      _prepareQuestion();
      return;
    }

    _lockedOut.clear();
    questionsPlayed += 1;
    if (questionsPlayed >= config.questions) {
      _completeRound();
      return;
    }
    questionNumber += 1;
    _prepareQuestion();
  }

  void _completeRound() {
    for (final c in contestants) {
      c.totalScore += c.score;
    }
    final ranked = active.toList()..sort((a, b) => b.score.compareTo(a.score));
    final eliminate = config.eliminate;
    for (var i = ranked.length - eliminate; i < ranked.length; i++) {
      if (i >= 0) ranked[i].eliminated = true;
    }
    activeIndex = null;
    phase = MatchPhase.roundComplete;
    timeLeft = 0;
  }

  /// Continue from the round-complete screen into the next round.
  void nextRound() {
    if (roundIndex >= kRounds.length - 1) {
      _finishDuel(finalRound: true);
      return;
    }
    roundIndex += 1;
    _beginRound();
    notifyListeners();
  }

  void _finishDuel({bool finalRound = false}) {
    final finalists = active;
    if (finalists.length == 2) {
      finalists.sort((a, b) => a.energy.compareTo(b.energy));
      finalists.first.eliminated = true;
    }
    phase = MatchPhase.finished;
    _ticker?.cancel();
    timeLeft = 0;
  }

  void restart() {
    _ticker?.cancel();
    roundIndex = 0;
    suddenDeath = false;
    _retryBuzz = false;
    for (final c in contestants) {
      c
        ..score = 0
        ..totalScore = 0
        ..energy = 5
        ..eliminated = false
        ..correct = 0
        ..wrong = 0;
    }
    _shuffleBag();
    _beginRound();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
