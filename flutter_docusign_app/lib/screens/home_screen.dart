import 'package:flutter/material.dart';
import 'package:flutter_docusign_app/screens/document_focus_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: ElevatedButton(
          child: const Text('Open Document'),
          onPressed: () =>
              Navigator.pushNamed(context, DocumentFocusScreen.routeName),
        ),
      ),
    );
  }
}
