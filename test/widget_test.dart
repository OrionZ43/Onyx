import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onyx/main.dart';

void main() {
  testWidgets('App launches and shows HomeScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OnyxApp()));
    await tester.pump();
  });
}
