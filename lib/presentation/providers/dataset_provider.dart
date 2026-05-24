import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../data/models/dataset_item.dart';
import '../../domain/services/dataset_manager.dart';
import '../../domain/services/ml_service.dart';
import '../../domain/services/ocr_service.dart';
import '../../core/constants/color_palette.dart';

/// Provider for dataset state management
class DatasetProvider with ChangeNotifier {
  final DatasetManager _datasetManager;
  
  List<DatasetItem> _items = [];
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic> _statistics = {};

  DatasetProvider({
    required MLService mlService,
    required OcrService ocrService,
  }) : _datasetManager = DatasetManager(
          mlService: mlService,
          ocrService: ocrService,
        );

  // Getters
  List<DatasetItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic> get statistics => _statistics;
  int get itemCount => _items.length;

  /// Initialize and load dataset
  Future<void> initialize() async {
    await loadItems();
    await loadStatistics();
  }

  /// Load all items from storage
  Future<void> loadItems() async {
    _setLoading(true);
    try {
      _items = await _datasetManager.getAllItems();
      _error = null;
    } catch (e) {
      _error = 'Failed to load items: $e';
      debugPrint('✗ $_error');
    } finally {
      _setLoading(false);
    }
  }

  /// Load statistics
  Future<void> loadStatistics() async {
    try {
      _statistics = await _datasetManager.getStatistics();
      notifyListeners();
    } catch (e) {
      debugPrint('✗ Error loading statistics: $e');
    }
  }

  /// Add item from camera
  /// 
  /// EMBEDDING CACHE ENFORCEMENT:
  /// Embedding is computed ONCE during this operation and cached in Hive.
  /// It will NEVER be recomputed during recognition.
  Future<bool> addItemFromCamera(String name, Color color) async {
    _setLoading(true);
    try {
      final item = await _datasetManager.addItemFromCamera(
        name: name,
        color: color,
      );
      
      if (item != null) {
        _items.add(item);
        await loadStatistics();
        _error = null;
        notifyListeners();
        return true;
      }
      return false;
    } on ArgumentError catch (e) {
      // Color validation failed
      _error = e.message;
      debugPrint('✗ $_error');
      notifyListeners();
      return false;
    } on StateError catch (e) {
      // Dataset size limit reached
      _error = e.message;
      debugPrint('✗ $_error');
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to add item: $e';
      debugPrint('✗ $_error');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Add item from gallery
  /// 
  /// EMBEDDING CACHE ENFORCEMENT:
  /// Embedding is computed ONCE during this operation and cached in Hive.
  /// It will NEVER be recomputed during recognition.
  Future<bool> addItemFromGallery(String name, Color color) async {
    _setLoading(true);
    try {
      final item = await _datasetManager.addItemFromGallery(
        name: name,
        color: color,
      );
      
      if (item != null) {
        _items.add(item);
        await loadStatistics();
        _error = null;
        notifyListeners();
        return true;
      }
      return false;
    } on ArgumentError catch (e) {
      // Color validation failed
      _error = e.message;
      debugPrint('✗ $_error');
      notifyListeners();
      return false;
    } on StateError catch (e) {
      // Dataset size limit reached
      _error = e.message;
      debugPrint('✗ $_error');
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Failed to add item: $e';
      debugPrint('✗ $_error');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Update color across every item sharing the given group name.
  /// Items are grouped by `name` in the UI, so this keeps the cohort
  /// visually consistent (one colour per real-world object).
  Future<bool> updateGroupColor(String groupName, Color newColor) async {
    try {
      if (!ColorPalette.isValidColor(newColor)) {
        _error = 'Invalid color: must be high-contrast';
        notifyListeners();
        return false;
      }

      final updated = await _datasetManager.updateGroupColor(groupName, newColor);
      if (updated == 0) return false;

      bool changed = false;
      for (int i = 0; i < _items.length; i++) {
        if (_items[i].name == groupName) {
          _items[i] = _items[i].copyWith(colorValue: newColor.value);
          changed = true;
        }
      }
      if (changed) notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to update group color: $e';
      debugPrint('✗ $_error');
      notifyListeners();
      return false;
    }
  }

  /// Update item color (in-place — avoids reloading entire dataset).
  Future<bool> updateItemColor(String itemId, Color newColor) async {
    try {
      if (!ColorPalette.isValidColor(newColor)) {
        _error = 'Invalid color: must be high-contrast';
        notifyListeners();
        return false;
      }

      final success = await _datasetManager.updateItemColor(itemId, newColor);
      if (success) {
        final idx = _items.indexWhere((i) => i.id == itemId);
        if (idx >= 0) {
          _items[idx] = _items[idx].copyWith(colorValue: newColor.value);
          notifyListeners();
        }
        return true;
      }
      return false;
    } catch (e) {
      _error = 'Failed to update color: $e';
      debugPrint('✗ $_error');
      notifyListeners();
      return false;
    }
  }

  /// Update item name (in-place).
  Future<bool> updateItemName(String itemId, String newName) async {
    try {
      final success = await _datasetManager.updateItemName(itemId, newName);
      if (success) {
        final idx = _items.indexWhere((i) => i.id == itemId);
        if (idx >= 0) {
          _items[idx] = _items[idx].copyWith(name: newName);
          notifyListeners();
        }
        return true;
      }
      return false;
    } catch (e) {
      _error = 'Failed to update name: $e';
      debugPrint('✗ $_error');
      return false;
    }
  }

  /// Delete item
  /// 
  /// EMBEDDING CACHE INVALIDATION:
  /// This is the ONLY operation that invalidates cached embeddings.
  /// When an item is deleted, its cached embedding is permanently removed.
  Future<bool> deleteItem(String itemId) async {
    try {
      final success = await _datasetManager.deleteItem(itemId);
      if (success) {
        _items.removeWhere((item) => item.id == itemId);
        await loadStatistics();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _error = 'Failed to delete item: $e';
      debugPrint('✗ $_error');
      notifyListeners();
      return false;
    }
  }

  /// Search items
  Future<List<DatasetItem>> searchItems(String query) async {
    if (query.isEmpty) return _items;
    return await _datasetManager.searchItems(query);
  }

  /// Clear all items
  Future<bool> clearDataset() async {
    try {
      final success = await _datasetManager.clearDataset();
      if (success) {
        _items.clear();
        await loadStatistics();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _error = 'Failed to clear dataset: $e';
      debugPrint('✗ $_error');
      return false;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
