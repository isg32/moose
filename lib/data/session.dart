/// Where this phone is: paired or not, locked or not, and whether the decoy
/// PIN opened it (C11–C14).
class Session {
  const Session({
    this.paired = true,
    this.locked = true,
    this.decoy = false,
    this.pin = '',
    this.decoyPin,
    this.decoyName = 'Neha',
    this.wrongTries = 0,
    this.waitUntil,
    this.name = '',
  });

  final bool paired;
  final bool locked;

  /// Opened with the decoy PIN: an empty, inert chat.
  final bool decoy;

  /// Empty when there is no app lock.
  final String pin;
  final String? decoyPin;
  final String decoyName;

  /// Wrong PINs in a row; five means a 30 s wait.
  final int wrongTries;
  final DateTime? waitUntil;

  /// The name typed in onboarding, before pairing.
  final String name;

  static const maxTries = 5;
  static const wait = Duration(seconds: 30);

  int get triesLeft => maxTries - wrongTries;

  Session copyWith({
    bool? paired,
    bool? locked,
    bool? decoy,
    String? pin,
    String? decoyPin,
    bool clearDecoyPin = false,
    String? decoyName,
    int? wrongTries,
    DateTime? waitUntil,
    bool clearWait = false,
    String? name,
  }) => Session(
    paired: paired ?? this.paired,
    locked: locked ?? this.locked,
    decoy: decoy ?? this.decoy,
    pin: pin ?? this.pin,
    decoyPin: clearDecoyPin ? null : decoyPin ?? this.decoyPin,
    decoyName: decoyName ?? this.decoyName,
    wrongTries: wrongTries ?? this.wrongTries,
    waitUntil: clearWait ? null : waitUntil ?? this.waitUntil,
    name: name ?? this.name,
  );
}

/// What a PIN attempt did.
enum Unlock { opened, decoy, wrong, waiting }
