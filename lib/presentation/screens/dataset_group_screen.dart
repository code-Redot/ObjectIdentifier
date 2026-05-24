import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/color_palette.dart';
import '../../data/models/dataset_item.dart';
import '../providers/dataset_provider.dart';
import '../widgets/dataset_item_card.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class DatasetGroupScreen extends StatelessWidget {
  final String groupName;
  final List<DatasetItem> items;

  const DatasetGroupScreen({
    Key? key,
    required this.groupName,
    required this.items,
  }) : super(key: key);

  Future<void> _addFromSource(
    BuildContext context, {
    required bool fromCamera,
    required Color groupColor,
  }) async {
    final provider = context.read<DatasetProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final ok = fromCamera
        ? await provider.addItemFromCamera(groupName, groupColor)
        : await provider.addItemFromGallery(groupName, groupColor);
    if (!ok && provider.error != null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(provider.error!, maxLines: 4),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  void _showAddDialog(BuildContext context, Color groupColor) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Add another image from Camera'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addFromSource(context, fromCamera: true, groupColor: groupColor);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Add another image from Gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addFromSource(context, fromCamera: false, groupColor: groupColor);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupColorPicker(BuildContext context, Color initial) {
    final provider = context.read<DatasetProvider>();
    Color selectedColor = initial;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Colour for "$groupName"'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: selectedColor,
            availableColors: ColorPalette.defaultColors,
            onColorChanged: (color) => selectedColor = color,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await provider.updateGroupColor(groupName, selectedColor);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Apply to group'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatasetProvider>(
      builder: (context, provider, child) {
        final currentGroupItems =
            provider.items.where((item) => item.name == groupName).toList();

        final groupColor = currentGroupItems.isNotEmpty
            ? Color(currentGroupItems.first.colorValue)
            : Color(items.first.colorValue);

        return Scaffold(
          appBar: AppBar(
            title: Text(groupName),
            actions: [
              IconButton(
                tooltip: 'Change group colour',
                icon: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: groupColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                onPressed: () => _showGroupColorPicker(context, groupColor),
              ),
            ],
          ),
          body: currentGroupItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('No images yet for "$groupName"',
                          style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 4),
                      const Text('Tap "Add Image" to attach one',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: currentGroupItems.length,
                  itemBuilder: (context, index) {
                    final item = currentGroupItems[index];
                    return DatasetItemCard(
                      item: item,
                      onEdit: () {},
                      onDelete: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Image'),
                            content: const Text('Delete this specific image?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('CANCEL'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('DELETE',
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await provider.deleteItem(item.id);
                          if (currentGroupItems.length == 1 && context.mounted) {
                            Navigator.pop(context);
                          }
                        }
                      },
                      // Colour edits at the group level only — per-image color
                      // would break the "one colour per object" invariant.
                      onColorChange: () =>
                          _showGroupColorPicker(context, groupColor),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: groupColor,
            foregroundColor: ColorPalette.getContrastingTextColor(groupColor),
            onPressed: () => _showAddDialog(context, groupColor),
            icon: const Icon(Icons.add_a_photo),
            label: const Text('Add Image'),
          ),
        );
      },
    );
  }
}
