import 'package:bureau_nakhodok/app.dart';
import 'package:bureau_nakhodok/data/screen_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog contains all approved screens', () {
    expect(userScreenSpecs, hasLength(40));
    expect(organizationScreenSpecs, hasLength(20));
    expect(adminScreenSpecs, hasLength(7));
    expect(allScreenSpecs, hasLength(67));
    expect(allScreenSpecs.map((screen) => screen.id).toSet(), hasLength(67));
  });

  testWidgets('app starts with onboarding', (tester) async {
    await tester.pumpWidget(const BureauNakhodokApp());
    expect(find.text('Бюро находок'), findsOneWidget);
    expect(find.text('Одна сеть для всей России'), findsOneWidget);
    expect(find.text('Далее'), findsOneWidget);
  });
}
