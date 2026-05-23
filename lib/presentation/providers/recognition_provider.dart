import 'package:flutter/material.dart';
import '../../data/models/recognition_result.dart';
import '../../domain/services/recognition_service.dart';
import '../../domain/services/camera_service.dart';

/// Provider for recognition state management
class RecognitionProvider with ChangeNotifier {
  final RecognitionService _recognitionService;
  final CameraService _cameraService;

  List<RecognitionResult> _currentResults = [];
  bool _isRecognizing = false;
  String? _error;
  int _framesProcessed = 0;
  int _totalFrames = 0;

  RecognitionProvider({
    required RecognitionService recognitionService,
    required CameraService cameraService,
  })  : _recognitionService = recognitionService,
        _cameraService = cameraService;

  // Getters
  List<RecognitionResult> get currentResults => _currentResults;
  bool get isRecognizing => _isRecognizing;
  String? get error => _error;
  int get framesProcessed => _framesProcessed;
  int get totalFrames => _totalFrames;
  CameraService get cameraService => _cameraService;

  /// Update recognition results
  void updateResults(List<RecognitionResult> results) {
    _currentResults = results;
    _framesProcessed++;
    notifyListeners();
  }

  /// Increment total frames counter
  void incrementTotalFrames() {
    _totalFrames++;
  }

  /// Start recognition
  void startRecognition() {
    _isRecognizing = true;
    _framesProcessed = 0;
    _totalFrames = 0;
    _recognitionService.resetAggregation();
    notifyListeners();
  }

  /// Stop recognition
  void stopRecognition() {
    _isRecognizing = false;
    _currentResults = [];
    notifyListeners();
  }

  /// Reset aggregation
  void resetAggregation() {
    _recognitionService.resetAggregation();
    _currentResults = [];
    notifyListeners();
  }

  /// Set error
  void setError(String error) {
    _error = error;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get processing statistics
  Map<String, dynamic> getStats() {
    return {
      'framesProcessed': _framesProcessed,
      'totalFrames': _totalFrames,
      'processingRate': _totalFrames > 0 
          ? (_framesProcessed / _totalFrames * 100).toStringAsFixed(1) 
          : '0.0',
      'currentMatches': _currentResults.length,
    };
  }
}
