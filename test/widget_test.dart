import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meta_hawaladar_image_generator/main.dart';

void main() {
  testWidgets('App launches into the studio shell', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MetaHawaladarApp());
    await tester.pump();

    // The shell renders its five destinations, with Studio selected.
    expect(find.text('Studio'), findsWidgets);
    expect(find.text('Batch'), findsWidgets);
    expect(find.text('Dola'), findsWidgets);
    expect(find.text('Gallery'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    // Studio shows the prompt box and its primary action.
    expect(find.text('Generate'), findsOneWidget);
  });
}
