import 'package:flutter_test/flutter_test.dart';
import 'package:gps_bg/main.dart';

void main() {
  testWidgets('layar spike tampil dengan tombol Mulai', (tester) async {
    await tester.pumpWidget(const SpikeApp());
    expect(find.text('Arcline · Spike GPS'), findsOneWidget);
    expect(find.text('Mulai'), findsOneWidget);
    expect(find.text('Bagikan log (CSV)'), findsOneWidget);
    expect(find.textContaining('Siap'), findsOneWidget);
  });
}
