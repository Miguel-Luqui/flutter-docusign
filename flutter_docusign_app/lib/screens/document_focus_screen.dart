import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdfx/pdfx.dart' as px;
import 'package:flutter_docusign_app/screens/fill_document_screen.dart';

class DocumentFocusScreen extends StatefulWidget {
  const DocumentFocusScreen({super.key});
  static const String routeName = '/document-focus';

  @override
  State<DocumentFocusScreen> createState() => _DocumentFocusScreenState();
}

class _DocumentFocusScreenState extends State<DocumentFocusScreen> {
  Uint8List? _bytes;
  px.PdfControllerPinch? _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await rootBundle.load('assets/sample_form.pdf');
    _bytes = data.buffer.asUint8List();
    _controller?.dispose();
    if (_bytes != null) {
      _controller =
          px.PdfControllerPinch(document: px.PdfDocument.openData(_bytes!));
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                if (_bytes != null && _controller != null)
                  Positioned.fill(
                    child: px.PdfViewPinch(
                        controller: _controller!,
                        scrollDirection: Axis.vertical),
                  )
                else
                  const Center(child: Text('PDF não carregado')),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(
                    heroTag: 'fill_doc_btn',
                    label: const Text('Fill document'),
                    icon: const Icon(Icons.edit),
                    onPressed: () {
                      if (_bytes != null) {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              FillDocumentScreen(originalPdfBytes: _bytes!),
                        ));
                      }
                    },
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
    );
  }
}
