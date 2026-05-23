import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../../core/constants/app_constants.dart';
import '../../core/utils/image_utils.dart';

/// Service for TensorFlow Lite model inference
/// Handles EfficientNet-Lite2 loading, embedding extraction, and hardware acceleration
class MLService {
  Interpreter? _interpreter;
  bool _isInitialized = false;
  String _currentModelPath = AppConstants.primaryModelPath;

  /// Initialize the TFLite interpreter with hardware acceleration
  Future<bool> initialize({String? modelPath}) async {
    if (_isInitialized) {
      return true;
    }

    try {
      _currentModelPath = modelPath ?? AppConstants.primaryModelPath;

      final interpreterOptions = InterpreterOptions();
      bool delegateAttached = false;

      // GPU delegate (OpenCL/OpenGL on Android — also taps the same SoC as
      // the NPU on Snapdragon). NNAPI is no longer shipped by tflite_flutter;
      // Google deprecated it in favor of GPU + XNNPACK.
      // Constants are raw ints because the underlying enum classes are not
      // part of the tflite_flutter public API.
      const int _gpuPrefFastSingleAnswer = 0;
      const int _gpuPriorityAuto = 0;
      const int _gpuPriorityMinLatency = 2;
      if (AppConstants.useGpuDelegate) {
        try {
          interpreterOptions.addDelegate(GpuDelegateV2(
            options: GpuDelegateOptionsV2(
              isPrecisionLossAllowed: true,
              inferencePreference: _gpuPrefFastSingleAnswer,
              inferencePriority1: _gpuPriorityMinLatency,
              inferencePriority2: _gpuPriorityAuto,
              inferencePriority3: _gpuPriorityAuto,
            ),
          ));
          delegateAttached = true;
          debugPrint('✓ GPU delegate enabled');
        } catch (e) {
          debugPrint('⚠ GPU delegate unavailable: $e');
        }
      }

      // CPU threading hint applied regardless — also helps kernels the GPU
      // delegate punts back to CPU. XNNPACK is on by default in this package
      // and provides the bulk of the CPU acceleration.
      interpreterOptions.threads = AppConstants.numThreads;

      _interpreter = await Interpreter.fromAsset(
        _currentModelPath,
        options: interpreterOptions,
      );

      _isInitialized = true;

      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      debugPrint('✓ Model loaded: $_currentModelPath '
          '(delegate=${delegateAttached ? "hw" : "cpu"})');
      debugPrint('  Input shape: $inputShape');
      debugPrint('  Output shape: $outputShape');

      return true;
    } catch (e) {
      debugPrint('✗ Error initializing ML model: $e');

      // Only fall back if a fallback path is configured AND we haven't already
      // tried it. A fallback model MUST produce the same embedding dimension
      // as the primary — otherwise cached dataset embeddings become incompatible.
      final fallback = AppConstants.fallbackModelPath;
      if (fallback != null && _currentModelPath == AppConstants.primaryModelPath) {
        debugPrint('Attempting fallback model: $fallback');
        return initialize(modelPath: fallback);
      }

      return false;
    }
  }

  /// Extract embedding vector from an image
  Future<List<double>?> extractEmbedding(img.Image image) async {
    if (!_isInitialized || _interpreter == null) {
      debugPrint('✗ ML Service not initialized');
      return null;
    }

    try {
      final inputData = ImageUtils.preprocessForModel(
        image,
        AppConstants.modelInputWidth,
        AppConstants.modelInputHeight,
      );
      return _runInference(inputData);
    } catch (e, stack) {
      debugPrint('✗ Error extracting embedding: $e\n$stack');
      rethrow;
    }
  }

  /// Extract embedding from preprocessed float data (for camera frames)
  Future<List<double>?> extractEmbeddingFromFloatData(Float32List imageData) async {
    if (!_isInitialized || _interpreter == null) {
      return null;
    }
    try {
      return _runInference(imageData);
    } catch (e) {
      debugPrint('✗ Error in inference: $e');
      return null;
    }
  }

  /// Shared inference path. Writes directly to the input tensor buffer and
  /// reads the output as a Float32List — avoids the per-frame allocation of
  /// nested `List<List<double>>` wrappers that the prior reshape required.
  List<double>? _runInference(Float32List imageData) {
    final interpreter = _interpreter;
    if (interpreter == null) return null;

    final inputTensor = interpreter.getInputTensor(0);
    final inputBuffer = inputTensor.data.buffer.asFloat32List();
    if (inputBuffer.length != imageData.length) {
      debugPrint(
          '✗ Input tensor size mismatch: tensor=${inputBuffer.length} '
          'data=${imageData.length}');
      return null;
    }
    inputBuffer.setAll(0, imageData);

    interpreter.invoke();

    final outputTensor = interpreter.getOutputTensor(0);
    final outputBuffer = outputTensor.data.buffer.asFloat32List();
    // Defensive: copy the output so the next invocation can't mutate it
    // underneath us (the tensor backing buffer is reused).
    final embedding = Float32List.fromList(outputBuffer);
    return _normalizeEmbedding(embedding);
  }

  /// Normalize embedding vector to unit length (L2). Required for cosine
  /// similarity to behave as a pure dot product downstream.
  List<double> _normalizeEmbedding(List<double> embedding) {
    final int n = embedding.length;
    double sumSquares = 0.0;
    for (int i = 0; i < n; i++) {
      final v = embedding[i];
      sumSquares += v * v;
    }
    final magnitude = sumSquares > 0 ? sqrt(sumSquares) : 1.0;
    final out = Float32List(n);
    final inv = 1.0 / magnitude;
    for (int i = 0; i < n; i++) {
      out[i] = embedding[i] * inv;
    }
    return out;
  }

  /// Calculate cosine similarity between two normalized embeddings.
  double calculateSimilarity(List<double> embedding1, List<double> embedding2) {
    final int n = embedding1.length;
    if (n != embedding2.length) {
      throw ArgumentError('Embeddings must have same dimension');
    }
    double dot = 0.0;
    for (int i = 0; i < n; i++) {
      dot += embedding1[i] * embedding2[i];
    }
    if (dot < -1.0) return -1.0;
    if (dot > 1.0) return 1.0;
    return dot;
  }

  /// Batch calculate similarities against multiple embeddings
  List<double> calculateSimilarities(
    List<double> queryEmbedding,
    List<List<double>> datasetEmbeddings,
  ) {
    return datasetEmbeddings
        .map((embedding) => calculateSimilarity(queryEmbedding, embedding))
        .toList();
  }

  /// Get model info
  Map<String, dynamic> getModelInfo() {
    if (!_isInitialized || _interpreter == null) {
      return {'initialized': false};
    }

    return {
      'initialized': true,
      'modelPath': _currentModelPath,
      'inputShape': _interpreter!.getInputTensor(0).shape,
      'outputShape': _interpreter!.getOutputTensor(0).shape,
      'inputType': _interpreter!.getInputTensor(0).type.toString(),
      'outputType': _interpreter!.getOutputTensor(0).type.toString(),
    };
  }

  /// Dispose resources
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    debugPrint('✓ ML Service disposed');
  }

  bool get isInitialized => _isInitialized;
}
