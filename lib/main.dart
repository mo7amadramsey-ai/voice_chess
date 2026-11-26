import 'package:flutter/material.dart';
import 'ui/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoiceChessApp());
}

class VoiceChessApp extends StatelessWidget {
  const VoiceChessApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'شطرنج صوتي',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFFD4A24C),
          scaffoldBackgroundColor: const Color(0xFF0E0F13),
        ),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const GameScreen(),
      );
}
