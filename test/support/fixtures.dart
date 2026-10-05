import 'dart:convert';
import 'dart:io';

import 'package:dinewise/core/api/api_client.dart';

/// Responses recorded from the real API (`docker compose up`, demo seed), in
/// `test/support/fixtures/`.
Json fixture(String name) =>
    jsonDecode(File('test/support/fixtures/$name.json').readAsStringSync()) as Json;

/// The demo menu. Photo URLs are dropped by default: widget tests have no network.
Json menuJson({bool photos = true}) {
  final menu = fixture('menu');
  if (!photos) {
    for (final section in menu['sections']! as List) {
      for (final item in (section as Json)['items']! as List) {
        (item as Json)['photoUrl'] = null;
      }
    }
  }
  return menu;
}
