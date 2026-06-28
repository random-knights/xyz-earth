import 'package:flutter/material.dart';

import 'package:xyz_earth/app/home_page.dart';

void main() {
  runApp(const XyzEarthApp());
}

/// Keyless, open-source living globe + Planet Health Score for rand0m.ai.
///
/// Reads ONLY public rand0m.ai Storage over plain HTTPS and falls back to
/// bundled representative data — no Firebase, no auth, no secrets.
class XyzEarthApp extends StatelessWidget {
  const XyzEarthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'rand0m · xyz-earth',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05070C),
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF05070C),
          primary: Color(0xFFBBA8FF),
        ),
      ),
      home: const EarthHomePage(),
    );
  }
}
