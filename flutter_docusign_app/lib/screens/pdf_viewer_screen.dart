import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter_docusign_app/widgets/signature_pad.dart';

class PdfViewerScreen extends StatefulWidget {
  static const String routeName = '/pdf-viewer';

  const PdfViewerScreen({super.key});

  @override
  _PdfViewerScreenState createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  Uint8List? _originalPdfBytes;
  Uint8List? _signatureImage; // PNG bytes from SignaturePad
  final Map<String, TextEditingController> _fieldControllers = {};
  final String signatureFieldName =
      'assinatura_cliente'; // campo onde a assinatura será aplicada

  bool _loading = true;

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
    setState(() => _loading = false);
  }

  Future<void> _extractFormFields() async {
    _fieldControllers.clear();
    if (_originalPdfBytes == null) return;

    // Carrega o PDF com Syncfusion (documento carregado somente para ler campos)
    final PdfLoadedDocument loaded = PdfLoadedDocument(_originalPdfBytes!);
    final PdfLoadedForm? form = loaded.form;
    if (form != null) {
      for (int i = 0; i < form.fields.count; i++) {
        final PdfLoadedField f = form.fields[i];
        final String name = f.name ?? 'field_$i';
        // apenas textboxes serão editáveis aqui — você pode estender para combobox/checkbox
        String initial = '';
        try {
          if (f is PdfLoadedTextBoxField) {
            initial = f.text ?? '';
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
    if (bytes != null) setState(() => _signatureImage = bytes);
  }

  void _removeSignature() {
    setState(() => _signatureImage = null);
  }

  Future<String> _generatePdfWithEdits() async {
    if (_originalPdfBytes == null) throw Exception('PDF not loaded');

    final PdfLoadedDocument loaded = PdfLoadedDocument(_originalPdfBytes!);
    final PdfLoadedForm? form = loaded.form;

    // Preencher campos de texto
    if (form != null) {
      for (int i = 0; i < form.fields.count; i++) {
        final PdfLoadedField f = form.fields[i];
        final String name = f.name ?? '';
        if (_fieldControllers.containsKey(name)) {
          final value = _fieldControllers[name]!.text;
          try {
            if (f is PdfLoadedTextBoxField) {
              // Atualiza o valor do campo
              f.text = value;
            } else {
              // se não for textbox, apenas ignore ou implemente conforme necessidade
            }
          } catch (_) {}
        }
      }
    }

    // Se tiver assinatura, desenhe em todos os campos com o nome correspondente
    if (_signatureImage != null && form != null) {
      final PdfBitmap sigBitmap = PdfBitmap(_signatureImage!);
      for (int i = 0; i < form.fields.count; i++) {
        final PdfLoadedField f = form.fields[i];
        final String name = f.name ?? '';
        if (name == signatureFieldName) {
          // tenta obter página e bounds do campo
          try {
            if (f is PdfLoadedWidgetField) {
              final rect = f.bounds;
              final int pageIndex = f.pageIndex;
              final PdfLoadedPage page =
                  loaded.pages[pageIndex] as PdfLoadedPage;
              // Conversão de coordenadas: Pdf usa origem no canto inferior esquerdo
              final double x = rect.left;
              final double yFromTop = rect.top;
              final double height = rect.height;
              final double pageHeight = page.size.height;
              final double y =
                  pageHeight - yFromTop - height; // y para origem inferior
              // desenha a imagem e escala para caber no rect
              page.graphics.drawImage(
                sigBitmap,
                Rect.fromLTWH(x, y, rect.width, rect.height),
              );
            }
          } catch (e) {
            // falha ao desenhar numa field específica; continuar
            debugPrint('Erro ao aplicar assinatura no campo $name: $e');
          }
        }
      }
    }

    // Flatten form (incorpora valores e remove campos interativos)
    try {
      loaded.form?.flattenAllFields();
    } catch (_) {}

    // Export
    final List<int> outBytes = loaded.saveSync();
    loaded.dispose();

    // Salva em um arquivo na pasta de documentos do app
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/signed_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(outBytes, flush: true);
    return file.path;
  }

  @override
  void dispose() {
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
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
      children: _fieldControllers.entries.map((entry) {
        final name = entry.key;
        final controller = entry.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          child: TextField(
            controller: controller,
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('PDF salvo: $path')));
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Erro: $e')));
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
                  // Preview básico: mostra se há assinatura e botões para assinar/remover
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text('Assinar'),
                          onPressed: _openSignaturePad,
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.remove_circle),
                          label: const Text('Remover assinatura'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                          ),
                          onPressed:
                              _signatureImage != null ? _removeSignature : null,
                        ),
                        const SizedBox(width: 12),
                        if (_signatureImage != null)
                          const Text(
                            'Assinatura pronta',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Lista de campos editáveis
                  _buildFieldsList(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
