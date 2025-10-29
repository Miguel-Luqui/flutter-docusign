// ------------------------------------------------------------
// Arquivo: pdf_field_utils.dart
// Propósito:
//   Utilitários para extrair campos de formulário de um PDF,
//   inferir dimensões (por exemplo, razão de aspecto para campos de
//   assinatura) e gerar um novo PDF aplicando valores de texto,
//   estados de checkbox e desenhando a assinatura.
//
// Estrutura:
//  - extractFormFields: lê valores iniciais (textos e checkboxes)
//  - inferSignatureAspectRatio: tenta inferir proporção de campo de assinatura
//  - buildPdfWithValuesAndSignature: aplica valores e assinatura ao PDF
//  - helpers (_num, _toDouble, _locateFieldWidget): utilitários tolerantes
//    para lidar com várias formas de representar retângulos/páginas
// ------------------------------------------------------------

import 'dart:typed_data';
// ignore: unused_import
import 'dart:ui' as ui;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;

// Extracts form field initial values (text and checkboxes) from a PDF
// Returns a map with keys: 'texts' => Map<String,String>, 'checkboxes' => Map<String,bool>
// ------------------------------------------------------------
// Função: extractFormFields
// Objetivo:
//   Extrair valores iniciais de campos de formulário a partir dos bytes
//   do PDF. Retorna um Map com duas chaves:
//     - 'texts' : Map<String, String> com valores de campos de texto
//     - 'checkboxes' : Map<String, bool> com estados dos checkboxes
//
// Comportamento/Notas:
//   - Ignora campos cujo nome comece com 'assinatura_cliente' (são
//     tratados separadamente para desenhar a imagem da assinatura).
//   - Muitos try/catch silenciosos são usados por robustez: PDFs podem
//     representar campos de formas diferentes dependendo da origem.
// ------------------------------------------------------------
Future<Map<String, dynamic>> extractFormFields(Uint8List pdfBytes) async {
	final Map<String, String> texts = {};
	final Map<String, bool> checkboxes = {};

	final sfpdf.PdfDocument doc = sfpdf.PdfDocument(inputBytes: pdfBytes);
	try {
		final sfpdf.PdfForm? form = doc.form;
		if (form != null) {
			for (int i = 0; i < form.fields.count; i++) {
				final sfpdf.PdfField f = form.fields[i];
				final String name = f.name ?? 'field_$i';

				// Pulamos campos de assinatura (tratados separadamente)
				if (name.startsWith('assinatura_cliente')) continue;

				try {
					if (f is sfpdf.PdfTextBoxField) {
						// Usa 'dynamic' para acessar propriedades que podem variar
						final dyn = f as dynamic;
						final String initial = (dyn.text != null) ? dyn.text.toString() : '';
						texts[name] = initial;
					} else if (f is sfpdf.PdfCheckBoxField) {
						try {
							final dyn = f as dynamic;
							checkboxes[name] = (dyn.checked == true);
						} catch (_) {
							// Fallback: se não conseguir ler o estado, assume false
							checkboxes[name] = false;
						}
					} else {
						// Campo não reconhecido: registra como texto vazio
						texts[name] = '';
					}
				} catch (_) {
					// Em qualquer erro ao ler o campo, registramos valor vazio
					texts[name] = '';
				}
			}
		}
	} finally {
		// Garantir que o documento seja descartado para liberar memória
		doc.dispose();
	}

	return {'texts': texts, 'checkboxes': checkboxes};
}

// Try to infer an aspect ratio for signature fields (returns width/height or null)
// ------------------------------------------------------------
// Função: inferSignatureAspectRatio
// Objetivo:
//   Tentar descobrir a razão de aspecto (largura/altura) de um campo de
//   assinatura presente no formulário do PDF. Isso é útil para apresentar
//   a tela de assinatura com a proporção adequada.
//
// Abordagem:
//   - Percorre os campos de formulário procurando nomes que comecem com
//     'assinatura_cliente'. Para o primeiro que tiver um retângulo válido,
//     calcula w/h e retorna.
//   - Usa vários acessos dinâmicos (bounds/rectangle/rect) e cálculos
//     tolerantes porque diferentes PDFs e bibliotecas podem expor nomes
//     de propriedades diferentes.
// Retorno: double? (razão largura/altura) ou null se não puder inferir.
// ------------------------------------------------------------
Future<double?> inferSignatureAspectRatio(Uint8List pdfBytes) async {
	try {
		final sfpdf.PdfDocument doc = sfpdf.PdfDocument(inputBytes: pdfBytes);
		double? aspectRatio;
		try {
			final sfpdf.PdfForm? form = doc.form;
			if (form != null) {
				for (int i = 0; i < form.fields.count; i++) {
					final sfpdf.PdfField f = form.fields[i];
					final String name = f.name ?? '';
					if (!name.startsWith('assinatura_cliente')) continue;
					dynamic rect;
					try {
						final dyn = f as dynamic;
						// Tenta várias propriedades possíveis onde o retângulo pode
						// estar armazenado (compatibilidade com diferentes versões)
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
							break; // pare no primeiro campo válido
						}
					}
				}
			}
		} finally {
			doc.dispose();
		}
		return aspectRatio;
	} catch (_) {
		// Em caso de qualquer erro ao abrir/parsear o PDF, retornamos null
		return null;
	}
}

// Build a new PDF bytes applying text values, checkbox states and drawing signature image
// ------------------------------------------------------------
// Função: buildPdfWithValuesAndSignature
// Objetivo:
//   - Aplicar valores de texto e estados de checkbox no formulário do PDF
//   - Desenhar a imagem de assinatura nos campos cujo nome começa com
//     'assinatura_cliente'
//
// Detalhes importantes:
//   - Constrói um objeto PdfBitmap a partir dos bytes da assinatura, quando
//     disponível, e calcula largura/altura da imagem para manter proporção
//     ao desenhar no campo.
//   - Tenta várias abordagens ao escrever textos/checkboxes porque a API
//     pode expor diferentes propriedades (por isso o uso extensivo de
//     'dynamic' e blocos try/catch).
//   - Localização do campo na página é feita via `_locateFieldWidget`,
//     com heurísticas adicionais caso essa localização não retorne
//     informações completas.
// ------------------------------------------------------------
Future<Uint8List> buildPdfWithValuesAndSignature(
		Uint8List originalPdfBytes,
		Map<String, String> textValues,
		Map<String, bool> checkboxValues,
		Uint8List? signatureBytes) async {
	final sfpdf.PdfDocument loaded = sfpdf.PdfDocument(inputBytes: originalPdfBytes);

	final sfpdf.PdfForm? form = loaded.form;

	// prepare signature bitmap and size
	int imgW = 0, imgH = 0;
	sfpdf.PdfBitmap? bitmap;
	if (signatureBytes != null) {
		try {
			// Tenta criar um PdfBitmap direto dos bytes
			bitmap = sfpdf.PdfBitmap(signatureBytes);
		} catch (_) {
			bitmap = null;
		}
		try {
			// Tenta decodificar para descobrir dimensões reais da imagem
			final codec = await ui.instantiateImageCodec(signatureBytes);
			final frame = await codec.getNextFrame();
			imgW = frame.image.width;
			imgH = frame.image.height;
		} catch (_) {
			imgW = 0;
			imgH = 0;
		}
	}

	// fill form fields
	if (form != null) {
		for (int i = 0; i < form.fields.count; i++) {
			final sfpdf.PdfField f = form.fields[i];
			final String name = f.name ?? '';

			// Ignorar campos de assinatura nesta etapa (são desenhados depois)
			if (name.startsWith('assinatura_cliente')) continue;

			// Preenche textos quando disponível
			if (textValues.containsKey(name)) {
				final val = textValues[name] ?? '';
				try {
					if (f is sfpdf.PdfTextBoxField) {
						final dyn = f as dynamic;
						try {
							dyn.text = val; // tenta escrever via API dinâmica
						} catch (_) {
							try {
								f.text = val; // fallback para propriedade conhecida
							} catch (_) {}
						}
					}
				} catch (_) {}
			}

			// Aplica estado dos checkboxes quando disponível
			if (checkboxValues.containsKey(name)) {
				final bool checked = checkboxValues[name] ?? false;
				try {
					if (f is sfpdf.PdfCheckBoxField) {
						final dyn = f as dynamic;
						var applied = false;
						try {
							dyn.checked = checked; // tentativa comum
							applied = true;
						} catch (_) {}
						if (!applied) {
							try {
								dyn.isChecked = checked; // fallback alternativo
								applied = true;
							} catch (_) {}
						}
					}
				} catch (_) {}
			}
		}
	}

	// draw signature image into fields named 'assinatura_cliente'
	final sfpdf.PdfBitmap? bm = bitmap;

	if (form != null) {
		for (int i = 0; i < form.fields.count; i++) {
			final sfpdf.PdfField f = form.fields[i];
			final String name = f.name ?? '';
			if (!name.startsWith('assinatura_cliente')) continue;
			try {
				int? parsedPage;
				try {
					// Alguns nomes podem ter sufixos como 'assinatura_cliente.2'
					// indicando a página; tentamos extrair isso aqui.
					final parts = name.split('.');
					if (parts.length > 1) {
						final p1 = int.tryParse(parts[1]);
						if (p1 != null && p1 > 0) parsedPage = p1 - 1;
					}
				} catch (_) {
					parsedPage = null;
				}

				// Localiza posição e tamanho do widget/campo
				final loc = _locateFieldWidget(f as dynamic, loaded);
				int? pageIndex = parsedPage ?? (loc?['page'] as int?);
				double left = (loc?['left'] as double?) ?? 0;
				double top = (loc?['top'] as double?) ?? 0;
				double width = (loc?['width'] as double?) ?? double.nan;
				double height = (loc?['height'] as double?) ?? double.nan;

				// Heurísticas para determinar a página quando não fornecida
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
					// Mantém proporção da imagem ao dimensionar
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

						if (bm != null) {
							// Desenha a imagem no local calculado
							page.graphics.drawImage(bm, ui.Rect.fromLTWH(drawX, drawY, drawW, drawH));
						}
			} catch (_) {}
		}
	}

	// Tenta achatar campos para que os valores sejam permanentes
	try {
		loaded.form.flattenAllFields();
	} catch (_) {}
	final List<int> out = await loaded.save();
	loaded.dispose();
	return Uint8List.fromList(out);
}

// tolerant numeric extraction helpers and locateFieldWidget implementation
// ------------------------------------------------------------
// Helpers tolerantes para extrair números e localizar widgets de campo
// ------------------------------------------------------------
// Converte diversos tipos/representações em um número (fallbacks) —
// usado para extrair propriedades como left/top/right/bottom.
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

// Similar a _num mas focado em converter uma propriedade que pode ser um
// número direto ou estar aninhada em um objeto (e devolve um double).
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

// Localiza a posição (page, left, top, width, height) de um campo/form
// widget de forma robusta, tentando várias estruturas possíveis expostas
// pela API da biblioteca PDF. Retorna null se não for possível localizar.
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

		// 2) collection of widgets
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

		// 3) rects on field
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
