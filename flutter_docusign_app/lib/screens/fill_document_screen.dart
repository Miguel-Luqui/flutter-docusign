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
  final Map<String, bool> _checkboxValues = {};
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
    _checkboxValues.clear();
    final sfpdf.PdfDocument doc =
        sfpdf.PdfDocument(inputBytes: widget.originalPdfBytes);
    final sfpdf.PdfForm? form = doc.form;
    if (form != null) {
      for (int i = 0; i < form.fields.count; i++) {
        final sfpdf.PdfField f = form.fields[i];
        final String name = f.name ?? 'field_$i';
        // ignore signature fields in the input list (accepts suffix .<page>)
        if (name.startsWith('assinatura_cliente')) continue;
        try {
          if (f is sfpdf.PdfTextBoxField) {
            final dyn = f as dynamic;
            final String initial = (dyn.text != null) ? dyn.text.toString() : '';
            _controllers[name] = TextEditingController(text: initial);
          } else if (f is sfpdf.PdfCheckBoxField) {
            // capture initial checked state (use dynamic to avoid static getter mismatch)
            try {
              final dyn = f as dynamic;
              _checkboxValues[name] = (dyn.checked == true);
            } catch (_) {
              _checkboxValues[name] = false;
            }
          } else {
            // default to a text controller for unknown fields
            _controllers[name] = TextEditingController();
          }
        } catch (_) {
          // best-effort: add an empty controller
          _controllers[name] = TextEditingController();
        }
      }
    }
    doc.dispose();
    setState(() => _loading = false);
  }

  Future<void> _openSignaturePad() async {
    // try to detect the signature field aspect ratio from the PDF so the pad can size accordingly
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
          // try to get rect defensively (use dynamic to avoid static getter errors)
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
              w = (rect.width ?? ((rect.right != null) ? rect.right - (rect.left ?? rect.x ?? 0) : 0)).toDouble();
            } catch (_) {
              try {
                w = (rect.right - rect.left).toDouble();
              } catch (_) {}
            }
            try {
              h = (rect.height ?? ((rect.bottom != null) ? rect.bottom - (rect.top ?? rect.y ?? 0) : 0)).toDouble();
            } catch (_) {
              try {
                h = (rect.bottom - rect.top).toDouble();
              } catch (_) {}
            }
            if (w > 0 && h > 0) {
              aspectRatio = w / h;
              break;
            }
          }
        }
      }
      doc.dispose();
    } catch (e) {
      debugPrint('Could not detect signature field aspect ratio: $e');
    }

    final Uint8List? bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => SignaturePadScreen(targetAspectRatio: aspectRatio)),
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
    // cache of field rects detected while scanning the form (name -> {page,left,top,width,height})
    final Map<String, Map<String, dynamic>> _fieldRects = {};
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
            // cache the rect for later use (fallbacks)
            _fieldRects[name] = {'page': pageIndex, 'left': left, 'top': top, 'width': width, 'height': height};
          } catch (e) {
            debugPrint('DEBUG-FIELD-RECT extract error: $e');
          }
        }
      }
    } else {
      debugPrint('DEBUG: no AcroForm present');
    }

    debugPrint('DEBUG-FIELD-RECTS KEYS -> ${_fieldRects.keys.toList()}');

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
    // ignore signature fields (they can be named like assinatura_cliente or assinatura_cliente.<page>)
    if (name.startsWith('assinatura_cliente')) continue;
        // text fields
        if (_controllers.containsKey(name)) {
          final val = _controllers[name]!.text;
          try {
            if (f is sfpdf.PdfTextBoxField) {
              final dyn = f as dynamic;
              try {
                dyn.text = val;
              } catch (_) {
                // fallback
                try {
                  f.text = val;
                } catch (_) {}
              }
            }
          } catch (_) {}
        }
        // checkbox fields
        if (_checkboxValues.containsKey(name)) {
          final bool checked = _checkboxValues[name] ?? false;
          try {
            if (f is sfpdf.PdfCheckBoxField) {
              final dyn = f as dynamic;
              // debug: inspect before state
              try {
                debugPrint('DEBUG-CHECKBOX APPLY -> name=$name before checked=${dyn.checked} value=${dyn.value ?? dyn.state}');
              } catch (_) {
                debugPrint('DEBUG-CHECKBOX APPLY -> name=$name before unknown state');
              }
              // try multiple ways to set the checkbox state (including common On names)
              var applied = false;
              try {
                dyn.checked = checked;
                applied = true;
              } catch (_) {}
              // try common appearance/value names
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
              try {
                if (!applied) {
                  dyn.state = checked;
                  applied = true;
                }
              } catch (_) {}

              // read back
              bool? post;
              try {
                post = dyn.checked as bool?;
              } catch (_) {
                post = null;
              }
              debugPrint('DEBUG-CHECKBOX APPLY -> name=$name attempted=$applied after checked=$post');

              // if the setter didn't persist the visible check, draw a fallback X on the page
              if (post != true && checked == true) {
                // try to use cached rect discovered earlier when scanning the form
                Map<String, dynamic>? crect = _fieldRects[name];
                debugPrint('DEBUG-CHECKBOX CACHED-RECT -> name=$name crect=$crect');
                int pageIndex = 0;
                double left = 0, top = 0, width = double.nan, height = double.nan;
                if (crect != null) {
                  pageIndex = (crect['page'] as int?) ?? 0;
                  left = (crect['left'] as double?) ?? 0;
                  top = (crect['top'] as double?) ?? 0;
                  width = (crect['width'] as double?) ?? double.nan;
                  height = (crect['height'] as double?) ?? double.nan;
                } else {
                  // try dynamic extraction as fallback
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
                  debugPrint('DEBUG-CHECKBOX FALLBACK -> drew X on page=$pageIndex rect=(${leftX.toStringAsFixed(1)},${topY.toStringAsFixed(1)},${width.toStringAsFixed(1)},${height.toStringAsFixed(1)})');
                } catch (e) {
                  debugPrint('DEBUG-CHECKBOX FALLBACK locate/draw error: $e');
                }
              }
            }
          } catch (e) {
            debugPrint('DEBUG-CHECKBOX APPLY ERROR -> name=$name error=$e');
          }
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
        dynamic rect;
        int? p;

        // small helper to extract width/height (try width/height, else right-left / bottom-top)
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

        // 1) try singular widget
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
              return {'page': p, 'left': left.isNaN ? 0.0 : left, 'top': top.isNaN ? 0.0 : top, 'width': width, 'height': height};
            }
          }
        } catch (e) {
          debugPrint('locateFieldWidget widget-check error: $e');
        }

        // 2) widgets collection
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
                return {'page': p, 'left': left.isNaN ? 0.0 : left, 'top': top.isNaN ? 0.0 : top, 'width': width, 'height': height};
              }
            }
          }
        } catch (e) {
          debugPrint('locateFieldWidget widgets-check error: $e');
        }

        // 3) field-level rects (field.bounds/rectangle/rect)
        try {
          // get rect defensively (some field implementations expose bounds/rectangle/rect)
          try {
            rect = field.bounds ?? field.rectangle ?? field.rect;
          } catch (_) {
            rect = null;
          }

          // get page index defensively (property may not exist)
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

            // If page is still null but we have a rect, try mapping to a page by checking per-page containment
            if (p == null && rect != null) {
              // try local page coords containment
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

              // cumulative mapping fallback (if rect is in global coords)
              if (p == null) {
                double cumulative = 0.0;
                for (int pi = 0; pi < loaded.pages.count; pi++) {
                  final pg = loaded.pages[pi];
                  if (top >= cumulative && top < cumulative + pg.size.height) {
                    p = pi;
                    // convert top to local page coords
                    top = top - cumulative;
                    break;
                  }
                  cumulative += pg.size.height;
                }
              }
            }

            return {'page': p, 'left': left.isNaN ? 0.0 : left, 'top': top.isNaN ? 0.0 : top, 'width': width, 'height': height};
          }
        } catch (e) {
          debugPrint('locateFieldWidget field-rect-check error: $e');
        }

        return null;
      } catch (e) {
        debugPrint('locateFieldWidget error: $e');
        return null;
      }
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
    debugPrint(
      'DEBUG-SIGN-ANNOT -> using annotation detected on page=$pageIndex; will draw at (x=${drawX.toStringAsFixed(1)}, y=${drawY.toStringAsFixed(1)}) size=${drawW.toStringAsFixed(1)}x${drawH.toStringAsFixed(1)}');

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
        // accept assinatura_cliente and assinatura_cliente.<page>
        if (!name.startsWith('assinatura_cliente')) continue;
        try {
          // try parse page from name suffix (1-based)
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

          // prefer parsedPage (from field name) if present, otherwise use locator
          int? pageIndex = parsedPage ?? (loc?['page'] as int?);
          double left = (loc?['left'] as double?) ?? 0;
          double top = (loc?['top'] as double?) ?? 0;
          double width = (loc?['width'] as double?) ?? double.nan;
          double height = (loc?['height'] as double?) ?? double.nan;

      debugPrint(
        'FIELD WIDGET LOC -> name=$name parsedPage=${parsedPage?.toString() ?? "null"} page=${pageIndex?.toString() ?? "null"} left=${left.toStringAsFixed(1)} top=${top.toStringAsFixed(1)} width=${width.isNaN ? 0 : width.toStringAsFixed(1)} height=${height.isNaN ? 0 : height.toStringAsFixed(1)}');

      // debug where we plan to draw and why (parsedPage vs locator)
      debugPrint('DEBUG-SIGN-FIELD -> name=$name parsedPage=${parsedPage?.toString() ?? "null"} locatorPage=${(loc?['page'] as int?)?.toString() ?? "null"} chosenPage=${pageIndex?.toString() ?? "null"}');

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
          final sfpdf.PdfPage page = loaded.pages[pageIndex];
          // preserve original image aspect ratio and shrink if necessary to fit
          double maxW = (width.isNaN || width <= 0) ? page.size.width * 0.5 : width;
          double maxH = (height.isNaN || height <= 0) ? page.size.height * 0.12 : height;
          double drawW, drawH;
          if (imgW > 0 && imgH > 0) {
            final ratio = imgH / imgW; // height/width
            // start by fitting to maxW, then shrink if height exceeds maxH
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
          if (drawX + drawW > page.size.width)
            drawX = (page.size.width - drawW).clamp(0, page.size.width);
          if (drawY + drawH > page.size.height)
            drawY = (page.size.height - drawH).clamp(0, page.size.height);

          debugPrint('DEBUG-SIGN-FIELD placement -> page:$pageIndex drawX:${drawX.toStringAsFixed(1)} drawY:${drawY.toStringAsFixed(1)} drawW:${drawW.toStringAsFixed(1)} drawH:${drawH.toStringAsFixed(1)}');

          page.graphics.drawImage(bitmap, Rect.fromLTWH(drawX, drawY, drawW, drawH));
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
                  // render checkbox inputs
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
