/// Application-wide constants for configuration and tuning
class AppConstants {
  // ML Model Configuration
  // MediaPipe MobileNetV3-Large image embedder.
  // Input: 224x224x3, Output: 1280-d L2-normalized feature vector.
  static const String primaryModelPath = 'assets/models/mobilenet_v3_large.tflite';
  // No safe fallback: a fallback must produce the SAME embedding dimension as
  // the primary, otherwise cached dataset embeddings become incompatible.
  static const String? fallbackModelPath = null;

  static const int modelInputWidth = 224;
  static const int modelInputHeight = 224;
  static const int modelInputChannels = 3;

  static const int embeddingDimension = 1280;
  
  // Recognition Configuration
  // MobileNetV3 cross-view cosine similarity for the same physical object
  // typically falls in 0.55–0.80 once you account for crop/lighting/angle.
  // Tighter thresholds will reject real matches; looser thresholds cause
  // false positives across visually similar classes.
  static const double similarityThreshold = 0.55;
  static const int maxMatchResults = 3;
  static const int resultAggregationFrames = 3;

  // Camera Configuration
  static const int targetFrameRate = 30;
  // Process every Nth frame. Higher = better UI smoothness, lower inference
  // throughput. With maxRois ≤ 2 and CPU inference, 8 keeps the UI responsive
  // and still gives ~3.5 inferences/sec.
  static const int frameSkipRatio = 8;
  static const int processingFrameRate = targetFrameRate ~/ frameSkipRatio;
  
  // S23/S24 optimal resolution for balance between quality and performance
  static const int cameraWidth = 1920;
  static const int cameraHeight = 1080;
  
  // Storage Configuration
  static const String hiveBoxName = 'dataset_box';
  static const String imagesDirectoryName = 'dataset_images';
  static const int maxDatasetSize = 1000; // Max items in dataset
  
  // UI Configuration
  static const double boundingBoxStrokeWidth = 3.0;
  static const double boundingBoxCornerRadius = 8.0;
  static const double confidenceLabelFontSize = 14.0;
  
  // Performance tuning. NNAPI is no longer shipped by tflite_flutter (Google
  // deprecated it in favor of GPU + XNNPACK).
  //
  // GPU delegate is OFF by default: it works while the app is in foreground
  // but its EGL/CL context can be torn down when Android pauses the activity
  // (e.g. when image_picker launches the system camera), which leaves the
  // interpreter in a state where the next invoke() fails with
  // "Bad state: failed precondition". CPU + XNNPACK is fast enough for
  // MobileNetV3 Large @ 224 and survives lifecycle events cleanly.
  static const bool useGpuDelegate = false;
  static const int numThreads = 4;
  
  // OCR Configuration
  static const bool enableOcr = true;
  static const double ocrConfidenceThreshold = 0.6;
  
  // Image Quality Validation
  static const int minImageWidth = 100;
  static const int minImageHeight = 100;
  static const int maxImageSizeMB = 10;
}
