import 'package:hive/hive.dart';

part 'dataset_item.g.dart';

/// Represents a single item in the recognition dataset
/// Each item contains an image, its embedding vector, and metadata
@HiveType(typeId: 0)
class DatasetItem {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String imagePath; // Local file path

  @HiveField(3)
  final List<double> embedding; // Feature vector from ML model

  @HiveField(4)
  final int colorValue; // RGB color as int (Color.value)

  @HiveField(5)
  final DateTime createdAt;

  @HiveField(6)
  final String source; // 'camera' or 'gallery'

  @HiveField(7)
  final String? ocrText; // Extracted text if OCR was successful

  DatasetItem({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.embedding,
    required this.colorValue,
    required this.createdAt,
    required this.source,
    this.ocrText,
  });

  /// Create a copy with updated fields
  DatasetItem copyWith({
    String? name,
    int? colorValue,
    String? ocrText,
  }) {
    return DatasetItem(
      id: id,
      name: name ?? this.name,
      imagePath: imagePath,
      embedding: embedding,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt,
      source: source,
      ocrText: ocrText ?? this.ocrText,
    );
  }

  /// Validate embedding dimension
  bool hasValidEmbedding(int expectedDimension) {
    return embedding.length == expectedDimension;
  }

  @override
  String toString() {
    return 'DatasetItem(id: $id, name: $name, source: $source, hasOcr: ${ocrText != null})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DatasetItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
