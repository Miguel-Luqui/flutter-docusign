import 'package:flutter/material.dart';
import 'package:flutter_docusign_app/screens/home_screen.dart';
import 'package:flutter_docusign_app/screens/document_focus_screen.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter DocuSign App (base)',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomeScreen(),
      routes: <String, WidgetBuilder>{
        DocumentFocusScreen.routeName: (_) => const DocumentFocusScreen(),
      },
    );
  }
}
