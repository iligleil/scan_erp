import 'package:flutter/material.dart';

import 'screens/document_list_screen.dart';

void main() => runApp(const ScanErpApp());

class ScanErpApp extends StatelessWidget {
  const ScanErpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Calibri',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003387),
          primary: const Color(0xFF003387),
          secondary: const Color(0xFF43B02A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF003387),
          foregroundColor: Colors.white,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      home: const DocumentListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
