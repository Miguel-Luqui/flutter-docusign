import 'dart:typed_data';
// ignore: unused_import
import 'dart:ui' as ui;
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

    // DEBUG: dump pages sizes
    debugPrint('DEBUG: pages=${loaded.pages.count}');
    for (int p = 0; p < loaded.pages.count; p++) {
      final pg = loaded.pages[p];
      debugPrint(
          'DEBUG-PAGE $p size=${pg.size.width.toStringAsFixed(2)}x${pg.size.height.toStringAsFixed(2)}');
    }

    // DEBUG: list AcroForm fields + their dynamic rects/pageIndex if available
    final sfpdf.PdfForm? form = loaded.form;
    if (form != null) {
      debugPrint('DEBUG-FORM fields=${form.fields.count}');
      for (int i = 0; i < form.fields.count; i++) {
        final f = form.fields[i];
        final name = f.name ?? '<no-name>';
        final dyn = f as dynamic;
        dynamic rect;
        dynamic pageIndex;
        try {
          rect = dyn.bounds;
        } catch (_) {
          rect = null;
        }
        try {
          rect ??= dyn.rectangle;
        } catch (_) {}
        try {
          pageIndex = dyn.pageIndex;
        } catch (_) {
          pageIndex = null;
        }
        try {
          pageIndex ??= dyn.widget?.pageIndex;
        } catch (_) {}
        debugPrint(
            'DEBUG-FIELD #$i name=$name type=${f.runtimeType} pageIndex=$pageIndex rect=$rect');
        // try to extract rect components
        if (rect != null) {
          try {
            final left = (rect.left ?? rect.x ?? 0).toDouble();
            final top = (rect.top ?? rect.y ?? 0).toDouble();
            final width =
                (rect.width ?? ((rect.right != null) ? rect.right - left : 0))
                    .toDouble();
            final height =
                (rect.height ?? ((rect.bottom != null) ? rect.bottom - top : 0))
                    .toDouble();
            debugPrint(
                'DEBUG-FIELD-RECT name=$name left=${left.toStringAsFixed(1)} top=${top.toStringAsFixed(1)} w=${width.toStringAsFixed(1)} h=${height.toStringAsFixed(1)}');
          } catch (e) {
            debugPrint('DEBUG-FIELD-RECT extract error: $e');
          }
        }
      }
    } else {
      debugPrint('DEBUG: no AcroForm present');
    }

    // DEBUG: scan annotations per page and print props (contents/subject/name/title/rect)
    for (int p = 0; p < loaded.pages.count; p++) {
      final page = loaded.pages[p];
      try {
        final annots = page.annotations;
        debugPrint('DEBUG-ANNOT page=$p count=${annots.count}');
        for (int a = 0; a < annots.count; a++) {
          final annot = annots[a];
          final dyn = annot as dynamic;
          String? contents;
          try {
            contents = (dyn.contents ??
                    dyn.subject ??
                    dyn.title ??
                    dyn.name ??
                    dyn.fieldName)
                ?.toString();
          } catch (_) {
            contents = null;
          }
          dynamic rect;
          try {
            rect =
                dyn.bounds ?? dyn.rectangle ?? dyn.rect ?? dyn.widget?.bounds;
          } catch (_) {
            rect = null;
          }
          debugPrint(
              'DEBUG-ANNOT page=$p idx=$a type=${annot.runtimeType} contents=$contents rect=$rect');
          if (rect != null) {
            try {
              final left = (rect.left ?? rect.x ?? 0).toDouble();
              final top = (rect.top ?? rect.y ?? 0).toDouble();
              final width =
                  (rect.width ?? ((rect.right != null) ? rect.right - left : 0))
                      .toDouble();
              final height = (rect.height ??
                      ((rect.bottom != null) ? rect.bottom - top : 0))
                  .toDouble();
              debugPrint(
                  'DEBUG-ANNOT-RECT page=$p idx=$a left=${left.toStringAsFixed(1)} top=${top.toStringAsFixed(1)} w=${width.toStringAsFixed(1)} h=${height.toStringAsFixed(1)}');
              // VISUAL DEBUG (uncomment to draw a visible rectangle on the page for testing)
              // page.graphics.drawRectangle(sfpdf.PdfPen(sfpdf.PdfColor.fromArgb(255, 255, 0, 0), width: 2), Rect.fromLTWH(left, top, width, height));
            } catch (e) {
              debugPrint('DEBUG-ANNOT-RECT extract error: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('DEBUG-ANNOT page-scan error p=$p: $e');
      }
    }

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

    // se não há assinatura, apenas retorna o pdf com campos preenchidos
    if (_signature == null) {
      try {
        loaded.form.flattenAllFields();
      } catch (_) {}
      final List<int> out = await loaded.save();
      loaded.dispose();
      return Uint8List.fromList(out);
    }

    // helper: extrai double de possíveis estruturas dinamicas
    double _num(dynamic v, [double def = 0]) {
      if (v == null) return def;
      if (v is num) return v.toDouble();
      try {
        return (v as num).toDouble();
      } catch (_) {}
      try {
        return (v.left as num).toDouble();
      } catch (_) {}
      try {
        return (v.x as num).toDouble();
      } catch (_) {}
      try {
        return (v.top as num).toDouble();
      } catch (_) {}
      return def;
    }

    // helper: extrai doubles de rect-like
    double _toDouble(dynamic v, [double def = 0]) {
      if (v == null) return def;
      if (v is num) return v.toDouble();
      try {
        return (v as num).toDouble();
      } catch (_) {}
      try {
        return (v.left as num).toDouble();
      } catch (_) {}
      try {
        return (v.x as num).toDouble();
      } catch (_) {}
      return def;
    }

    // tenta localizar widget do field com page+rect
    Map<String, dynamic>? _locateFieldWidget(
        dynamic field, sfpdf.PdfDocument loaded) {
      try {
        // 1) widget singular
        try {
          final w = field.widget;
          if (w != null) {
            dynamic rect = w.bounds ?? w.rectangle ?? w.rect;
            int? p = (w.pageIndex ?? w.pageNumber) as int?;
            if (rect != null || p != null) {
              final left = _toDouble(rect?.left ?? rect?.x);
              final top = _toDouble(rect?.top ?? rect?.y);
              final width = _toDouble(rect?.width, double.nan);
              final height = _toDouble(rect?.height, double.nan);
              return {
                'page': p,
                'left': left,
                'top': top,
                'width': width,
                'height': height
              };
            }
          }
        } catch (_) {}

        // 2) widgets collection
        try {
          final widgets = field.widgets;
          if (widgets != null) {
            for (int wi = 0; wi < widgets.count; wi++) {
              final w = widgets[wi];
              dynamic rect = w.bounds ?? w.rectangle ?? w.rect;
              int? p = (w.pageIndex ?? w.pageNumber) as int?;
              final left = _toDouble(rect?.left ?? rect?.x);
              final top = _toDouble(rect?.top ?? rect?.y);
              final width = _toDouble(rect?.width, double.nan);
              final height = _toDouble(rect?.height, double.nan);
              if (p != null || (rect != null)) {
                return {
                  'page': p,
                  'left': left,
                  'top': top,
                  'width': width,
                  'height': height
                };
              }
            }
          }
        } catch (_) {}

        // 3) field-level rects (field.bounds/rectangle)
        try {
          dynamic rect = field.bounds ?? field.rectangle ?? field.rect;
          int? p = (field.pageIndex ?? field.pageNumber) as int?;
          if (rect != null || p != null) {
            final left = _toDouble(rect?.left ?? rect?.x);
            final top = _toDouble(rect?.top ?? rect?.y);
            final width = _toDouble(rect?.width, double.nan);
            final height = _toDouble(rect?.height, double.nan);
            return {
              'page': p,
              'left': left,
              'top': top,
              'width': width,
              'height': height
            };
          }
        } catch (_) {}

        // 4) fallback: if we have a rect without page, try map it to a page by overlap/cumulative heights
        // this will be handled by caller if page == null
      } catch (e) {
        debugPrint('locateFieldWidget error: $e');
      }
      return null;
    }

    // procura annotation com texto "signature" (case-insensitive)
    int? foundPage;
    dynamic foundRect;
    try {
      for (int p = 0; p < loaded.pages.count; p++) {
        final page = loaded.pages[p];
        final annots = page.annotations;
        for (int a = 0; a < annots.count; a++) {
          final annot = annots[a];
          final dyn = annot as dynamic;
          String? text;
          try {
            text = (dyn.contents ??
                    dyn.subject ??
                    dyn.title ??
                    dyn.name ??
                    dyn.fieldName)
                ?.toString();
          } catch (_) {
            text = null;
          }
          if (text != null && text.toLowerCase().contains('signature')) {
            // extrai rect de forma tolerante
            try {
              foundRect =
                  dyn.bounds ?? dyn.rectangle ?? dyn.rect ?? dyn.widget?.bounds;
            } catch (_) {
              foundRect = null;
            }
            foundPage = p;
            break;
          }
        }
        if (foundPage != null) break;
      }
    } catch (e) {
      debugPrint('Erro ao procurar annotations: $e');
    }

    // prepares image
    final sfpdf.PdfBitmap bitmap = sfpdf.PdfBitmap(_signature!);

    // dimensões naturais da imagem (opcional, para escalar mantendo proporção)
    int imgW = 0, imgH = 0;
    try {
      final codec = await ui.instantiateImageCodec(_signature!);
      final frame = await codec.getNextFrame();
      imgW = frame.image.width;
      imgH = frame.image.height;
    } catch (_) {
      imgW = 0;
      imgH = 0;
    }

    bool drawn = false;

    if (foundPage != null && foundRect != null) {
      try {
        // usamos foundRect/foundPage já detectados (não há 'dyn' aqui)
        final dynamic rect = foundRect;
        int pageIndex = foundPage;

        // extrai left/top/width/height de forma tolerante usando o helper _num
        double left = _num(rect.left, _num(rect.x, 0));
        double top = _num(rect.top, _num(rect.y, 0));
        double width = _num(rect.width, double.nan);
        double height = _num(rect.height, double.nan);

        if (width.isNaN) {
          final double right = _num(rect.right, double.nan);
          if (!right.isNaN) width = right - left;
        }
        if (height.isNaN) {
          final double bottom = _num(rect.bottom, double.nan);
          if (!bottom.isNaN) height = bottom - top;
        }

        if (width <= 0) width = 160;
        if (height <= 0) height = 60;

        // bottom-left do campo (top-based)
        final double rectBottom = top + height;

        // ESCALA (mantém proporção) — você pediu "escalar"
        double drawW, drawH;
        if (imgW > 0 && imgH > 0 && width > 0) {
          final ratio = imgH / imgW;
          drawW = width;
          drawH = drawW * ratio;
          final pg = loaded.pages[pageIndex];
          if (drawH > pg.size.height) {
            drawH = pg.size.height * 0.25;
            drawW = drawH / ratio;
          }
        } else {
          drawW = width;
          drawH = height;
        }

        double drawX = left;
        double drawY = rectBottom - drawH;

        final sfpdf.PdfPage page = loaded.pages[pageIndex];

        if (drawX < 0) drawX = 0;
        if (drawY < 0) drawY = 0;
        if (drawX + drawW > page.size.width)
          drawX = (page.size.width - drawW).clamp(0, page.size.width);
        if (drawY + drawH > page.size.height)
          drawY = (page.size.height - drawH).clamp(0, page.size.height);

        debugPrint(
            'FINAL SIGN placement -> page:$pageIndex left:${left.toStringAsFixed(1)} top:${top.toStringAsFixed(1)} w:${width.toStringAsFixed(1)} h:${height.toStringAsFixed(1)} drawX:${drawX.toStringAsFixed(1)} drawY:${drawY.toStringAsFixed(1)} drawW:${drawW.toStringAsFixed(1)} drawH:${drawH.toStringAsFixed(1)}');

        page.graphics
            .drawImage(bitmap, Rect.fromLTWH(drawX, drawY, drawW, drawH));
        drawn = true;
      } catch (e) {
        debugPrint('Erro ao desenhar assinatura na annotation: $e');
      }
    }

    // se não desenhamos pela annotation, tenta fallback em campo de formulário 'assinatura_cliente'
    if (!drawn && form != null) {
      for (int i = 0; i < form.fields.count; i++) {
        final sfpdf.PdfField f = form.fields[i];
        final String name = f.name ?? '';
        if (name != 'assinatura_cliente') continue;
        try {
          final loc = _locateFieldWidget(f as dynamic, loaded);
          int? pageIndex = loc?['page'] as int?;
          double left = (loc?['left'] as double?) ?? 0;
          double top = (loc?['top'] as double?) ?? 0;
          double width = (loc?['width'] as double?) ?? double.nan;
          double height = (loc?['height'] as double?) ?? double.nan;

          debugPrint(
              'FIELD WIDGET LOC -> page=${pageIndex?.toString() ?? "null"} left=${left.toStringAsFixed(1)} top=${top.toStringAsFixed(1)} width=${width.isNaN ? 0 : width.toStringAsFixed(1)} height=${height.isNaN ? 0 : height.toStringAsFixed(1)}');

          // if pageIndex null -> try map top (possibly global) into page by cumulative heights
          if (pageIndex == null) {
            double cumulative = 0;
            for (int p = 0; p < loaded.pages.count; p++) {
              final pg = loaded.pages[p];
              if (top >= cumulative && top < cumulative + pg.size.height) {
                pageIndex = p;
                top = top - cumulative; // convert to local page coordinates
                break;
              }
              cumulative += pg.size.height;
            }
          }

          // final fallback: try simple containment per-page (top-based)
          if (pageIndex == null) {
            for (int p = 0; p < loaded.pages.count; p++) {
              final pg = loaded.pages[p];
              if (!width.isNaN && !height.isNaN && width > 0 && height > 0) {
                final fits = left >= 0 &&
                    top >= 0 &&
                    left + width <= pg.size.width + 1 &&
                    top + height <= pg.size.height + 1;
                if (fits) {
                  pageIndex = p;
                  break;
                }
              }
            }
          }

          if (pageIndex == null) pageIndex = 0; // absolute fallback

          // agora pageIndex + left/top/width/height prontos para uso
          // ... aqui aplique seu draw logic (scale/anchor) ...
          final sfpdf.PdfPage page = loaded.pages[pageIndex];

          double drawX = left;
          double drawY = top + height - (height > 0 ? height : 60);
          double drawW = (width > 0 ? width : 160);
          double drawH = (height > 0 ? height : 60);
          if (drawX < 0) drawX = 0;
          if (drawY < 0) drawY = 0;
          if (drawX + drawW > page.size.width)
            drawX = (page.size.width - drawW).clamp(0, page.size.width);
          if (drawY + drawH > page.size.height)
            drawY = (page.size.height - drawH).clamp(0, page.size.height);
          page.graphics
              .drawImage(bitmap, Rect.fromLTWH(drawX, drawY, drawW, drawH));
          drawn = true;
          break;
        } catch (e) {
          debugPrint('Fallback assinatura erro: $e');
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

  Future<void> _onPreview() async {
    setState(() => _loading = true);
    try {
      final bytes = await _buildPdfWithValuesAndSignature();
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PdfViewerScreen(pdfBytes: bytes),
      ));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
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
        title: const Text('Preencher Documento'),
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
                else
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
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _openSignaturePad,
                  child: const Text('Sign document'),
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
    _controller = px.PdfControllerPinch(
        document: px.PdfDocument.openData(widget.pdfBytes));
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
          : px.PdfViewPinch(
              controller: _controller!, scrollDirection: Axis.vertical),
    );
  }
}
