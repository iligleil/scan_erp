import 'package:flutter_test/flutter_test.dart';

import 'package:scan_erp/main.dart';

void main() {
  testWidgets('Стартовый экран документов отображается', (WidgetTester tester) async {
    await tester.pumpWidget(const ScanErpApp());
    await tester.pumpAndSettle();

    expect(find.text('Документы инвентаризации'), findsOneWidget);
    expect(find.textContaining('Нажмите «+»'), findsOneWidget);
  });
}
