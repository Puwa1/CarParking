import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'location_selection_screen.dart'; // import หน้าจอเลือกสถานที่
import 'parking_dashboard.dart';        // import หน้าจอ dashboard

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://dgqqonbhhivprdoutkzp.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRncXFvbmJoaGl2cHJkb3V0a3pwIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1MTU0MTg2MywiZXhwIjoyMDY3MTE3ODYzfQ.CmqI4-zRpvhasNYW1BOYYloMGRZlbySPr_ESyU1RBm0',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parking Dashboard',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'Roboto', color: Colors.white70),
          bodyMedium: TextStyle(fontFamily: 'Roboto', color: Colors.white70),
          titleLarge: TextStyle(fontFamily: 'Roboto', color: Colors.white),
        ),
      ),
      home: const LocationSelectionScreen(), // เปลี่ยนหน้าแรก
      debugShowCheckedModeBanner: false,
    );
  }
}