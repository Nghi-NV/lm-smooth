// test_driver/perf_driver.dart
//
// Runs integration tests and exports timeline summary.
// Usage:
//   flutter drive \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/scroll_perf_test.dart \
//     --profile

import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      if (data != null) {
        // Write timeline summaries for each test
        for (final entry in data.entries) {
          final timeline = driver.Timeline.fromJson(
            entry.value as Map<String, dynamic>,
          );
          final summary = driver.TimelineSummary.summarize(timeline);

          await summary.writeTimelineToFile(
            entry.key,
            pretty: true,
            includeSummary: true,
          );
        }
      }
    },
  );
}
