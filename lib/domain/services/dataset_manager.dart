import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;
import '../../data/models/dataset_item.dart';
import '../../data/repositories/dataset_repository.dart';
import '../../data/storage/hive_storage.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/color_palette.dart';
import '../../core/utils/image_utils.dart';
import 'ml_service.dart';
import 'ocr_service.dart';

/// Service for managing the dataset of recognized items
/// Handles adding, updating, deleting items and computing embeddings
class DatasetManager {
  final DatasetRepository _repository;
  final MLService _mlService;
  final OcrService _ocrService;
  final ImagePicker _imagePicker;
  final Uuid _uuid;

  DatasetManager({
    DatasetRepository? repository,
    required MLService mlService,
    required OcrService ocrService,
  })  : _repository = repository ?? DatasetRepository(),
        _mlService = mlService,
        _ocrService = ocrService,
        _imagePicker = ImagePicker(),
        _uuid = const Uuid();

  /// Add item from camera
  Future<DatasetItem?> addItemFromCamera({
    required String name,
    required Color color,
  }) async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (photo == null) {
        debugPrint('⚠ Camera capture cancelled');
        return null;
      }

      return await _processAndAddItem(
        imagePath: photo.path,
        name: name,
        color: color,
        source: 'camera',
      );
    } catch (e) {
      debugPrint('✗ Error adding item from camera: $e');
      rethrow;
    }
  }

  /// Add item from gallery
  Future<DatasetItem?> addItemFromGallery({
    required String name,
    required Color color,
  }) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (image == null) {
        debugPrint('⚠ Gallery selection cancelled');
        return null;
      }

      return await _processAndAddItem(
        imagePath: image.path,
        name: name,
        color: color,
        source: 'gallery',
      );
    } catch (e) {
      debugPrint('✗ Error adding item from gallery: $e');
      rethrow;
    }
  }

  /// Add item from file path (for programmatic use)
  Future<DatasetItem?> addItemFromFile({
    required String imagePath,
    required String name,
    required Color color,
    String source = 'file',
  }) async {
    return await _processAndAddItem(
      imagePath: imagePath,
      name: name,
      color: color,
      source: source,
    );
  }

  /// Process image and add to dataset
  Future<DatasetItem?> _processAndAddItem({
    required String imagePath,
    required String name,
    required Color color,
    required String source,
    String? ocrText,
  }) async {
    try {
      // MANDATORY: Enforce high-contrast color validation
      // Reject near-white, near-black, and low-saturation colors
      if (!ColorPalette.isValidColor(color)) {
        debugPrint('✗ Invalid color: fails high-contrast validation');
        throw ArgumentError(
          'Color must be high-contrast (luminance 0.1-0.9, not near-white/black)',
        );
      }

      // Check dataset size limit
      final canAdd = await _repository.canAddItem(AppConstants.maxDatasetSize);
      if (!canAdd) {
        debugPrint('✗ Dataset size limit reached (${AppConstants.maxDatasetSize} items)');
        throw StateError(
          'Dataset is full. Maximum ${AppConstants.maxDatasetSize} items allowed.',
        );
      }

      // Load and validate image — bail before decoding huge files.
      final image = await ImageUtils.loadImageFromFile(
        imagePath,
        maxBytes: AppConstants.maxImageSizeMB * 1024 * 1024,
      );
      if (image == null) {
        debugPrint('✗ Failed to load image (missing/too-large/unreadable): $imagePath');
        throw Exception(
            'Image is missing, unreadable, or exceeds ${AppConstants.maxImageSizeMB}MB');
      }

      if (!ImageUtils.isValidImage(
          image, AppConstants.minImageWidth, AppConstants.minImageHeight)) {
        debugPrint('✗ Image too small');
        throw Exception(
            'Image too small (must be at least ${AppConstants.minImageWidth}x${AppConstants.minImageHeight} pixels)');
      }

      // EMBEDDING CACHE ENFORCEMENT:
      // Compute embedding ONLY ONCE at import time
      // This embedding will be stored in Hive and NEVER recomputed
      debugPrint('⏳ Computing embedding (one-time operation)...');
      final embedding = await _mlService.extractEmbedding(image);
      if (embedding == null) {
        debugPrint('✗ Failed to extract embedding');
        throw Exception('Failed to extract embedding from image');
      }
      debugPrint('✓ Embedding computed and will be cached');

      // Extract OCR text if service is available
      String? extractedOcrText = ocrText;
      if (extractedOcrText == null && _ocrService.isInitialized) {
        debugPrint('⏳ Extracting OCR text...');
        extractedOcrText = await _ocrService.extractTextFromFile(imagePath);
        if (extractedOcrText != null && extractedOcrText.isNotEmpty) {
           debugPrint('✓ OCR text extracted: ${extractedOcrText.substring(0, extractedOcrText.length > 50 ? 50 : extractedOcrText.length)}...');
        }
      }

      // Copy image to app storage
      final imagesDir = await HiveStorage.instance.getImagesDirectory();
      final imageId = _uuid.v4();
      final extension = imagePath.split('.').last;
      final savedPath = '${imagesDir.path}/$imageId.$extension';

      final savedFile = await File(imagePath).copy(savedPath);

      // Create dataset item
      final item = DatasetItem(
        id: const Uuid().v4(),
        name: name,
        imagePath: savedPath,
        embedding: embedding,
        colorValue: color.value,
        createdAt: DateTime.now(),
        source: source,
        ocrText: extractedOcrText,
      );

      // Persist to Hive; if that throws, undo the file copy to avoid orphans.
      try {
        await _repository.addItem(item);
      } catch (e) {
        try {
          if (await savedFile.exists()) await savedFile.delete();
        } catch (_) {/* best-effort cleanup */}
        rethrow;
      }
      debugPrint('✓ Dataset item added with cached embedding');

      return item;
    } catch (e) {
      debugPrint('✗ Error adding item: $e');
      // Re-throw to allow UI to handle
      rethrow;
    }
  }

  /// Update item color (single item).
  Future<bool> updateItemColor(String itemId, Color newColor) async {
    try {
      final item = await _repository.getItemById(itemId);
      if (item == null) return false;

      final updated = item.copyWith(colorValue: newColor.value);
      await _repository.updateItem(updated);

      debugPrint('✓ Color updated for: ${item.name}');
      return true;
    } catch (e) {
      debugPrint('✗ Error updating color: $e');
      return false;
    }
  }

  /// Update color for ALL items that share the given group name.
  /// Returns the number of items updated.
  Future<int> updateGroupColor(String groupName, Color newColor) async {
    int updated = 0;
    try {
      final items = await _repository.getAllItems();
      for (final item in items) {
        if (item.name != groupName) continue;
        await _repository.updateItem(
          item.copyWith(colorValue: newColor.value),
        );
        updated++;
      }
      debugPrint('✓ Color updated for $updated items in group "$groupName"');
    } catch (e) {
      debugPrint('✗ Error updating group color: $e');
    }
    return updated;
  }

  /// Update item name
  Future<bool> updateItemName(String itemId, String newName) async {
    try {
      final item = await _repository.getItemById(itemId);
      if (item == null) return false;

      final updated = item.copyWith(name: newName);
      await _repository.updateItem(updated);
      
      debugPrint('✓ Name updated: $newName');
      return true;
    } catch (e) {
      debugPrint('✗ Error updating name: $e');
      return false;
    }
  }

  /// Delete item
  Future<bool> deleteItem(String itemId) async {
    try {
      await _repository.deleteItem(itemId);
      debugPrint('✓ Item deleted');
      return true;
    } catch (e) {
      debugPrint('✗ Error deleting item: $e');
      return false;
    }
  }

  /// Get all items
  Future<List<DatasetItem>> getAllItems() async {
    return await _repository.getAllItems();
  }

  /// Get item by ID
  Future<DatasetItem?> getItemById(String id) async {
    return await _repository.getItemById(id);
  }

  /// Search items
  Future<List<DatasetItem>> searchItems(String query) async {
    return await _repository.searchByName(query);
  }

  /// Get statistics
  Future<Map<String, dynamic>> getStatistics() async {
    return await _repository.getStatistics();
  }

  /// Clear entire dataset
  Future<bool> clearDataset() async {
    try {
      await _repository.clearDataset();
      debugPrint('✓ Dataset cleared');
      return true;
    } catch (e) {
      debugPrint('✗ Error clearing dataset: $e');
      return false;
    }
  }

  /// Validate dataset integrity
  Future<Map<String, dynamic>> validateDataset() async {
    final items = await getAllItems();
    int validItems = 0;
    int invalidEmbeddings = 0;
    int missingImages = 0;

    for (final item in items) {
      bool isValid = true;

      // Check embedding
      if (!item.hasValidEmbedding(AppConstants.embeddingDimension)) {
        invalidEmbeddings++;
        isValid = false;
      }

      // Check image file
      if (!await File(item.imagePath).exists()) {
        missingImages++;
        isValid = false;
      }

      if (isValid) validItems++;
    }

    return {
      'totalItems': items.length,
      'validItems': validItems,
      'invalidEmbeddings': invalidEmbeddings,
      'missingImages': missingImages,
    };
  }
}
