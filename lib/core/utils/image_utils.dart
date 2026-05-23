import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// DTO for a preprocessed ROI returned to the main thread.
/// `normalizedRect` is in portrait coordinates (0.0 - 1.0).
class PreprocessedRoi {
  final Rect normalizedRect;
  final Float32List pixels;

  const PreprocessedRoi({
    required this.normalizedRect,
    required this.pixels,
  });
}

// Tunables for multi-ROI detection (top-level constants so the isolate worker
// can use them without dragging in the `ImageUtils` class).
const int _kGridStep = 24;
const int _kEdgeDeltaThreshold = 40;
const int _kMinCellEdges = 4;
const int _kMinClusterCells = 6;
const int _kMaxRois = 5;

class ImageUtils {
  /// Multi-ROI pipeline. Heavy YUV→RGB / clustering / reprojection work runs
  /// on a worker isolate so the UI thread stays free.
  static Future<List<PreprocessedRoi>?> processCameraFrameFullPipeline(
    CameraImage cameraImage, {
    required int modelWidth,
    required int modelHeight,
  }) async {
    if (cameraImage.format.group != ImageFormatGroup.yuv420) return null;

    final job = _FrameJob(
      yBytes: cameraImage.planes[0].bytes,
      uBytes: cameraImage.planes[1].bytes,
      vBytes: cameraImage.planes[2].bytes,
      width: cameraImage.width,
      height: cameraImage.height,
      uvRowStride: cameraImage.planes[1].bytesPerRow,
      uvPixelStride: cameraImage.planes[1].bytesPerPixel ?? 1,
      modelWidth: modelWidth,
      modelHeight: modelHeight,
    );

    try {
      return await Isolate.run(() => _runFramePipelineSync(job));
    } catch (e) {
      debugPrint('Pipeline isolate error: $e');
      return null;
    }
  }

  /// Resize image to target dimensions for ML model input
  static img.Image resizeImage(img.Image image, int targetWidth, int targetHeight) {
    return img.copyResize(
      image,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear,
    );
  }

  /// Normalize pixel values to [0, 1] range for ML model
  static Float32List normalizeImage(img.Image image) {
    final pixels = Float32List(image.width * image.height * 3);
    int pixelIndex = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        pixels[pixelIndex++] = pixel.r / 255.0;
        pixels[pixelIndex++] = pixel.g / 255.0;
        pixels[pixelIndex++] = pixel.b / 255.0;
      }
    }
    return pixels;
  }

  /// Prepare image for TFLite input (resize + normalize)
  static Float32List preprocessForModel(
    img.Image image,
    int modelWidth,
    int modelHeight,
  ) {
    final resized = resizeImage(image, modelWidth, modelHeight);
    return normalizeImage(resized);
  }

  /// Convert Flutter Image to img.Image
  static Future<img.Image?> convertFlutterImage(ui.Image flutterImage) async {
    final byteData = await flutterImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) return null;
    return img.Image.fromBytes(
      width: flutterImage.width,
      height: flutterImage.height,
      bytes: byteData.buffer,
      order: img.ChannelOrder.rgba,
    );
  }

  /// Load image from file path. Returns null if file is missing, unreadable,
  /// or larger than `maxBytes` (when supplied).
  static Future<img.Image?> loadImageFromFile(String path, {int? maxBytes}) async {
    try {
      if (maxBytes != null) {
        final stat = await FileStat.stat(path);
        if (stat.type == FileSystemEntityType.notFound) return null;
        if (stat.size > maxBytes) {
          debugPrint(
              'Image exceeds size limit (${stat.size} > $maxBytes bytes): $path');
          return null;
        }
      }
      return await img.decodeImageFile(path);
    } catch (e) {
      debugPrint('Error loading image from file: $e');
      return null;
    }
  }

  static bool isValidImage(img.Image image, int minWidth, int minHeight) {
    return image.width >= minWidth && image.height >= minHeight;
  }

  static Future<double> getImageSizeMB(String path) async {
    try {
      final stat = await FileStat.stat(path);
      if (stat.type == FileSystemEntityType.notFound) return 0.0;
      return stat.size / (1024 * 1024);
    } catch (e) {
      return 0.0;
    }
  }
}

/// Sendable payload describing one camera frame + model target shape.
class _FrameJob {
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int width;
  final int height;
  final int uvRowStride;
  final int uvPixelStride;
  final int modelWidth;
  final int modelHeight;

  const _FrameJob({
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.width,
    required this.height,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.modelWidth,
    required this.modelHeight,
  });
}

class _Cluster {
  final int minX;
  final int maxX;
  final int minY;
  final int maxY;
  final int size;
  const _Cluster({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.size,
  });
}

/// Runs the full YUV → multi-ROI pipeline synchronously.
/// Top-level so it can be invoked inside `Isolate.run`.
List<PreprocessedRoi> _runFramePipelineSync(_FrameJob job) {
  final int inWidth = job.width;
  final int inHeight = job.height;
  final int uvRowStride = job.uvRowStride;
  final int uvPixelStride = job.uvPixelStride;
  final Uint8List yPlaneBytes = job.yBytes;
  final Uint8List uPlaneBytes = job.uBytes;
  final Uint8List vPlaneBytes = job.vBytes;
  final int modelWidth = job.modelWidth;
  final int modelHeight = job.modelHeight;

  // ==========================================
  // PHASE 1: COARSE EDGE-DENSITY GRID
  // ==========================================
  final int gridW = inWidth ~/ _kGridStep;
  final int gridH = inHeight ~/ _kGridStep;
  if (gridW < 2 || gridH < 2) return const [];

  final Int32List edgeCount = Int32List(gridW * gridH);

  for (int y = _kGridStep; y < inHeight - _kGridStep; y += 2) {
    final int rowOffset = y * inWidth;
    final int topRowOffset = (y - _kGridStep) * inWidth;
    final int cellY = y ~/ _kGridStep;
    if (cellY >= gridH) break;
    for (int x = _kGridStep; x < inWidth - _kGridStep; x += 2) {
      final int cur = yPlaneBytes[rowOffset + x];
      final int left = yPlaneBytes[rowOffset + (x - _kGridStep)];
      final int top = yPlaneBytes[topRowOffset + x];
      if ((cur - left).abs() > _kEdgeDeltaThreshold ||
          (cur - top).abs() > _kEdgeDeltaThreshold) {
        final int cellX = x ~/ _kGridStep;
        if (cellX < gridW) {
          edgeCount[cellY * gridW + cellX]++;
        }
      }
    }
  }

  // ==========================================
  // PHASE 2: CONNECTED COMPONENTS
  // ==========================================
  final Uint8List active = Uint8List(gridW * gridH);
  for (int i = 0; i < edgeCount.length; i++) {
    if (edgeCount[i] >= _kMinCellEdges) active[i] = 1;
  }

  final Uint8List visited = Uint8List(gridW * gridH);
  final List<_Cluster> clusters = [];
  final List<int> stack = [];

  for (int seed = 0; seed < active.length; seed++) {
    if (active[seed] == 0 || visited[seed] == 1) continue;

    int minCx = gridW, maxCx = -1, minCy = gridH, maxCy = -1;
    int cellsInCluster = 0;

    stack.add(seed);
    visited[seed] = 1;
    while (stack.isNotEmpty) {
      final int cell = stack.removeLast();
      final int cx = cell % gridW;
      final int cy = cell ~/ gridW;
      cellsInCluster++;
      if (cx < minCx) minCx = cx;
      if (cx > maxCx) maxCx = cx;
      if (cy < minCy) minCy = cy;
      if (cy > maxCy) maxCy = cy;

      if (cx + 1 < gridW) {
        final int ni = cell + 1;
        if (active[ni] == 1 && visited[ni] == 0) {
          visited[ni] = 1;
          stack.add(ni);
        }
      }
      if (cx - 1 >= 0) {
        final int ni = cell - 1;
        if (active[ni] == 1 && visited[ni] == 0) {
          visited[ni] = 1;
          stack.add(ni);
        }
      }
      if (cy + 1 < gridH) {
        final int ni = cell + gridW;
        if (active[ni] == 1 && visited[ni] == 0) {
          visited[ni] = 1;
          stack.add(ni);
        }
      }
      if (cy - 1 >= 0) {
        final int ni = cell - gridW;
        if (active[ni] == 1 && visited[ni] == 0) {
          visited[ni] = 1;
          stack.add(ni);
        }
      }
    }

    if (cellsInCluster >= _kMinClusterCells) {
      clusters.add(_Cluster(
        minX: minCx * _kGridStep,
        maxX: (maxCx + 1) * _kGridStep,
        minY: minCy * _kGridStep,
        maxY: (maxCy + 1) * _kGridStep,
        size: cellsInCluster,
      ));
    }
  }

  if (clusters.isEmpty) {
    clusters.add(_Cluster(
      minX: (inWidth * 0.20).toInt(),
      maxX: (inWidth * 0.80).toInt(),
      minY: (inHeight * 0.20).toInt(),
      maxY: (inHeight * 0.80).toInt(),
      size: 0,
    ));
  }

  clusters.sort((a, b) => b.size.compareTo(a.size));
  final selected = clusters.take(_kMaxRois).toList(growable: false);

  // ==========================================
  // PHASE 3: PER-ROI REVERSE-PROJECTION
  // ==========================================
  final int portraitWidth = inHeight;
  final int portraitHeight = inWidth;
  final List<PreprocessedRoi> rois = [];

  for (final c in selected) {
    final int nMinX = max(0, c.minX);
    final int nMaxX = min(inWidth, c.maxX);
    final int nMinY = max(0, c.minY);
    final int nMaxY = min(inHeight, c.maxY);
    if (nMaxX - nMinX < 8 || nMaxY - nMinY < 8) continue;

    final int pMinX = portraitWidth - 1 - nMaxY;
    final int pMaxX = portraitWidth - 1 - nMinY;
    final int pMinY = nMinX;
    final int pMaxY = nMaxX;
    final int pBoxWidth = pMaxX - pMinX;
    final int pBoxHeight = pMaxY - pMinY;
    if (pBoxWidth <= 0 || pBoxHeight <= 0) continue;

    final Float32List pixels = Float32List(modelWidth * modelHeight * 3);
    int pi = 0;

    for (int aiY = 0; aiY < modelHeight; aiY++) {
      final int pTargetY = pMinY + ((aiY * pBoxHeight) ~/ modelHeight);
      for (int aiX = 0; aiX < modelWidth; aiX++) {
        final int pTargetX = pMinX + ((aiX * pBoxWidth) ~/ modelWidth);

        final int nativeX = pTargetY;
        final int nativeY = inHeight - 1 - pTargetX;

        final int uvIndex =
            uvPixelStride * (nativeX >> 1) + uvRowStride * (nativeY >> 1);
        final int yIndex = nativeY * inWidth + nativeX;

        final int yp = yPlaneBytes[yIndex];
        final int up = uPlaneBytes[uvIndex];
        final int vp = vPlaneBytes[uvIndex];

        int r = (yp + vp * 1436 / 1024 - 179).round();
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .round();
        int b = (yp + up * 1814 / 1024 - 227).round();
        if (r < 0) r = 0; else if (r > 255) r = 255;
        if (g < 0) g = 0; else if (g > 255) g = 255;
        if (b < 0) b = 0; else if (b > 255) b = 255;

        pixels[pi++] = r / 255.0;
        pixels[pi++] = g / 255.0;
        pixels[pi++] = b / 255.0;
      }
    }

    rois.add(PreprocessedRoi(
      normalizedRect: Rect.fromLTRB(
        pMinX / portraitWidth,
        pMinY / portraitHeight,
        pMaxX / portraitWidth,
        pMaxY / portraitHeight,
      ),
      pixels: pixels,
    ));
  }

  return rois;
}
