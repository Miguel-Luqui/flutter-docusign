import 'dart:typed_data';
// ignore: unused_import
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'package:pdfx/pdfx.dart' as px;
import 'package:flutter_docusign_app/widgets/signature_pad.dart';

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
    final sfpdf.PdfDocument doc =
        sfpdf.PdfDocument(inputBytes: widget.originalPdfBytes);
    final sfpdf.PdfForm? form = doc.form;
    if (form != null) {
      for (int i = 0; i < form.fields.count; i++) {
        final sfpdf.PdfField f = form.fields[i];
        final String name = f.name ?? 'field_$i';
        // ignora campos de assinatura (podem ter sufixo .<pagina>)
        if (name.startsWith('assinatura_cliente')) continue;
        try {
          if (f is sfpdf.PdfTextBoxField) {
            final dyn = f as dynamic;
            final String initial = (dyn.text != null) ? dyn.text.toString() : '';
            _controllers[name] = TextEditingController(text: initial);
          } else if (f is sfpdf.PdfCheckBoxField) {
            try {
              final dyn = f as dynamic;
              _checkboxValues[name] = (dyn.checked == true);
            } catch (_) {
              _checkboxValues[name] = false;
            }
          } else {
            _controllers[name] = TextEditingController();
          }
        } catch (_) {
          _controllers[name] = TextEditingController();
        }
      }
    }
    doc.dispose();
    setState(() => _loading = false);
  }

  // Abre a tela de captura de assinatura tentando inferir proporção do campo
  Future<void> _openSignaturePad() async {
    double? aspectRatio;
    try {
      final sfpdf.PdfDocument doc =
          sfpdf.PdfDocument(inputBytes: widget.originalPdfBytes);
      final sfpdf.PdfForm? form = doc.form;
      if (form != null) {
        for (int i = 0; i < form.fields.count; i++) {
          final sfpdf.PdfField f = form.fields[i];
          final String name = f.name ?? '';
          if (!name.startsWith('assinatura_cliente')) continue;
          dynamic rect;
          try {
            final dyn = f as dynamic;
            rect = dyn.bounds ?? dyn.rectangle ?? dyn.rect;
          } catch (_) {
            rect = null;
          }
          if (rect != null) {
            double w = 0, h = 0;
            try {
              w = (rect.width ?? ((rect.right != null)
                      ? rect.right - (rect.left ?? rect.x ?? 0)
                      : 0))
                  .toDouble();
            } catch (_) {}
            try {
              h = (rect.height ?? ((rect.bottom != null)
                      ? rect.bottom - (rect.top ?? rect.y ?? 0)
                      : 0))
                  .toDouble();
            } catch (_) {}
            if (w > 0 && h > 0) {
              aspectRatio = w / h;
              break;
            }
          }
        }
      }
      doc.dispose();
    } catch (_) {}

    final Uint8List? bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
          builder: (_) => SignaturePadScreen(targetAspectRatio: aspectRatio)),
    );
    if (bytes != null) setState(() => _signature = bytes);
  }

  // Constrói o PDF preenchido, aplica checkboxes e coloca a assinatura
  Future<Uint8List> _buildPdfWithValuesAndSignature() async {
    final sfpdf.PdfDocument loaded =
        sfpdf.PdfDocument(inputBytes: widget.originalPdfBytes);

    final sfpdf.PdfForm? form = loaded.form;

    // cache de rects detectados (nome -> {page,left,top,width,height})
    final Map<String, Map<String, dynamic>> _fieldRects = {};

    if (form != null) {
      for (int i = 0; i < form.fields.count; i++) {
        final f = form.fields[i];
        final name = f.name ?? '<no-name>';
        final dyn = f as dynamic;
        dynamic rect;
        dynamic pageIndex;
        try {
          rect = dyn.bounds ?? dyn.rectangle ?? dyn.rect;
        } catch (_) {
          rect = null;
        }
        try {
          pageIndex = dyn.pageIndex ?? dyn.widget?.pageIndex;
        } catch (_) {
          pageIndex = null;
        }

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
            _fieldRects[name] = {
              'page': pageIndex,
              'left': left,
              'top': top,
              'width': width,
              'height': height
            };
          } catch (_) {}
        }
      }
    }

    // se não há assinatura, apenas salva e retorna
    if (_signature == null) {
      try {
        loaded.form.flattenAllFields();
      } catch (_) {}
      final List<int> out = await loaded.save();
      loaded.dispose();
      return Uint8List.fromList(out);
    }

    // prepara imagem da assinatura
    final sfpdf.PdfBitmap bitmap = sfpdf.PdfBitmap(_signature!);
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

    // preencher campos (texto e checkbox)
    if (form != null) {
      for (int i = 0; i < form.fields.count; i++) {
        final sfpdf.PdfField f = form.fields[i];
        final String name = f.name ?? '';

        // ignora campos de assinatura
        if (name.startsWith('assinatura_cliente')) continue;

        // texto
        if (_controllers.containsKey(name)) {
          final val = _controllers[name]!.text;
          try {
            if (f is sfpdf.PdfTextBoxField) {
              final dyn = f as dynamic;
              try {
                dyn.text = val;
              } catch (_) {
                try {
                  f.text = val;
                } catch (_) {}
              }
            }
          } catch (_) {}
        }

        // checkbox
        if (_checkboxValues.containsKey(name)) {
          final bool checked = _checkboxValues[name] ?? false;
          try {
            if (f is sfpdf.PdfCheckBoxField) {
              final dyn = f as dynamic;
              var applied = false;
              try {
                dyn.checked = checked;
                applied = true;
              } catch (_) {}

              if (!applied) {
                final List<String> onNames = ['Yes', 'On', '1', '/Yes', '/On'];
                for (final n in onNames) {
                  try {
                    dyn.value = checked ? n : '';
                    applied = true;
                    break;
                  } catch (_) {}
                }
              }

              if (!applied) {
                try {
                  dyn.state = checked;
                  applied = true;
                } catch (_) {}
              }

              // verifica se aplicou visualmente; caso não, desenha X no rect detectado
              bool? post;
              try {
                post = dyn.checked as bool?;
              } catch (_) {
                post = null;
              }

              if (post != true && checked == true) {
                Map<String, dynamic>? crect = _fieldRects[name];
                int pageIndex = 0;
                double left = 0, top = 0, width = double.nan, height = double.nan;
                if (crect != null) {
                  pageIndex = (crect['page'] as int?) ?? 0;
                  left = (crect['left'] as double?) ?? 0;
                  top = (crect['top'] as double?) ?? 0;
                  width = (crect['width'] as double?) ?? double.nan;
                  height = (crect['height'] as double?) ?? double.nan;
                } else {
                  try {
                    final dynF = f as dynamic;
                    final r = dynF.widget?.bounds ?? dynF.bounds ?? dynF.rectangle ?? dynF.rect;
                    if (r != null) {
                      left = (r.left ?? r.x ?? 0).toDouble();
                      top = (r.top ?? r.y ?? 0).toDouble();
                      width = (r.width ?? ((r.right != null) ? r.right - (r.left ?? r.x ?? 0) : 0)).toDouble();
                      height = (r.height ?? ((r.bottom != null) ? r.bottom - (r.top ?? r.y ?? 0) : 0)).toDouble();
                    }
                    try {
                      pageIndex = (dynF.pageIndex ?? dynF.pageNumber ?? (dynF.widget?.pageIndex ?? dynF.widget?.pageNumber ?? (dynF.page != null ? dynF.page.index : null))) as int? ?? 0;
                    } catch (_) {
                      pageIndex = 0;
                    }
                  } catch (_) {}
                }

                if (width.isNaN || width <= 0) width = 12;
                if (height.isNaN || height <= 0) height = 12;
                try {
                  final sfpdf.PdfPage page = loaded.pages[pageIndex];
                  final leftX = left;
                  final topY = top;
                  final pen = sfpdf.PdfPen(sfpdf.PdfColor(0, 0, 0), width: 1.5);
                  page.graphics.drawLine(pen, Offset(leftX, topY), Offset(leftX + width, topY + height));
                  page.graphics.drawLine(pen, Offset(leftX + width, topY), Offset(leftX, topY + height));
                } catch (_) {}
              }
            }
          } catch (_) {}
        }
      }
    }

    // coloca assinatura: tenta annotations primeiro, senão fallback por campo 'assinatura_cliente'
    int? foundPage;
    dynamic foundRect;
    try {
      for (int p = 0; p < loaded.pages.count; p++) {
        final page = loaded.pages[p];
        final annots = page.annotations;
        for (int a = 0; a < annots.count; a++) {
          final annot = annots[a];
          final dyn = annot as dynamic;
          String? contents;
          try {
            contents = (dyn.contents ?? dyn.subject ?? dyn.title ?? dyn.name ?? dyn.fieldName)?.toString();
          } catch (_) {
            contents = null;
          }
          if (contents != null && contents.toLowerCase().contains('signature')) {
            try {
              foundRect = dyn.bounds ?? dyn.rectangle ?? dyn.rect ?? dyn.widget?.bounds;
            } catch (_) {
              foundRect = null;
            }
            foundPage = p;
            break;
          }
        }
        if (foundPage != null) break;
      }
    } catch (_) {}

    final sfpdf.PdfBitmap bm = bitmap;

    if (foundPage != null && foundRect != null) {
      try {
        final dynamic rect = foundRect;
        int pageIndex = foundPage;
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
        final double rectBottom = top + height;

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
        if (drawX + drawW > page.size.width) drawX = (page.size.width - drawW).clamp(0, page.size.width);
        if (drawY + drawH > page.size.height) drawY = (page.size.height - drawH).clamp(0, page.size.height);
        page.graphics.drawImage(bm, Rect.fromLTWH(drawX, drawY, drawW, drawH));
      } catch (_) {}
    } else if (form != null) {
      // fallback: procurar campo assinatura_cliente
      for (int i = 0; i < form.fields.count; i++) {
        final sfpdf.PdfField f = form.fields[i];
        final String name = f.name ?? '';
        if (!name.startsWith('assinatura_cliente')) continue;
        try {
          int? parsedPage;
          try {
            final parts = name.split('.');
            if (parts.length > 1) {
              final p1 = int.tryParse(parts[1]);
              if (p1 != null && p1 > 0) parsedPage = p1 - 1;
            }
          } catch (_) {
            parsedPage = null;
          }

          final loc = _locateFieldWidget(f as dynamic, loaded);
          int? pageIndex = parsedPage ?? (loc?['page'] as int?);
          double left = (loc?['left'] as double?) ?? 0;
          double top = (loc?['top'] as double?) ?? 0;
          double width = (loc?['width'] as double?) ?? double.nan;
          double height = (loc?['height'] as double?) ?? double.nan;

          if (pageIndex == null) {
            double cumulative = 0;
            for (int p = 0; p < loaded.pages.count; p++) {
              final pg = loaded.pages[p];
              if (top >= cumulative && top < cumulative + pg.size.height) {
                pageIndex = p;
                top = top - cumulative;
                break;
              }
              cumulative += pg.size.height;
            }
          }

          if (pageIndex == null) {
            for (int p = 0; p < loaded.pages.count; p++) {
              final pg = loaded.pages[p];
              if (!width.isNaN && !height.isNaN && width > 0 && height > 0) {
                final fits = left >= 0 && top >= 0 && left + width <= pg.size.width + 1 && top + height <= pg.size.height + 1;
                if (fits) {
                  pageIndex = p;
                  break;
                }
              }
            }
          }

          if (pageIndex == null) pageIndex = 0;

          final sfpdf.PdfPage page = loaded.pages[pageIndex];
          double maxW = (width.isNaN || width <= 0) ? page.size.width * 0.5 : width;
          double maxH = (height.isNaN || height <= 0) ? page.size.height * 0.12 : height;
          double drawW, drawH;
          if (imgW > 0 && imgH > 0) {
            final ratio = imgH / imgW;
            drawW = maxW;
            drawH = drawW * ratio;
            if (drawH > maxH) {
              drawH = maxH;
              drawW = drawH / ratio;
            }
          } else {
            drawW = maxW;
            drawH = maxH;
          }

          double drawX = left;
          double drawY = (!height.isNaN && height > 0) ? (top + height - drawH) : top;
          if (drawX < 0) drawX = 0;
          if (drawY < 0) drawY = 0;
          if (drawX + drawW > page.size.width) drawX = (page.size.width - drawW).clamp(0, page.size.width);
          if (drawY + drawH > page.size.height) drawY = (page.size.height - drawH).clamp(0, page.size.height);

          page.graphics.drawImage(bm, Rect.fromLTWH(drawX, drawY, drawW, drawH));
          break;
        } catch (_) {}
      }
    }

    try {
      loaded.form.flattenAllFields();
    } catch (_) {}
    final List<int> out = await loaded.save();
    loaded.dispose();
    return Uint8List.fromList(out);
  }

  // converte valores numéricos tolerantes
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

  // extrai double de objetos rect-like
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

  // tenta localizar widget/rect de um field e retorna mapa com page/left/top/width/height
  Map<String, dynamic>? _locateFieldWidget(dynamic field, sfpdf.PdfDocument loaded) {
    try {
      dynamic rect;
      int? p;

      double _extractWidth(dynamic r) {
        double w = _toDouble(r?.width, double.nan);
        if (w.isNaN) {
          try {
            final rn = _num(r?.right, double.nan);
            final ln = _num(r?.left, double.nan);
            if (!rn.isNaN && !ln.isNaN) return rn - ln;
          } catch (_) {}
        }
        return w;
      }

      double _extractHeight(dynamic r) {
        double h = _toDouble(r?.height, double.nan);
        if (h.isNaN) {
          try {
            final bn = _num(r?.bottom, double.nan);
            final tn = _num(r?.top, double.nan);
            if (!bn.isNaN && !tn.isNaN) return bn - tn;
          } catch (_) {}
        }
        return h;
      }

      // 1) widget singular
      try {
        final w = field.widget;
        if (w != null) {
          rect = w.bounds ?? w.rectangle ?? w.rect;
          p = (w.pageIndex ?? w.pageNumber ?? (w.page != null ? w.page.index : null)) as int?;
          if (rect != null || p != null) {
            double left = _toDouble(rect?.left ?? rect?.x, double.nan);
            double top = _toDouble(rect?.top ?? rect?.y, double.nan);
            double width = _extractWidth(rect);
            double height = _extractHeight(rect);
            return {
              'page': p,
              'left': left.isNaN ? 0.0 : left,
              'top': top.isNaN ? 0.0 : top,
              'width': width,
              'height': height
            };
          }
        }
      } catch (_) {}

      // 2) coleção de widgets
      try {
        final widgets = field.widgets;
        if (widgets != null) {
          for (int wi = 0; wi < widgets.count; wi++) {
            final w = widgets[wi];
            rect = w.bounds ?? w.rectangle ?? w.rect;
            p = (w.pageIndex ?? w.pageNumber ?? (w.page != null ? w.page.index : null)) as int?;
            double left = _toDouble(rect?.left ?? rect?.x, double.nan);
            double top = _toDouble(rect?.top ?? rect?.y, double.nan);
            double width = _extractWidth(rect);
            double height = _extractHeight(rect);
            if (p != null || rect != null) {
              return {
                'page': p,
                'left': left.isNaN ? 0.0 : left,
                'top': top.isNaN ? 0.0 : top,
                'width': width,
                'height': height
              };
            }
          }
        }
      } catch (_) {}

      // 3) rects no próprio field
      try {
        try {
          rect = field.bounds ?? field.rectangle ?? field.rect;
        } catch (_) {
          rect = null;
        }
        try {
          p = (field.pageIndex ?? field.pageNumber ?? (field.page != null ? field.page.index : null)) as int?;
        } catch (_) {
          p = null;
        }

        if (rect != null || p != null) {
          double left = _toDouble(rect?.left ?? rect?.x, double.nan);
          double top = _toDouble(rect?.top ?? rect?.y, double.nan);
          double width = _extractWidth(rect);
          double height = _extractHeight(rect);

          if (p == null && rect != null) {
            for (int pi = 0; pi < loaded.pages.count; pi++) {
              final pg = loaded.pages[pi];
              final ph = pg.size.height;
              if (!height.isNaN) {
                if ((top >= 0 && top + height <= ph + 1) || (top >= 0 && top <= ph + 1)) {
                  p = pi;
                  break;
                }
              } else {
                if (top >= 0 && top <= ph + 1) {
                  p = pi;
                  break;
                }
              }
            }

            if (p == null) {
              double cumulative = 0.0;
              for (int pi = 0; pi < loaded.pages.count; pi++) {
                final pg = loaded.pages[pi];
                if (top >= cumulative && top < cumulative + pg.size.height) {
                  p = pi;
                  top = top - cumulative;
                  break;
                }
                cumulative += pg.size.height;
              }
            }
          }

          return {
            'page': p,
            'left': left.isNaN ? 0.0 : left,
            'top': top.isNaN ? 0.0 : top,
            'width': width,
            'height': height
          };
        }
      } catch (_) {}

      return null;
    } catch (_) {
      return null;
    }
  }

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

