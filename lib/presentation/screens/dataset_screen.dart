import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../core/constants/color_palette.dart';
import '../providers/dataset_provider.dart';
import '../widgets/dataset_item_card.dart';
import '../../data/models/dataset_item.dart';
import 'dataset_group_screen.dart';

/// Dataset management screen
/// Allows users to add, edit, and delete dataset items
class DatasetScreen extends StatefulWidget {
  const DatasetScreen({Key? key}) : super(key: key);

  @override
  State<DatasetScreen> createState() => _DatasetScreenState();
}

class _DatasetScreenState extends State<DatasetScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dataset Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => _showClearDatasetDialog(context),
            tooltip: 'Clear Dataset',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search items...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),

          // Dataset items grid
          Expanded(
            child: Consumer<DatasetProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                        const SizedBox(height: 16),
                        Text(provider.error!),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => provider.loadItems(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final items = _searchQuery.isEmpty
                    ? provider.items
                    : provider.items.where((item) {
                        return item.name.toLowerCase().contains(_searchQuery.toLowerCase());
                      }).toList();

                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty ? 'No items in dataset' : 'No matching items',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isEmpty ? 'Tap + to add your first item' : 'Try a different search',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                // Group items by name
                final groupedItems = <String, List<DatasetItem>>{};
                for (var item in items) {
                  groupedItems.putIfAbsent(item.name, () => []).add(item);
                }
                final groupNames = groupedItems.keys.toList();

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: groupNames.length,
                  itemBuilder: (context, index) {
                    final groupName = groupNames[index];
                    final group = groupedItems[groupName]!;
                    final firstItem = group.first;
                    
                    return DatasetItemCard(
                      item: firstItem,
                      groupCount: group.length,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DatasetGroupScreen(
                              groupName: groupName,
                              items: group,
                            ),
                          ),
                        );
                      },
                      onEdit: () => _showEditDialog(context, firstItem.id),
                      onDelete: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Group?'),
                            content: Text('Delete all ${group.length} images for "$groupName"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('CANCEL'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('DELETE ALL', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          for (var item in group) {
                            await provider.deleteItem(item.id);
                          }
                        }
                      },
                      onColorChange: () => _showGroupColorPicker(context, groupName, Color(firstItem.colorValue)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddItemDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
    );
  }

  void _showAddItemDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _AddItemDialog(),
    );
  }

  void _showEditDialog(BuildContext context, String itemId) {
    final provider = context.read<DatasetProvider>();
    final item = provider.items.firstWhere((i) => i.id == itemId);
    
    final controller = TextEditingController(text: item.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Item Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Item Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await provider.updateItemName(itemId, controller.text.trim());
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, String itemId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await context.read<DatasetProvider>().deleteItem(itemId);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Cascades the chosen colour to every item in the group — one colour per
  /// real-world object, not per individual photo.
  void _showGroupColorPicker(BuildContext context, String groupName, Color initial) {
    final provider = context.read<DatasetProvider>();
    Color selectedColor = initial;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await provider.updateGroupColor(groupName, selectedColor);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Apply to group'),
          ),
        ],
      ),
    );
  }

  void _showClearDatasetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Dataset'),
        content: const Text('Are you sure you want to delete ALL items? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await context.read<DatasetProvider>().clearDataset();
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

/// Dialog for adding new items
class _AddItemDialog extends StatefulWidget {
  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final TextEditingController _nameController = TextEditingController();
  Color _selectedColor = ColorPalette.defaultColors[0];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add new item'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Item name',
                hintText: 'e.g. "Coffee mug"',
                prefixIcon: Icon(Icons.label_outline),
              ),
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            const Text('Group colour', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in ColorPalette.defaultColors)
                  GestureDetector(
                    onTap: () => setState(() => _selectedColor = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedColor.value == c.value
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.tonalIcon(
          onPressed: _nameController.text.trim().isEmpty
              ? null
              : () => _addFromGallery(context),
          icon: const Icon(Icons.photo),
          label: const Text('Gallery'),
        ),
        FilledButton.icon(
          onPressed: _nameController.text.trim().isEmpty
              ? null
              : () => _addFromCamera(context),
          icon: const Icon(Icons.camera_alt),
          label: const Text('Camera'),
        ),
      ],
    );
  }

  Future<void> _addFromCamera(BuildContext context) async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an item name')),
      );
      return;
    }
    await _runAdd(context, fromCamera: true);
  }

  Future<void> _addFromGallery(BuildContext context) async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an item name')),
      );
      return;
    }
    await _runAdd(context, fromCamera: false);
  }

  /// Shared add flow. We MUST capture `ScaffoldMessenger` and a long-lived
  /// context (the root overlay) BEFORE popping the dialog — once popped, the
  /// dialog's own BuildContext is dead and any `*.of(deadContext)` lookup
  /// throws "Null check operator used on a null value".
  Future<void> _runAdd(BuildContext dialogContext,
      {required bool fromCamera}) async {
    final scaffoldMessenger = ScaffoldMessenger.of(dialogContext);
    final overlayContext =
        Navigator.of(dialogContext, rootNavigator: true).overlay!.context;
    final provider = dialogContext.read<DatasetProvider>();
    final name = _nameController.text.trim();
    final color = _selectedColor;

    Navigator.pop(dialogContext);

    final success = fromCamera
        ? await provider.addItemFromCamera(name, color)
        : await provider.addItemFromGallery(name, color);

    if (success) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Item added successfully')),
      );
    } else {
      _showAddError(overlayContext, provider.error ?? 'Unknown error');
    }
  }

  /// Long / multi-line error messages don't fit in a SnackBar — show a
  /// scrollable dialog. `context` must be a still-alive BuildContext (e.g.
  /// the root overlay's), NOT the popped add-dialog context.
  void _showAddError(BuildContext context, String message) {
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Failed to add item'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360, maxWidth: 480),
          child: SingleChildScrollView(
            child: SelectableText(
              message,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
