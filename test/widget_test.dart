import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_image_studio/main.dart';

void main() {
  testWidgets('App launches into the studio shell', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AiImageStudioApp());
    await tester.pump();

    // The shell renders its four destinations, with Studio selected.
    expect(find.text('Studio'), findsWidgets);
    expect(find.text('Batch'), findsWidgets);
    expect(find.text('Gallery'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    // Studio shows the prompt box and its primary action.
    expect(find.text('Generate'), findsOneWidget);
  });
}
