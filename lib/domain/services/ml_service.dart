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
      return await _runInferenceWithRecovery(inputData);
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
      return await _runInferenceWithRecovery(imageData);
    } catch (e) {
      debugPrint('✗ Error in inference: $e');
      return null;
    }
  }

  /// Inference with one recovery attempt: if the underlying native call fails
  /// (typical cause: GPU delegate's EGL/CL context was lost while the activity
  /// was paused for the system camera, or the interpreter otherwise entered a
  /// bad state), close + reopen the interpreter and retry once. If the retry
  /// also fails, rethrow the original diagnostic-rich error.
  Future<List<double>?> _runInferenceWithRecovery(Float32List imageData) async {
    try {
      return _runInference(imageData);
    } catch (firstError, firstStack) {
      debugPrint('⚠ Inference failed, attempting interpreter reinit: $firstError');
      try {
        _interpreter?.close();
      } catch (_) {/* ignore — already closed or broken */}
      _interpreter = null;
      _isInitialized = false;

      final reinit = await initialize(modelPath: _currentModelPath);
      if (!reinit) {
        debugPrint('✗ Reinit failed — surfacing original error');
        Error.throwWithStackTrace(firstError, firstStack);
      }

      try {
        final result = _runInference(imageData);
        debugPrint('✓ Inference recovered after interpreter reinit');
        return result;
      } catch (retryError) {
        debugPrint('✗ Inference still failing after reinit: $retryError');
        Error.throwWithStackTrace(firstError, firstStack);
      }
    }
  }

  /// Single inference attempt. Throws a diagnostic StateError on failure.
  /// `Tensor.data` in tflite_flutter 0.11 is an UnmodifiableUint8ListView, so
  /// the documented inference path is `Interpreter.run(reshapedInput, output)`.
  List<double>? _runInference(Float32List imageData) {
    final interpreter = _interpreter;
    if (interpreter == null) return null;

    final expected = AppConstants.modelInputWidth *
        AppConstants.modelInputHeight *
        AppConstants.modelInputChannels;
    if (imageData.length != expected) {
      debugPrint(
          '✗ Input size mismatch: got=${imageData.length} expected=$expected');
      return null;
    }

    final input = imageData.reshape<double>([
      1,
      AppConstants.modelInputHeight,
      AppConstants.modelInputWidth,
      AppConstants.modelInputChannels,
    ]);
    // tflite_flutter's output reader produces a List<List<double>> and writes
    // the inner list straight into output[0]. The slot must be `List<double>`
    // — a Float32List slot would TypeError ("List<double> is not Float32List").
    final output = <List<double>>[
      List<double>.filled(AppConstants.embeddingDimension, 0.0),
    ];

    try {
      interpreter.run(input, output);
    } catch (e) {
      // tflite_flutter wraps native failures in `checkState` which throws
      // `StateError('failed precondition')` — useless on its own. Annotate
      // with the tensor shape so we know which side mismatched, and dump the
      // model's declared shape for comparison.
      final inT = interpreter.getInputTensor(0);
      final outT = interpreter.getOutputTensor(0);
      throw StateError(
        'TFLite inference failed: $e\n'
        '  input tensor: shape=${inT.shape} type=${inT.type}\n'
        '  output tensor: shape=${outT.shape} type=${outT.type}\n'
        '  supplied input flat-length=${imageData.length} '
        '(expected ${AppConstants.modelInputWidth * AppConstants.modelInputHeight * AppConstants.modelInputChannels})\n'
        '  supplied output slot length=${output[0].length} '
        '(expected ${AppConstants.embeddingDimension})',
      );
    }

    return _normalizeEmbedding(output[0]);
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
