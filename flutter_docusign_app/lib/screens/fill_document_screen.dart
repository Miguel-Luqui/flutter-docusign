import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as px;
import 'package:flutter_docusign_app/widgets/signature_pad.dart';
import 'package:flutter_docusign_app/helpers/pdf_field_utils.dart';

// Tela para preencher campos do PDF e aplicar assinatura/checkboxes
class FillDocumentScreen extends StatefulWidget {
  final Uint8List originalPdfBytes;
  const FillDocumentScreen({super.key, required this.originalPdfBytes});

  @override
  State<FillDocumentScreen> createState() => _FillDocumentScreenState();
}

class _FillDocumentScreenState extends State<FillDocumentScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _checkboxValues = {};
  Uint8List? _signature;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _extractFields();
  }

  // Extrai campos do formulário e popula controladores/checkboxes
  Future<void> _extractFields() async {
    setState(() => _loading = true);
    _controllers.clear();
    _checkboxValues.clear();
    try {
      final res = await extractFormFields(widget.originalPdfBytes);
      final Map<String, String> texts = Map<String, String>.from(res['texts'] ?? {});
      final Map<String, bool> checks = Map<String, bool>.from(res['checkboxes'] ?? {});

      for (final e in texts.entries) {
        _controllers[e.key] = TextEditingController(text: e.value);
      }
      for (final e in checks.entries) {
        _checkboxValues[e.key] = e.value;
      }
    } catch (_) {}
    finally {
      setState(() => _loading = false);
    }
  }

  // Abre a tela de captura de assinatura tentando inferir proporção do campo
  Future<void> _openSignaturePad() async {
    double? aspectRatio;
    try {
      aspectRatio = await inferSignatureAspectRatio(widget.originalPdfBytes);
    } catch (_) {
      aspectRatio = null;
    }

    final Uint8List? bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
          builder: (_) => SignaturePadScreen(targetAspectRatio: aspectRatio)),
    );
    if (bytes != null) setState(() => _signature = bytes);
  }

  // Constrói o PDF preenchido, aplica checkboxes e coloca a assinatura
  Future<Uint8List> _buildPdfWithValuesAndSignature() async {
    final Map<String, String> texts = {};
    _controllers.forEach((k, v) => texts[k] = v.text);
    final Map<String, bool> checks = Map<String, bool>.from(_checkboxValues);
    return await buildPdfWithValuesAndSignature(widget.originalPdfBytes, texts, checks, _signature);
  }

  // converte valores numéricos tolerantes
  

  Future<void> _onPreview() async {
    setState(() => _loading = true);
    try {
      final bytes = await _buildPdfWithValuesAndSignature();
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PdfViewerScreen(pdfBytes: bytes),
      ));
    } catch (_) {}
    finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fill Document'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'preview_fab',
        label: const Text('Preview'),
        icon: const Icon(Icons.visibility),
        onPressed: _onPreview,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  ..._controllers.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TextField(
                        controller: e.value,
                        decoration: InputDecoration(
                          labelText: e.key,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                  // renderiza checkboxes
                  ..._checkboxValues.entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: CheckboxListTile(
                        title: Text(entry.key),
                        value: _checkboxValues[entry.key] ?? false,
                        onChanged: (v) => setState(() => _checkboxValues[entry.key] = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _openSignaturePad,
                    child: const Text('Sign document'),
                  ),
                ]
              ],
            ),
          ),
          if (_loading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

// Visualizador simples de PDF (usando pdfx)
class PdfViewerScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  const PdfViewerScreen({super.key, required this.pdfBytes});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  px.PdfControllerPinch? _controller;

  @override
  void initState() {
    super.initState();
    _controller = px.PdfControllerPinch(document: px.PdfDocument.openData(widget.pdfBytes));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualizar PDF'),
      ),
      body: widget.pdfBytes.isEmpty
          ? const Center(child: Text('PDF vazio'))
          : px.PdfViewPinch(controller: _controller!, scrollDirection: Axis.vertical),
    );
  }
}
