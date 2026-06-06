final RegExp _usernamePattern = RegExp(r'^[A-Za-z0-9._-]+$');
final RegExp _emailPattern = RegExp(r'^[a-z0-9._%+\-]+@[a-z0-9\-]+(\.[a-z0-9\-]+)+$');

String normalizeEmail(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._%+\-@]'), '');
}

String normalizeUsername(String value) {
  return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
}

String normalizeCity(String value) {
  return value.replaceAll(RegExp(r'[^А-Яа-яЁё\s,\-]'), '');
}

String normalizeName(String value, String script) {
  if (script == 'latin') {
    return value.replaceAll(RegExp(r'[^A-Za-z\s\-]'), '');
  }
  if (script == 'cyrillic') {
    return value.replaceAll(RegExp(r'[^А-Яа-яЁё\s\-]'), '');
  }
  return value.replaceAll(RegExp(r'[^A-Za-zА-Яа-яЁё\s\-]'), '');
}

String detectNameScript(String value) {
  if (RegExp(r'[A-Za-z]').hasMatch(value)) {
    return 'latin';
  }
  if (RegExp(r'[А-Яа-яЁё]').hasMatch(value)) {
    return 'cyrillic';
  }
  return '';
}

String currentNameScript(Iterable<String> values) {
  for (final value in values) {
    final script = detectNameScript(value);
    if (script.isNotEmpty) {
      return script;
    }
  }
  return '';
}

bool hasConsistentNameScript(Iterable<String> values) {
  final script = currentNameScript(values);
  if (script.isEmpty) {
    return true;
  }

  for (final value in values) {
    final detected = detectNameScript(value);
    if (detected.isNotEmpty && detected != script) {
      return false;
    }
  }

  return true;
}

bool isValidEmail(String value) {
  if (value.isEmpty || value.contains(RegExp(r'\s'))) {
    return false;
  }
  final parts = value.split('@');
  if (parts.length != 2) {
    return false;
  }
  final domainPart = parts[1];
  final dotIndex = domainPart.lastIndexOf('.');
  if (dotIndex <= 0 || (domainPart.length - dotIndex - 1) < 2) {
    return false;
  }
  return _emailPattern.hasMatch(value);
}

bool isValidUsername(String value) {
  return value.isNotEmpty && _usernamePattern.hasMatch(value);
}

bool isValidPassword(String value) {
  if (value.trim() != value) {
    return false;
  }

  return value.length >= 10 &&
      RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(value) &&
      RegExp(r'\d').hasMatch(value) &&
      RegExp(r'[^A-Za-zА-Яа-яЁё\d\s]').hasMatch(value);
}

bool isValidCity(String value) {
  return value.isNotEmpty && RegExp(r'^[А-Яа-яЁё\s,\-]+$').hasMatch(value);
}

bool isValidHumanName(String value) {
  return value.isNotEmpty &&
      RegExp(r'^[A-Za-zА-Яа-яЁё\s\-]+$').hasMatch(value);
}

String normalizePhoneDigits(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('7') && digits.length == 11) {
    return digits.substring(1);
  }
  return digits.length > 10 ? digits.substring(0, 10) : digits;
}

String formatPhone(String value) {
  final digits = normalizePhoneDigits(value);
  final buffer = StringBuffer();

  if (digits.isNotEmpty) {
    buffer.write('(');
    buffer.write(digits.substring(0, _min(digits.length, 3)));
  }
  if (digits.length >= 4) {
    buffer.write(') ');
    buffer.write(digits.substring(3, _min(digits.length, 6)));
  }
  if (digits.length >= 7) {
    buffer.write('-');
    buffer.write(digits.substring(6, _min(digits.length, 8)));
  }
  if (digits.length >= 9) {
    buffer.write('-');
    buffer.write(digits.substring(8, _min(digits.length, 10)));
  }

  return buffer.toString();
}

int _min(int a, int b) => a < b ? a : b;
