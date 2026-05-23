import '../models/dataset_item.dart';
import '../storage/hive_storage.dart';

/// Repository for dataset operations
/// Provides a clean interface between domain layer and storage
class DatasetRepository {
  final HiveStorage _storage;

  DatasetRepository({HiveStorage? storage})
      : _storage = storage ?? HiveStorage.instance;

  /// Get all dataset items
  Future<List<DatasetItem>> getAllItems() async {
    return _storage.getAllItems();
  }

  /// Get item by ID
  Future<DatasetItem?> getItemById(String id) async {
    return _storage.getItem(id);
  }

  /// Add new item to dataset
  Future<void> addItem(DatasetItem item) async {
    await _storage.saveItem(item);
  }

  /// Update existing item
  Future<void> updateItem(DatasetItem item) async {
    await _storage.saveItem(item);
  }

  /// Delete item by ID
  Future<void> deleteItem(String id) async {
    await _storage.deleteItem(id);
  }

  /// Clear entire dataset
  Future<void> clearDataset() async {
    await _storage.clearAll();
  }

  /// Get dataset count
  Future<int> getItemCount() async {
    return _storage.getAllItems().length;
  }

  /// Search items by name
  Future<List<DatasetItem>> searchByName(String query) async {
    final allItems = _storage.getAllItems();
    final lowerQuery = query.toLowerCase();
    
    return allItems.where((item) {
      return item.name.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Get items by source (camera/gallery)
  Future<List<DatasetItem>> getItemsBySource(String source) async {
    final allItems = _storage.getAllItems();
    return allItems.where((item) => item.source == source).toList();
  }

  /// Get items with OCR text
  Future<List<DatasetItem>> getItemsWithOcr() async {
    final allItems = _storage.getAllItems();
    return allItems.where((item) => item.ocrText != null).toList();
  }

  /// Get statistics
  Future<Map<String, dynamic>> getStatistics() async {
    return _storage.getStats();
  }

  /// Validate dataset size limit
  Future<bool> canAddItem(int maxSize) async {
    final count = await getItemCount();
    return count < maxSize;
  }
}
