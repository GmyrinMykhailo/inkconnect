import 'dart:convert';

import 'package:flutter/services.dart';

class CityOption {
  const CityOption({
    required this.name,
    required this.subject,
    required this.displayName,
  });

  final String name;
  final String subject;
  final String displayName;
}

class CityCatalog {
  CityCatalog._();

  static final CityCatalog instance = CityCatalog._();

  static const _assetPath = 'assets/data/russian-cities.json';

  Future<List<CityOption>>? _loadFuture;
  List<CityOption> _items = const <CityOption>[];

  Future<List<CityOption>> load() {
    return _loadFuture ??= _load();
  }

  Future<List<CityOption>> _load() async {
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw) as List<dynamic>;
    final seen = <String>{};
    final items = <CityOption>[];

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final name = (item['name'] as String? ?? '').trim();
      final subject = (item['subject'] as String? ?? '').trim();
      if (name.isEmpty) {
        continue;
      }
      final displayName = formatDisplayName(name: name, subject: subject);
      final key = _normalize(displayName);
      if (!seen.add(key)) {
        continue;
      }
      items.add(CityOption(
        name: name,
        subject: subject,
        displayName: displayName,
      ));
    }

    _items = List.unmodifiable(items);
    return _items;
  }

  List<CityOption> search(String query, {int limit = 10}) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return const <CityOption>[];
    }

    final matches = _items.where((item) {
      return _normalize(item.name).contains(normalizedQuery) ||
          _normalize(item.subject).contains(normalizedQuery) ||
          _normalize(item.displayName).contains(normalizedQuery);
    }).toList();

    matches.sort((a, b) {
      final aName = _normalize(a.name);
      final bName = _normalize(b.name);
      final aDisplay = _normalize(a.displayName);
      final bDisplay = _normalize(b.displayName);
      final aStarts = aName.startsWith(normalizedQuery) ||
          aDisplay.startsWith(normalizedQuery);
      final bStarts = bName.startsWith(normalizedQuery) ||
          bDisplay.startsWith(normalizedQuery);
      if (aStarts != bStarts) {
        return aStarts ? -1 : 1;
      }
      return a.displayName.length.compareTo(b.displayName.length);
    });

    return matches.take(limit).toList(growable: false);
  }

  CityOption? findByDisplayName(String value) {
    final normalized = _normalize(value);
    if (normalized.isEmpty) {
      return null;
    }
    for (final item in _items) {
      if (_normalize(item.displayName) == normalized) {
        return item;
      }
    }
    return null;
  }

  static String formatDisplayName({
    required String name,
    required String subject,
  }) {
    final city = name.trim();
    final region = subject.trim();
    if (region.isEmpty || _normalize(region) == _normalize(city)) {
      return city;
    }
    return '$city, $region';
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
