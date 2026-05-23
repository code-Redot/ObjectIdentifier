import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/models/dataset_item.dart';
import '../../core/constants/color_palette.dart';

/// Card widget for displaying a dataset item
class DatasetItemCard extends StatelessWidget {
  final DatasetItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onColorChange;
  final int groupCount;
  final VoidCallback? onTap;

  const DatasetItemCard({
    Key? key,
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onColorChange,
    this.groupCount = 1,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final itemColor = Color(item.colorValue);
    
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image thumbnail
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(item.imagePath),
                  fit: BoxFit.cover,
                  cacheWidth: 400,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image, size: 48),
                    );
                  },
                ),
                // Color indicator overlay
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onColorChange,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: itemColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Batch indicator overlay
                if (groupCount > 1)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_library, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            '$groupCount',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Item info
          Container(
            padding: const EdgeInsets.all(12),
            color: itemColor.withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      item.source == 'camera' ? Icons.camera_alt : Icons.photo,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.source,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (item.ocrText != null) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.text_fields,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onEdit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: const Icon(Icons.edit, size: 20),
                  ),
                ),
              ),
              Container(width: 1, height: 20, color: Colors.grey[300]),
              Expanded(
                child: InkWell(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: const Icon(Icons.delete, size: 20, color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
}
