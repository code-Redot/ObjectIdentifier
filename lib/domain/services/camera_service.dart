import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

/// Service for managing camera operations
/// Handles initialization, frame streaming, and lifecycle management
class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isStreaming = false;
  
  StreamController<CameraImage>? _frameStreamController;
  int _frameCounter = 0;

  /// Initialize camera with optimal settings for S23/S24
  Future<bool> initialize() async {
    if (_isInitialized) {
      return true;
    }

    try {
      _cameras = await availableCameras();
      
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('✗ No cameras available');
        return false;
      }

      // Use back camera
      final camera = _cameras!.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.max, // Highest resolution for great UI passthrough
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // Best for Android
      );

      await _controller!.initialize();
      
      _isInitialized = true;
      debugPrint('✓ Camera initialized: ${camera.name}');
      debugPrint('  Resolution: ${_controller!.value.previewSize}');
      
      return true;
    } catch (e) {
      debugPrint('✗ Error initializing camera: $e');
      return false;
    }
  }

  /// Start streaming frames for recognition
  /// Implements aggressive frame throttling (max 5 FPS for ML)
  void startFrameStream(Function(CameraImage) onFrame) {
    if (!_isInitialized || _controller == null) {
      debugPrint('✗ Camera not initialized');
      return;
    }

    if (_isStreaming) {
      debugPrint('⚠ Frame stream already active');
      return;
    }

    _frameCounter = 0;
    _isStreaming = true;

    _controller!.startImageStream((CameraImage image) {
      // Modulo keeps cadence consistent without ever overflowing.
      // Dart ints don't overflow, but we still keep the counter small.
      _frameCounter = (_frameCounter + 1) % AppConstants.frameSkipRatio;
      if (_frameCounter == 0) {
        onFrame(image);
      }
    });

    debugPrint('✓ Frame stream started (processing every ${AppConstants.frameSkipRatio}th frame)');
  }

  /// Stop frame streaming
  Future<void> stopFrameStream() async {
    if (!_isStreaming || _controller == null) {
      return;
    }

    try {
      await _controller!.stopImageStream();
      _isStreaming = false;
      _frameCounter = 0;
      debugPrint('✓ Frame stream stopped');
    } catch (e) {
      debugPrint('✗ Error stopping frame stream: $e');
    }
  }

  /// Take a still picture
  Future<XFile?> takePicture() async {
    if (!_isInitialized || _controller == null) {
      return null;
    }

    try {
      // Stop streaming if active
      final wasStreaming = _isStreaming;
      if (wasStreaming) {
        await stopFrameStream();
      }

      final image = await _controller!.takePicture();
      
      // Resume streaming if it was active
      if (wasStreaming) {
        // Note: caller should restart stream manually
      }

      return image;
    } catch (e) {
      debugPrint('✗ Error taking picture: $e');
      return null;
    }
  }

  /// Set flash mode
  Future<void> setFlashMode(FlashMode mode) async {
    if (_controller != null) {
      await _controller!.setFlashMode(mode);
    }
  }

  /// Set focus mode
  Future<void> setFocusMode(FocusMode mode) async {
    if (_controller != null) {
      await _controller!.setFocusMode(mode);
    }
  }

  /// Set focus point (tap to focus)
  Future<void> setFocusPoint(Offset point) async {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        await _controller!.setFocusPoint(point);
        await _controller!.setExposurePoint(point);
      } catch (e) {
        debugPrint('⚠ Error setting focus point: $e');
      }
    }
  }

  /// Pause camera (for app lifecycle)
  Future<void> pause() async {
    if (_isStreaming) {
      await stopFrameStream();
    }
    await _controller?.pausePreview();
  }

  /// Resume camera
  Future<void> resume() async {
    await _controller?.resumePreview();
    // Caller should restart stream if needed
  }

  /// Dispose camera resources
  Future<void> dispose() async {
    if (_isStreaming) {
      await stopFrameStream();
    }
    
    await _controller?.dispose();
    _controller = null;
    _cameras = null;
    _isInitialized = false;
    _frameStreamController?.close();
    
    debugPrint('✓ Camera service disposed');
  }

  // Getters
  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get isStreaming => _isStreaming;
  Size? get previewSize => _controller?.value.previewSize;
  
  /// Get camera aspect ratio
  double get aspectRatio {
    if (!_isInitialized || _controller == null) {
      return 16 / 9; // Default
    }
    return _controller!.value.aspectRatio;
  }
}
