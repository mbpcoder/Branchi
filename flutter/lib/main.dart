import 'package:flutter/material.dart';

void main() {
  runApp(const RustGitApp());
}

class RustGitApp extends StatelessWidget {
  const RustGitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RustGit',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const WelcomeScreen(),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RustGit')),
      body: const Center(
        child: Text(
          'Welcome to RustGit',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
