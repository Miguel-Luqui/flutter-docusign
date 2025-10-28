import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});

  @override
  _SignaturePadScreenState createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final GlobalKey _containerKey =
      GlobalKey(); // usado para converter global -> local
  final GlobalKey _repaintKey = GlobalKey(); // usado para exportar imagem
  final List<Offset?> _points = <Offset?>[];

  // debug: última posição global recebida e sua conversão local
  Offset? lastGlobal;
  Offset? lastLocal;

  Future<Uint8List?> _exportSignature() async {
    final boundary =
        _repaintKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData?.buffer.asUint8List();
  }

  void _clear() => setState(() {
    _points.clear();
    lastGlobal = null;
    lastLocal = null;
  });

  Offset _globalToLocal(Offset global) {
    final renderObject = _containerKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) return renderObject.globalToLocal(global);
    return Offset.zero;
  }

  void _addPointFromGlobal(Offset global) {
    final local = _globalToLocal(global);

    // debug prints
    final renderObject = _containerKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      final origin = renderObject.localToGlobal(Offset.zero);
      final size = renderObject.size;
      debugPrint(
        'POINTER global:$global  containerOrigin:$origin  local:$local  size:$size  '
        'viewPaddingTop:${MediaQuery.of(context).viewPadding.top}',
      );
    } else {
      debugPrint('POINTER global:$global  container renderObject null');
    }

    setState(() {
      _points.add(local);
      lastGlobal = global;
      lastLocal = local;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final canvasWidth = (screenWidth * 0.95).clamp(280.0, 900.0);
    const canvasHeight = 220.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Desenhe sua assinatura')),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: RepaintBoundary(
              key: _repaintKey,
              child: Material(
                elevation: 2,
                child: Container(
                  key: _containerKey,
                  width: canvasWidth,
                  height: canvasHeight,
                  color: Colors.white,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) =>
                        _addPointFromGlobal(event.position),
                    onPointerMove: (event) =>
                        _addPointFromGlobal(event.position),
                    onPointerUp: (_) => setState(() => _points.add(null)),
                    child: CustomPaint(
                      painter: _SignaturePainter(_points, lastLocal),
                      size: Size(canvasWidth, canvasHeight),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Assine na área branca acima',
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
          const Spacer(),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.blueGrey[900], // deixa os botões visíveis
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 10.0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white24),
                        backgroundColor: Colors.blueGrey[800],
                      ),
                      onPressed: _clear,
                      child: const Text('Limpar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () async {
                        final bytes = await _exportSignature();
                        Navigator.of(context).pop(bytes);
                      },
                      child: const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  final Offset? lastLocal;
  _SignaturePainter(this.points, this.lastLocal);

  @override
  void paint(Canvas canvas, Size size) {
    // fundo e borda para referência
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);
    final border = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, border);

    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool started = false;
    for (final p in points) {
      if (p == null) {
        started = false;
        continue;
      }
      final px = p.dx.clamp(0.0, size.width);
      final py = p.dy.clamp(0.0, size.height);
      if (!started) {
        path.moveTo(px, py);
        started = true;
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(path, paint);

    // debug: desenha último ponto convertido (bolinha vermelha)
    if (lastLocal != null) {
      final debugPaint = Paint()..color = Colors.red;
      canvas.drawCircle(
        Offset(
          lastLocal!.dx.clamp(0.0, size.width),
          lastLocal!.dy.clamp(0.0, size.height),
        ),
        6,
        debugPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) =>
      old.points != points || old.lastLocal != lastLocal;
}
