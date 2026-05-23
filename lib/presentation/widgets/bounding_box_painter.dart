import 'package:flutter/material.dart';
import '../../data/models/recognition_result.dart';
import '../../core/constants/app_constants.dart';

/// Custom painter for drawing bounding boxes and labels on camera preview.
/// Expects `results[i].boundingBox` to be normalized (0..1) in the same
/// coordinate system as the displayed preview (portrait).
class BoundingBoxPainter extends CustomPainter {
  final List<RecognitionResult> results;

  BoundingBoxPainter({
    required this.results,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final result in results) {
      if (result.boundingBox == null) continue;

      final normalizedBox = result.boundingBox!;
      final color = result.color;

      final rect = Rect.fromLTRB(
        (normalizedBox.left * size.width).clamp(0.0, size.width),
        (normalizedBox.top * size.height).clamp(0.0, size.height),
        (normalizedBox.right * size.width).clamp(0.0, size.width),
        (normalizedBox.bottom * size.height).clamp(0.0, size.height),
      );
      if (rect.width <= 0 || rect.height <= 0) continue;

      // Draw bounding box with adaptive stroke width based on confidence
      final strokeWidth = AppConstants.boundingBoxStrokeWidth *
          (0.5 + result.confidence * 0.5);

      final paint = Paint()
        ..color = color.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      final rrect = RRect.fromRectAndRadius(
        rect,
        const Radius.circular(AppConstants.boundingBoxCornerRadius),
      );

      canvas.drawRRect(rrect, paint);

      // Draw semi-transparent fill
      final fillPaint = Paint()
        ..color = color.withOpacity(0.15)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(rrect, fillPaint);

      // Draw label with item name and confidence
      _drawLabel(
        canvas,
        rect,
        result.matchedItem.name,
        result.confidence,
        color,
      );
    }
  }

  /// Draw label with background
  void _drawLabel(
    Canvas canvas,
    Rect boundingBox,
    String itemName,
    double confidence,
    Color color,
  ) {
    final confidencePercent = (confidence * 100).toStringAsFixed(0);
    final labelText = '$itemName ($confidencePercent%)';

    final textPainter = TextPainter(
      text: TextSpan(
        text: labelText,
        style: TextStyle(
          color: Colors.white,
          fontSize: AppConstants.confidenceLabelFontSize,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 4,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Position label above bounding box (or below if too close to top)
    final labelY = boundingBox.top > textPainter.height + 10
        ? boundingBox.top - textPainter.height - 8
        : boundingBox.bottom + 8;

    final labelRect = Rect.fromLTWH(
      boundingBox.left,
      labelY,
      textPainter.width + 16,
      textPainter.height + 8,
    );

    // Draw label background
    final backgroundPaint = Paint()
      ..color = color.withOpacity(0.9)
      ..style = PaintingStyle.fill;

    final labelRRect = RRect.fromRectAndRadius(
      labelRect,
      const Radius.circular(4),
    );

    canvas.drawRRect(labelRRect, backgroundPaint);

    // Draw text
    textPainter.paint(
      canvas,
      Offset(labelRect.left + 8, labelRect.top + 4),
    );
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    if (identical(oldDelegate.results, results)) return false;
    if (oldDelegate.results.length != results.length) return true;
    for (int i = 0; i < results.length; i++) {
      final a = oldDelegate.results[i];
      final b = results[i];
      if (a.matchedItem.id != b.matchedItem.id) return true;
      if (a.confidence != b.confidence) return true;
      if (a.boundingBox != b.boundingBox) return true;
    }
    return false;
  }
}

/// Painter for drawing a simple crosshair in the center (for alignment)
class CrosshairPainter extends CustomPainter {
  final Color color;

  CrosshairPainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final crosshairSize = 20.0;

    // Horizontal line
    canvas.drawLine(
      Offset(centerX - crosshairSize, centerY),
      Offset(centerX + crosshairSize, centerY),
      paint,
    );

    // Vertical line
    canvas.drawLine(
      Offset(centerX, centerY - crosshairSize),
      Offset(centerX, centerY + crosshairSize),
      paint,
    );

    // Center circle
    canvas.drawCircle(
      Offset(centerX, centerY),
      4,
      paint..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CrosshairPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
