import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/garden_models.dart';

class QuoteService {
  QuoteService._();

  static List<GentleQuote>? _cache;
  static final _random = Random();

  static Future<GentleQuote> randomQuote() async {
    _cache ??= await _load();
    final quotes = _cache!;
    if (quotes.isEmpty) {
      throw const FormatException('gentle_quotes.json cannot be empty.');
    }
    return quotes[_random.nextInt(quotes.length)];
  }

  static Future<List<GentleQuote>> _load() async {
    final raw = await rootBundle.loadString('assets/data/gentle_quotes.json');
    final data = jsonDecode(raw) as List<dynamic>;
    return List.unmodifiable(
      data
          .map((item) => GentleQuote.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
