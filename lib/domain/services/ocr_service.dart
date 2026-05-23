import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

/// Service for offline text recognition using Google ML Kit
/// Used as a secondary signal to boost recognition confidence.
/// The underlying `TextRecognizer` is only created if OCR is actually enabled.
class OcrService {
  TextRecognizer? _textRecognizer;
  bool _isInitialized = false;

  OcrService();

  /// Initialize OCR service
  Future<bool> initialize() async {
    if (!AppConstants.enableOcr) {
      debugPrint('OCR disabled in configuration');
      return false;
    }

    try {
      _textRecognizer ??=
          TextRecognizer(script: TextRecognitionScript.latin);
      _isInitialized = true;
      debugPrint('✓ OCR Service initialized (offline mode)');
      return true;
    } catch (e) {
      debugPrint('✗ Error initializing OCR: $e');
      return false;
    }
  }

  /// Extract text from image file
  Future<String?> extractTextFromFile(String imagePath) async {
    final recognizer = _textRecognizer;
    if (!_isInitialized || recognizer == null) {
      return null;
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await recognizer.processImage(inputImage);
      if (recognizedText.text.isEmpty) return null;
      return recognizedText.text;
    } catch (e) {
      debugPrint('✗ Error extracting text from file: $e');
      return null;
    }
  }

  /// Extract text from InputImage (for camera frames)
  Future<RecognizedText?> extractText(InputImage inputImage) async {
    final recognizer = _textRecognizer;
    if (!_isInitialized || recognizer == null) {
      return null;
    }

    try {
      return await recognizer.processImage(inputImage);
    } catch (e) {
      debugPrint('✗ Error in OCR: $e');
      return null;
    }
  }

  /// Calculate text similarity between two strings
  /// Simple implementation using normalized Levenshtein distance
  double calculateTextSimilarity(String text1, String text2) {
    if (text1.isEmpty || text2.isEmpty) return 0.0;

    final lower1 = text1.toLowerCase().trim();
    final lower2 = text2.toLowerCase().trim();

    if (lower1 == lower2) return 1.0;

    // Check for substring match
    if (lower1.contains(lower2) || lower2.contains(lower1)) {
      return 0.8;
    }

    // Calculate Levenshtein distance
    final distance = _levenshteinDistance(lower1, lower2);
    final maxLength = lower1.length > lower2.length ? lower1.length : lower2.length;
    
    return 1.0 - (distance / maxLength);
  }

  /// Levenshtein distance calculation
  int _levenshteinDistance(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;
    
    final matrix = List.generate(
      len1 + 1,
      (i) => List.filled(len2 + 1, 0),
    );

    for (int i = 0; i <= len1; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= len2; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[len1][len2];
  }

  /// Combine image similarity and text similarity
  /// OCR is used as a secondary signal when image similarity is near threshold
  double combineScores({
    required double imageSimilarity,
    required double textSimilarity,
    required double threshold,
  }) {
    // If image similarity is high, OCR doesn't matter much
    if (imageSimilarity > threshold + 0.1) {
      return imageSimilarity;
    }

    // If image similarity is near threshold, boost with OCR
    if (imageSimilarity > threshold - 0.1 && textSimilarity > AppConstants.ocrConfidenceThreshold) {
      // Weighted combination: 70% image, 30% text
      return (imageSimilarity * 0.7) + (textSimilarity * 0.3);
    }

    // Otherwise, use image similarity only
    return imageSimilarity;
  }

  /// Extract text blocks with bounding boxes
  List<TextBlock> getTextBlocks(RecognizedText recognizedText) {
    return recognizedText.blocks;
  }

  /// Dispose resources
  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
    _isInitialized = false;
    debugPrint('✓ OCR Service disposed');
  }

  bool get isInitialized => _isInitialized;
}
