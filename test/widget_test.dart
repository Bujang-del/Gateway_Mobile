import 'package:flutter_test/flutter_test.dart';

import 'package:gateway_mobile/main.dart';
import 'package:gateway_mobile/screens/login_screen.dart';

void main() {
  testWidgets('shows loading screen before login page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GatewayMobileApp());

    expect(find.text('Gateway Mobile'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Selamat datang kembali'), findsOneWidget);
    expect(
      find.textContaining('Akun dibuat melalui invitation dari HR'),
      findsOneWidget,
    );
  });
}
