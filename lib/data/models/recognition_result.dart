import 'package:flutter/material.dart';
import 'dataset_item.dart';

/// Result of a recognition operation
/// Contains the matched item, confidence score, and optional bounding box
class RecognitionResult {
  final DatasetItem matchedItem;
  final double confidence; // Cosine similarity score (0.0 - 1.0)
  final Rect? boundingBox; // Optional bounding box in image coordinates
  final DateTime timestamp;
  final String? detectedText; // OCR text from current frame (if different from stored)

  RecognitionResult({
    required this.matchedItem,
    required this.confidence,
    this.boundingBox,
    DateTime? timestamp,
    this.detectedText,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Get the color for rendering this result
  Color get color => Color(matchedItem.colorValue);

  /// Check if confidence meets threshold
  bool meetsThreshold(double threshold) => confidence >= threshold;

  /// Create a copy with updated fields
  RecognitionResult copyWith({
    DatasetItem? matchedItem,
    double? confidence,
    Rect? boundingBox,
    DateTime? timestamp,
    String? detectedText,
  }) {
    return RecognitionResult(
      matchedItem: matchedItem ?? this.matchedItem,
      confidence: confidence ?? this.confidence,
      boundingBox: boundingBox ?? this.boundingBox,
      timestamp: timestamp ?? this.timestamp,
      detectedText: detectedText ?? this.detectedText,
    );
  }

  @override
  String toString() {
    return 'RecognitionResult(item: ${matchedItem.name}, confidence: ${confidence.toStringAsFixed(3)})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecognitionResult &&
        other.matchedItem == matchedItem &&
        other.confidence == confidence;
  }

  @override
  int get hashCode => Object.hash(matchedItem, confidence);
}

/// Aggregated recognition results over multiple frames
/// Used to stabilize detection and reduce flickering
class AggregatedResult {
  final DatasetItem item;
  final List<double> confidenceHistory;
  final List<Rect?> boundingBoxHistory;
  
  AggregatedResult({
    required this.item,
    required this.confidenceHistory,
    required this.boundingBoxHistory,
  });

  /// Get average confidence
  double get averageConfidence {
    if (confidenceHistory.isEmpty) return 0.0;
    return confidenceHistory.reduce((a, b) => a + b) / confidenceHistory.length;
  }

  /// Get most recent bounding box
  Rect? get latestBoundingBox {
    return boundingBoxHistory.lastWhere(
      (box) => box != null,
      orElse: () => null,
    );
  }

  /// Add new observation. Single allocation per call: the start offset shifts
  /// when the buffer is full, no `removeAt(0)`.
  AggregatedResult addObservation(double confidence, Rect? boundingBox, int maxHistory) {
    final int newLen = confidenceHistory.length + 1;
    if (newLen <= maxHistory) {
      return AggregatedResult(
        item: item,
        confidenceHistory: [...confidenceHistory, confidence],
        boundingBoxHistory: [...boundingBoxHistory, boundingBox],
      );
    }
    // Drop the oldest sample in a single pass.
    final int keep = maxHistory - 1;
    final newConfidences = List<double>.generate(
      maxHistory,
      (i) => i < keep ? confidenceHistory[i + 1] : confidence,
      growable: false,
    );
    final newBoxes = List<Rect?>.generate(
      maxHistory,
      (i) => i < keep ? boundingBoxHistory[i + 1] : boundingBox,
      growable: false,
    );
    return AggregatedResult(
      item: item,
      confidenceHistory: newConfidences,
      boundingBoxHistory: newBoxes,
    );
  }
}
