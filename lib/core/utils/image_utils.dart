import 'dart:async';
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
// Maximum ROIs per frame. Each ROI = one model invocation, so this caps the
// per-frame ML cost. 3 is a comfortable balance on CPU+XNNPACK.
const int _kMaxRois = 3;
// Minimum edge count for a cell to be considered a peak candidate.
const int _kMinPeakEdges = 6;
// Non-max-suppression radius (in grid cells). Two peaks closer than this
// collapse to one — prevents the same object generating two overlapping ROIs.
const int _kNmsRadiusCells = 8;

class ImageUtils {
  /// Multi-ROI pipeline. Heavy YUV→RGB / clustering / reprojection work runs
  /// on a long-lived worker isolate so the UI thread stays free AND we don't
  /// pay isolate-spawn overhead on every frame.
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
      final worker = await _PipelineWorker.ensure();
      return await worker.submit(job);
    } catch (e) {
      debugPrint('Pipeline worker error: $e');
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

class _Peak {
  final int cx;
  final int cy;
  final int density;
  const _Peak({required this.cx, required this.cy, required this.density});
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
  // PHASE 2: PEAK DETECTION + NON-MAX SUPPRESSION
  //
  // Connected-components had the failure mode that adjacent objects merged
  // into one big cluster (4-neighbour BFS bridges them through shared edges).
  // Instead: find local maxima in the edge-density grid, rank by density,
  // suppress peaks that are within `_kNmsRadiusCells` of a stronger one.
  // This keeps the strongest few "centres of attention" as separate ROIs.
  // ==========================================
  final List<_Peak> peaks = [];
  for (int cy = 1; cy < gridH - 1; cy++) {
    for (int cx = 1; cx < gridW - 1; cx++) {
      final int v = edgeCount[cy * gridW + cx];
      if (v < _kMinPeakEdges) continue;
      // 3x3 local max test
      bool isMax = true;
      for (int dy = -1; dy <= 1 && isMax; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          if (edgeCount[(cy + dy) * gridW + (cx + dx)] > v) {
            isMax = false;
            break;
          }
        }
      }
      if (isMax) peaks.add(_Peak(cx: cx, cy: cy, density: v));
    }
  }
  peaks.sort((a, b) => b.density.compareTo(a.density));

  final List<_Peak> kept = [];
  for (final p in peaks) {
    bool tooClose = false;
    for (final s in kept) {
      if ((s.cx - p.cx).abs() < _kNmsRadiusCells &&
          (s.cy - p.cy).abs() < _kNmsRadiusCells) {
        tooClose = true;
        break;
      }
    }
    if (!tooClose) {
      kept.add(p);
      if (kept.length >= _kMaxRois) break;
    }
  }

  // Window radius for each ROI, in cells. ~1/4 of the shorter grid dimension
  // gives an ROI of ~25% of the frame, which scales cleanly into 224x224.
  final int halfWin = max(3, min(gridW, gridH) ~/ 5);

  final List<_Cluster> clusters = [];
  for (final p in kept) {
    final int nMinX = max(0, (p.cx - halfWin) * _kGridStep);
    final int nMaxX = min(inWidth, (p.cx + halfWin + 1) * _kGridStep);
    final int nMinY = max(0, (p.cy - halfWin) * _kGridStep);
    final int nMaxY = min(inHeight, (p.cy + halfWin + 1) * _kGridStep);
    clusters.add(_Cluster(
      minX: nMinX,
      maxX: nMaxX,
      minY: nMinY,
      maxY: nMaxY,
      size: p.density,
    ));
  }

  // Fallback when no peaks: probe four overlapping quadrants instead of one
  // centre window — much higher chance of catching at least one real object.
  if (clusters.isEmpty) {
    final int hw = inWidth ~/ 2;
    final int hh = inHeight ~/ 2;
    // 60%-sized windows positioned at each quadrant centre; produces some
    // overlap which is fine because NMS is over peaks, not over fallback ROIs.
    final int wMargin = (inWidth * 0.10).toInt();
    final int hMargin = (inHeight * 0.10).toInt();
    void addBox(int x0, int y0, int x1, int y1) {
      clusters.add(_Cluster(
        minX: max(0, x0), maxX: min(inWidth, x1),
        minY: max(0, y0), maxY: min(inHeight, y1),
        size: 0,
      ));
    }
    addBox(wMargin, hMargin, hw + wMargin, hh + hMargin);
    addBox(hw - wMargin, hMargin, inWidth - wMargin, hh + hMargin);
    addBox(wMargin, hh - hMargin, hw + wMargin, inHeight - hMargin);
    addBox(hw - wMargin, hh - hMargin, inWidth - wMargin, inHeight - hMargin);
  }

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

/// Long-lived worker isolate that runs `_runFramePipelineSync` on demand.
/// Spawned once on the first frame and reused for the app lifetime — avoids
/// the per-frame `Isolate.run` startup cost.
class _PipelineWorker {
  static _PipelineWorker? _instance;
  static Future<_PipelineWorker>? _spawning;

  static Future<_PipelineWorker> ensure() {
    final cached = _instance;
    if (cached != null) return Future.value(cached);
    return _spawning ??= () async {
      final w = _PipelineWorker._();
      await w._spawn();
      _instance = w;
      _spawning = null;
      return w;
    }();
  }

  _PipelineWorker._();

  late SendPort _sendPort;
  late ReceivePort _resultPort;
  final Map<int, Completer<List<PreprocessedRoi>>> _pending = {};
  int _nextId = 0;

  Future<void> _spawn() async {
    _resultPort = ReceivePort();
    final initPort = ReceivePort();
    await Isolate.spawn(
      _workerEntry,
      <SendPort>[initPort.sendPort, _resultPort.sendPort],
      debugName: 'visual-recognition-pipeline',
    );
    _sendPort = await initPort.first as SendPort;
    initPort.close();
    _resultPort.listen(_onResult);
  }

  void _onResult(dynamic msg) {
    final list = msg as List;
    final id = list[0] as int;
    final payload = list[1];
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (payload is List<PreprocessedRoi>) {
      completer.complete(payload);
    } else {
      completer.complete(const <PreprocessedRoi>[]);
    }
  }

  Future<List<PreprocessedRoi>> submit(_FrameJob job) {
    final id = _nextId++;
    final completer = Completer<List<PreprocessedRoi>>();
    _pending[id] = completer;
    _sendPort.send(<Object>[id, job]);
    return completer.future;
  }
}

void _workerEntry(List<SendPort> ports) {
  final initPort = ports[0];
  final resultPort = ports[1];
  final commandPort = ReceivePort();
  initPort.send(commandPort.sendPort);
  commandPort.listen((dynamic msg) {
    final list = msg as List;
    final id = list[0] as int;
    final job = list[1] as _FrameJob;
    try {
      final result = _runFramePipelineSync(job);
      resultPort.send(<Object>[id, result]);
    } catch (e) {
      resultPort.send(<Object>[id, e.toString()]);
    }
  });
}
