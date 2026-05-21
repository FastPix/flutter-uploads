import 'package:flutter_test/flutter_test.dart';

import 'package:fastpix_resumable_uploader_example/main.dart';

void main() {
  testWidgets('App boots and shows upload screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FastPixUploaderExampleApp());

    expect(find.text('FastPix Resumable Uploader'), findsOneWidget);
    expect(find.text('Pick video from gallery'), findsOneWidget);
    expect(find.text('Upload to FastPix'), findsOneWidget);
  });
}
