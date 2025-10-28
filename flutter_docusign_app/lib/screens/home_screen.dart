import 'package:flutter/material.dart';
import 'package:flutter_docusign_app/screens/pdf_viewer_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: ElevatedButton(
          child: const Text('Open PDF Viewer (placeholder)'),
          onPressed: () =>
              Navigator.pushNamed(context, PdfViewerScreen.routeName),
        ),
      ),
    );
  }
}
