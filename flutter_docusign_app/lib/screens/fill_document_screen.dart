import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'package:pdfx/pdfx.dart' as px;
import 'package:flutter_docusign_app/widgets/signature_pad.dart';

class FillDocumentScreen extends StatefulWidget {
  final Uint8List originalPdfBytes;
  const FillDocumentScreen({super.key, required this.originalPdfBytes});

  @override
  State<FillDocumentScreen> createState() => _FillDocumentScreenState();
}

class _FillDocumentScreenState extends State<FillDocumentScreen> {
  final Map<String, TextEditingController> _controllers = {};
  Uint8List? _signature;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _extractFields();
  }

  Future<void> _extractFields() async {
    setState(() => _loading = true);
    _controllers.clear();
    final sfpdf.PdfDocument doc =
        sfpdf.PdfDocument(inputBytes: widget.originalPdfBytes);
    final sfpdf.PdfForm? form = doc.form;
    if (form != null) {
      for (int i = 0; i < form.fields.count; i++) {
        final sfpdf.PdfField f = form.fields[i];
        final String name = f.name ?? 'field_$i';
        // ignorar campo de assinatura na lista de inputs
        if (name == 'assinatura_cliente') continue;
        String initial = '';
        try {
          if (f is sfpdf.PdfTextBoxField) initial = f.text;
        } catch (_) {}
        _controllers[name] = TextEditingController(text: initial);
      }
    }
    doc.dispose();
    setState(() => _loading = false);
  }

  Future<void> _openSignaturePad() async {
    final Uint8List? bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const SignaturePadScreen()),
    );
    if (bytes != null) setState(() => _signature = bytes);
  }

  Future<Uint8List> _buildPdfWithValuesAndSignature() async {
    final sfpdf.PdfDocument loaded =
        sfpdf.PdfDocument(inputBytes: widget.originalPdfBytes);
    final sfpdf.PdfForm? form = loaded.form;

    // preencher campos (exceto assinatura_cliente)
    if (form != null) {
      for (int i = 0; i < form.fields.count; i++) {
        final sfpdf.PdfField f = form.fields[i];
        final String name = f.name ?? '';
        if (name == 'assinatura_cliente') continue;
        if (_controllers.containsKey(name)) {
          final val = _controllers[name]!.text;
          try {
            if (f is sfpdf.PdfTextBoxField) f.text = val;
          } catch (_) {}
        }
      }
    }

    // helper seguro
    double _toDouble(dynamic v, [double def = 0]) {
      if (v == null) return def;
      if (v is num) return v.toDouble();
      try {
        return (v as num).toDouble();
      } catch (_) {}
      try {
        // algumas impls tem getters .left/.top/.width/.height
        if ((v).left != null) return (v.left as num).toDouble();
      } catch (_) {}
      return def;
    }

    // localizar página a partir do rect usando várias estratégias
    int? _findPageIndexForRect(dynamic rect) {
      if (rect == null) return null;
      // extrair valores básicos do rect
      final double rectLeft = _toDouble(rect.left, _toDouble(rect.x, 0));
      final double rectTop = _toDouble(rect.top, _toDouble(rect.y, 0));
      final double rectW = _toDouble(rect.width, 0);
      final double rectH = _toDouble(rect.height, 0);
      // 1) tentar encaixe simples por página (top-based e bottom-based)
      for (int p = 0; p < loaded.pages.count; p++) {
        final pg = loaded.pages[p];
        // top-based
        final fitsTop = rectLeft >= 0 &&
            rectTop >= 0 &&
            rectW > 0 &&
            rectH > 0 &&
            rectLeft + rectW <= pg.size.width + 1 &&
            rectTop + rectH <= pg.size.height + 1;
        if (fitsTop) return p;
        // bottom-based: rectTop é medido desde a base
        final topFromBottom = pg.size.height - rectTop - rectH;
        final fitsBottom = rectLeft >= 0 &&
            topFromBottom >= 0 &&
            rectW > 0 &&
            rectH > 0 &&
            rectLeft + rectW <= pg.size.width + 1 &&
            topFromBottom + rectH <= pg.size.height + 1;
        if (fitsBottom) return p;
      }
      // 2) mapeamento por alturas cumulativas (top-based)
      double cumulative = 0;
      for (int p = 0; p < loaded.pages.count; p++) {
        final pg = loaded.pages[p];
        final double pgH = pg.size.height;
        if (rectTop >= cumulative && rectTop < cumulative + pgH) return p;
        final double rectCenter = rectTop + rectH / 2;
        if (rectCenter >= cumulative && rectCenter < cumulative + pgH) return p;
        cumulative += pgH;
      }
      // 3) mapeamento por alturas cumulativas (bottom-based)
      // calcular total
      double totalH = 0;
      for (int p = 0; p < loaded.pages.count; p++)
        totalH += loaded.pages[p].size.height;
      final double rectTopFromBottomDoc = totalH - rectTop - rectH;
      double cum2 = 0;
      for (int p = 0; p < loaded.pages.count; p++) {
        final pg = loaded.pages[p];
        if (rectTopFromBottomDoc >= cum2 &&
            rectTopFromBottomDoc < cum2 + pg.size.height) return p;
        cum2 += pg.size.height;
      }
      return null;
    }

    // aplicar assinatura na posição do campo "assinatura_cliente"
    if (_signature != null && form != null) {
      final sfpdf.PdfBitmap bitmap = sfpdf.PdfBitmap(_signature!);
      for (int i = 0; i < form.fields.count; i++) {
        final sfpdf.PdfField f = form.fields[i];
        final String name = f.name ?? '';
        if (name == 'assinatura_cliente') {
          try {
            final dyn = f as dynamic;
            dynamic rect;
            int? pageIndex;

            try {
              rect = dyn.bounds;
            } catch (_) {
              rect = null;
            }
            // pageIndex direto (se disponível)
            try {
              pageIndex = dyn.pageIndex as int?;
            } catch (_) {
              pageIndex = null;
            }
            try {
              pageIndex ??= dyn.widget?.pageIndex as int?;
            } catch (_) {}

            // se não tiver pageIndex, tente achar com as estratégias acima
            if (rect != null && pageIndex == null) {
              pageIndex = _findPageIndexForRect(rect);
              // se a estratégia 1 (fitsBottom) foi escolhida, invertY não é estritamente necessário
            }

            if (rect != null &&
                pageIndex != null &&
                pageIndex >= 0 &&
                pageIndex < loaded.pages.count) {
              final pg = loaded.pages[pageIndex];
              double left = 0, top = 0, w = 160, h = 60;
              try {
                left = (rect.left ?? rect.x).toDouble();
              } catch (_) {}
              try {
                top = (rect.top ?? rect.y).toDouble();
              } catch (_) {}
              try {
                w = (rect.width).toDouble();
              } catch (_) {}
              try {
                h = (rect.height).toDouble();
              } catch (_) {}

              // determinar y final: tentar both interpretations e escolher a que cai dentro da página
              double yCandidateTop = top;
              double yCandidateBottom = pg.size.height - top - h;
              double yFinal = yCandidateTop;
              if (yCandidateTop < 0 || yCandidateTop + h > pg.size.height + 1) {
                if (yCandidateBottom >= 0 &&
                    yCandidateBottom + h <= pg.size.height + 1) {
                  yFinal = yCandidateBottom;
                }
              }

              final double x = left;
              final double y = yFinal;

              pg.graphics.drawImage(bitmap, Rect.fromLTWH(x, y, w, h));
            } else {
              // fallback
              final pg = loaded.pages[0];
              const double fw = 160.0, fh = 60.0;
              final double fx = pg.size.width - fw - 40.0;
              final double fy = pg.size.height - fh - 40.0;
              pg.graphics.drawImage(bitmap, Rect.fromLTWH(fx, fy, fw, fh));
            }
          } catch (e) {
            debugPrint('Erro ao posicionar assinatura: $e');
          }
          break; // aplica apenas no primeiro campo de assinatura encontrado
        }
      }
    }

    try {
      loaded.form.flattenAllFields();
    } catch (_) {}
    final List<int> out = await loaded.save();
    loaded.dispose();
    return Uint8List.fromList(out);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preencher Documento'),
        actions: [
          IconButton(
            onPressed: () async {
              final Uint8List pdfComAssinatura =
                  await _buildPdfWithValuesAndSignature();
              // Navegar para a tela de visualização do PDF
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => PdfViewerScreen(
                    pdfBytes: pdfComAssinatura,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.save),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else
                  ..._controllers.entries.map(
                    (e) => TextField(
                      controller: e.value,
                      decoration: InputDecoration(
                        labelText: e.key,
                        border: const OutlineInputBorder(),
                        suffixIcon: e.key == 'assinatura_cliente'
                            ? IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: _openSignaturePad,
                              )
                            : null,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _openSignaturePad,
                  child: const Text('Abrir Pad de Assinatura'),
                ),
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

class PdfViewerScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  const PdfViewerScreen({super.key, required this.pdfBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualizar PDF'),
      ),
      body: Center(
        child: px.PdfView(
          controller: px.PdfController(
            document: px.PdfDocument.openData(pdfBytes),
          ),
        ),
      ),
    );
  }
}
