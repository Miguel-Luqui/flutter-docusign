import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

// prefixar imports para evitar ambiguidade
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'package:pdfx/pdfx.dart' as px;
import 'package:flutter_docusign_app/widgets/signature_pad.dart';

class PdfViewerScreen extends StatefulWidget {
  static const String routeName = '/pdf-viewer';
  const PdfViewerScreen({super.key});
  @override
  _PdfViewerScreenState createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  Uint8List? _originalPdfBytes;
  Uint8List? _signatureImage;
  final Map<String, TextEditingController> _fieldControllers = {};
  final String signatureFieldName = 'assinatura_cliente';
  bool _loading = true;

  px.PdfControllerPinch? _pdfController;

  @override
  void initState() {
    super.initState();
    _loadPdfFromAssets();
  }

  Future<void> _loadPdfFromAssets() async {
    setState(() => _loading = true);
    final bytes = await rootBundle.load('assets/sample_form.pdf');
    _originalPdfBytes = bytes.buffer.asUint8List();
    await _extractFormFields();
    // inicializa controller do pdfx (abre em memória) — passe a Future, NÃO await
    _pdfController?.dispose();
    if (_originalPdfBytes != null) {
      _pdfController = px.PdfControllerPinch(
          document: px.PdfDocument.openData(_originalPdfBytes!));
    }
    setState(() => _loading = false);
  }

  Future<void> _extractFormFields() async {
    _fieldControllers.clear();
    if (_originalPdfBytes == null) return;

    final sfpdf.PdfDocument loaded =
        sfpdf.PdfDocument(inputBytes: _originalPdfBytes!);
    final sfpdf.PdfForm? form = loaded.form;
    if (form != null) {
      for (int i = 0; i < form.fields.count; i++) {
        final sfpdf.PdfField f = form.fields[i];
        final String name = f.name ?? 'field_$i';
        String initial = '';
        try {
          if (f is sfpdf.PdfTextBoxField) {
            initial = (f).text ?? '';
          }
        } catch (_) {}
        _fieldControllers[name] = TextEditingController(text: initial);
      }
    }
    loaded.dispose();
  }

  Future<void> _openSignaturePad() async {
    final Uint8List? bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const SignaturePadScreen()),
    );
    if (bytes != null) {
      setState(() => _signatureImage = bytes);
      // NÃO recarregamos o viewer — ele continua mostrando o PDF original
    }
  }

  void _removeSignature() {
    setState(() => _signatureImage = null);
    // NÃO recarregamos o viewer
  }

  Future<String> _generatePdfWithEdits() async {
    if (_originalPdfBytes == null) throw Exception('PDF not loaded');

    final sfpdf.PdfDocument loaded =
        sfpdf.PdfDocument(inputBytes: _originalPdfBytes!);
    final sfpdf.PdfForm? form = loaded.form;

    // Preencher campos de texto
    if (form != null) {
      for (int i = 0; i < form.fields.count; i++) {
        final sfpdf.PdfField f = form.fields[i];
        final String name = f.name ?? '';
        if (_fieldControllers.containsKey(name)) {
          final value = _fieldControllers[name]!.text;
          try {
            if (f is sfpdf.PdfTextBoxField) {
              (f).text = value;
            }
          } catch (_) {}
        }
      }
    }

    // Desenhar assinatura sobre primeiros campos com nome correspondente (tentativa dinâmica + fallback)
    if (_signatureImage != null && form != null) {
      final sfpdf.PdfBitmap sigBitmap = sfpdf.PdfBitmap(_signatureImage!);
      bool applied = false;
      for (int i = 0; i < form.fields.count; i++) {
        final sfpdf.PdfField f = form.fields[i];
        final String name = f.name ?? '';
        if (name == signatureFieldName) {
          try {
            final dyn = f as dynamic;
            dynamic rect;
            int? pageIndex;
            try {
              rect = dyn.bounds;
            } catch (_) {
              try {
                rect = dyn.rectangle;
              } catch (_) {
                rect = null;
              }
            }
            try {
              pageIndex = dyn.pageIndex as int?;
            } catch (_) {
              pageIndex = null;
            }

            if (rect != null &&
                pageIndex != null &&
                pageIndex >= 0 &&
                pageIndex < loaded.pages.count) {
              final sfpdf.PdfPage page = loaded.pages[pageIndex];
              double x = 0, y = 0, w = 180, h = 80;
              try {
                x = (rect.left ?? rect.x ?? 0).toDouble();
              } catch (_) {}
              try {
                y = (rect.top ?? rect.y ?? 0).toDouble();
              } catch (_) {}
              try {
                w = (rect.width ?? 180).toDouble();
              } catch (_) {}
              try {
                h = (rect.height ?? 80).toDouble();
              } catch (_) {}
              page.graphics.drawImage(sigBitmap, Rect.fromLTWH(x, y, w, h));
              applied = true;
            }
          } catch (e) {
            debugPrint('Erro ao aplicar assinatura no campo $name: $e');
            continue;
          }
        }
      }

      if (!applied && loaded.pages.count > 0) {
        try {
          final sfpdf.PdfPage page = loaded.pages[0];
          const double w = 180.0;
          const double h = 80.0;
          final double x = page.size.width - w - 40.0;
          final double y = page.size.height - h - 40.0;
          page.graphics.drawImage(sigBitmap, Rect.fromLTWH(x, y, w, h));
        } catch (_) {}
      }
    }

    try {
      loaded.form?.flattenAllFields();
    } catch (_) {}

    final List<int> outBytes = await loaded.save();
    loaded.dispose();

    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/signed_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(outBytes, flush: true);
    return file.path;
  }

  @override
  void dispose() {
    for (final c in _fieldControllers.values) c.dispose();
    _pdfController?.dispose();
    super.dispose();
  }

  Widget _buildFieldsList() {
    if (_fieldControllers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: Text('Nenhum campo de formulário detectado no PDF.'),
      );
    }
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: _fieldControllers.entries.map((entry) {
        final name = entry.key;
        final controller = entry.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          child: TextField(
            controller: controller,
            // NÃO atualizamos o viewer enquanto digita
            decoration: InputDecoration(
              labelText: name,
              border: const OutlineInputBorder(),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Viewer / Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Recarregar PDF',
            onPressed: _loadPdfFromAssets,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Gerar PDF final',
            onPressed: () async {
              setState(() => _loading = true);
              try {
                final path = await _generatePdfWithEdits();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('PDF salvo: $path'),
                  action: SnackBarAction(
                    label: 'Abrir',
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PdfPreviewScreen(path: path),
                      ));
                    },
                  ),
                ));
              } catch (e) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Erro: $e')));
              } finally {
                setState(() => _loading = false);
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // viewer permanece sempre com o PDF original
                  if (_originalPdfBytes != null && _pdfController != null)
                    SizedBox(
                      height: 420,
                      child: px.PdfViewPinch(
                        controller: _pdfController!,
                        scrollDirection: Axis.vertical,
                      ),
                    )
                  else
                    Container(
                      height: 420,
                      color: Colors.grey.shade200,
                      child: const Center(child: Text('PDF não carregado')),
                    ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.start,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text('Assinar'),
                          onPressed: _openSignaturePad,
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.remove_circle),
                          label: const Text('Remover assinatura'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent),
                          onPressed:
                              _signatureImage != null ? _removeSignature : null,
                        ),
                        if (_signatureImage != null)
                          SizedBox(
                            width: 160,
                            height: 56,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              child: Image.memory(
                                _signatureImage!,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFieldsList(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
    );
  }
}

class PdfPreviewScreen extends StatelessWidget {
  final String path;
  const PdfPreviewScreen({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Salvo'),
      ),
      body: Center(
        child: ElevatedButton(
          child: const Text('Abrir PDF'),
          onPressed: () async {
            try {
              final file = File(path);
              if (await file.exists()) {
                final controller = px.PdfControllerPinch(
                    document: px.PdfDocument.openFile(path));
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Visualizador de PDF')),
                    body: px.PdfViewPinch(
                        controller: controller, scrollDirection: Axis.vertical),
                  ),
                ));
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erro ao abrir PDF: $e')));
            }
          },
        ),
      ),
    );
  }
}
