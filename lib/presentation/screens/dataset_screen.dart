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
                      onColorChange: () => _showColorPicker(context, firstItem.id),
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

  void _showColorPicker(BuildContext context, String itemId) {
    final provider = context.read<DatasetProvider>();
    final item = provider.items.firstWhere((i) => i.id == itemId);
    Color selectedColor = Color(item.colorValue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Color'),
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
              await provider.updateItemColor(itemId, selectedColor);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
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
      title: const Text('Add New Item'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Item Name',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Color: '),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showColorPicker(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _selectedColor,
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () => _addFromCamera(context),
          icon: const Icon(Icons.camera_alt),
          label: const Text('Camera'),
        ),
        ElevatedButton.icon(
          onPressed: () => _addFromGallery(context),
          icon: const Icon(Icons.photo),
          label: const Text('Gallery'),
        ),
      ],
    );
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: _selectedColor,
            availableColors: ColorPalette.defaultColors,
            onColorChanged: (color) {
              setState(() => _selectedColor = color);
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _addFromCamera(BuildContext context) async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an item name')),
      );
      return;
    }

    final currentContext = context;
    final scaffoldMessenger = ScaffoldMessenger.of(currentContext);
    final provider = currentContext.read<DatasetProvider>();
    final name = _nameController.text.trim();
    final color = _selectedColor;

    Navigator.pop(currentContext);
    
    final success = await provider.addItemFromCamera(name, color);

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(success ? 'Item added successfully' : provider.error ?? 'Failed to add item'),
      ),
    );
  }

  Future<void> _addFromGallery(BuildContext context) async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an item name')),
      );
      return;
    }

    final currentContext = context;
    final scaffoldMessenger = ScaffoldMessenger.of(currentContext);
    final provider = currentContext.read<DatasetProvider>();
    final name = _nameController.text.trim();
    final color = _selectedColor;

    Navigator.pop(currentContext);
    
    final success = await provider.addItemFromGallery(name, color);

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(success ? 'Item added successfully' : provider.error ?? 'Failed to add item'),
      ),
    );
  }
}
