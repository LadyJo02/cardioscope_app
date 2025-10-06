// This is a basic Flutter widget test.

import 'package:cardioscope_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Onboarding screen shows up for first-time users', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // We pass the required arguments to simulate a first-time user.
    await tester.pumpWidget(const CardioScopeApp(
      hasSeenOnboarding: false,
      isLoggedIn: false,
    ));

    // Verify that the first screen of the onboarding carousel is visible.
    // We check for the title text of the first slide.
    expect(find.text('Welcome to CardioScope'), findsOneWidget);

    // Verify that a widget from the login or main app screen is NOT visible.
    expect(find.byIcon(Icons.person_outline), findsNothing);
  });
}