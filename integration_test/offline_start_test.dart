// Starting with no way to reach the API: the offline screen and its Try again button.
//
//   flutter test integration_test/offline_start_test.dart -d <device> \
//     --dart-define=API_BASE_URL=http://localhost:9/api/v1

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/device.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline at launch shows the offline screen, and Try again stays calm', (tester) async {
    await startApp(tester);
    await waitFor(tester, find.text('You seem to be offline'));
    expect(find.text('Could not reach Tadka Lane. Check your connection and try again.'), findsOneWidget);
    await shot(tester, '16-offline');
    await tapOn(tester, find.text('Try again'));
    await waitFor(tester, find.text('You seem to be offline'));
  });
}
