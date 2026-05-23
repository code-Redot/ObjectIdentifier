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
  static const double similarityThreshold = 0.72; // Cosine similarity threshold
  static const int maxMatchResults = 5; // Max simultaneous detections
  static const int resultAggregationFrames = 3; // Frames to aggregate for stability
  
  // Camera Configuration - Optimized for S23/S24
  static const int targetFrameRate = 30; // Camera capture FPS
  static const int processingFrameRate = 6; // ML inference FPS (every 5th frame)
  static const int frameSkipRatio = 5; // Process every Nth frame
  
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
  // deprecated it in favor of GPU + XNNPACK), so we only toggle the GPU path.
  static const bool useGpuDelegate = true;
  static const int numThreads = 4;
  
  // OCR Configuration
  static const bool enableOcr = true;
  static const double ocrConfidenceThreshold = 0.6;
  
  // Image Quality Validation
  static const int minImageWidth = 100;
  static const int minImageHeight = 100;
  static const int maxImageSizeMB = 10;
}
