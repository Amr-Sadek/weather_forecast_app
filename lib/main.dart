import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const WeatherApp());
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Weather Forecast',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2B83C6),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const HomeScreen(),
    );
  }
}
