import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/dataset_item.dart';

/// Service for managing local storage using Hive (AES-encrypted at rest).
class HiveStorage {
  static const String _boxName = 'dataset_box';
  static const String _encryptionKeyStorageKey = 'hive_dataset_aes_key_v1';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static HiveStorage? _instance;
  Box<DatasetItem>? _datasetBox;

  HiveStorage._();

  static HiveStorage get instance {
    _instance ??= HiveStorage._();
    return _instance!;
  }

  /// Initialize Hive, register adapters, and open the encrypted dataset box.
  Future<void> initialize() async {
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(DatasetItemAdapter());
    }

    final cipher = HiveAesCipher(await _loadOrCreateEncryptionKey());
    _datasetBox = await Hive.openBox<DatasetItem>(
      _boxName,
      encryptionCipher: cipher,
    );
  }

  /// Loads the AES-256 key from secure storage, generating one on first run.
  static Future<List<int>> _loadOrCreateEncryptionKey() async {
    try {
      final existing = await _secureStorage.read(key: _encryptionKeyStorageKey);
      if (existing != null && existing.isNotEmpty) {
        final decoded = base64Decode(existing);
        if (decoded.length == 32) return decoded;
        // Stale/invalid key — overwrite below.
      }
    } catch (e) {
      debugPrint(
          '⚠ Secure storage read failed, regenerating key: $e');
    }

    final rng = Random.secure();
    final key = List<int>.generate(32, (_) => rng.nextInt(256));
    try {
      await _secureStorage.write(
        key: _encryptionKeyStorageKey,
        value: base64Encode(key),
      );
    } catch (e) {
      debugPrint(
          '⚠ Secure storage write failed; key will not persist: $e');
    }
    return key;
  }

  /// Get the dataset box
  Box<DatasetItem> get datasetBox {
    if (_datasetBox == null || !_datasetBox!.isOpen) {
      throw StateError('HiveStorage not initialized. Call initialize() first.');
    }
    return _datasetBox!;
  }

  /// Get all dataset items
  List<DatasetItem> getAllItems() {
    return datasetBox.values.toList();
  }

  /// Get item by ID
  DatasetItem? getItem(String id) {
    return datasetBox.get(id);
  }

  /// Add or update an item
  Future<void> saveItem(DatasetItem item) async {
    await datasetBox.put(item.id, item);
  }

  /// Delete an item and its associated image file
  Future<void> deleteItem(String id) async {
    final item = getItem(id);
    if (item != null) {
      // Delete the image file
      final file = File(item.imagePath);
      if (await file.exists()) {
        await file.delete();
      }
      
      // Delete from Hive
      await datasetBox.delete(id);
    }
  }

  /// Delete all items and their images
  Future<void> clearAll() async {
    // Delete all image files
    for (final item in getAllItems()) {
      final file = File(item.imagePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    
    // Clear the box
    await datasetBox.clear();
  }

  /// Get dataset statistics
  Map<String, dynamic> getStats() {
    final items = getAllItems();
    return {
      'totalItems': items.length,
      'cameraItems': items.where((i) => i.source == 'camera').length,
      'galleryItems': items.where((i) => i.source == 'gallery').length,
      'itemsWithOcr': items.where((i) => i.ocrText != null).length,
    };
  }

  /// Get the directory for storing dataset images
  Future<Directory> getImagesDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${appDir.path}/dataset_images');
    
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    
    return imagesDir;
  }

  /// Close Hive (call on app shutdown)
  Future<void> close() async {
    await _datasetBox?.close();
    await Hive.close();
  }
}
