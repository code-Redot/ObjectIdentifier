import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  void _showAddDialog(BuildContext context) {
    // Show dialog with Add from Camera and Add from Gallery to append to this group
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Add another image from Camera'),
              onTap: () async {
                Navigator.pop(context);
                final provider = context.read<DatasetProvider>();
                final itemColor = Color(items.first.colorValue);
                await provider.addItemFromCamera(groupName, itemColor);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Add another image from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final provider = context.read<DatasetProvider>();
                final itemColor = Color(items.first.colorValue);
                await provider.addItemFromGallery(groupName, itemColor);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatasetProvider>(
      builder: (context, provider, child) {
        // Find all items matching this group's name exactly
        final currentGroupItems = provider.items.where((item) => item.name == groupName).toList();
        
        return Scaffold(
          appBar: AppBar(
            title: Text(groupName),
          ),
          body: currentGroupItems.isEmpty
              ? const Center(child: Text('Empty group'))
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
                      onEdit: () {}, // Handled manually at group level
                      onDelete: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Image'),
                            content: const Text('Are you sure you want to delete this specific image?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('CANCEL'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('DELETE', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await provider.deleteItem(item.id);
                          if (currentGroupItems.length == 1 && context.mounted) {
                            Navigator.pop(context); // Group is empty, go back
                          }
                        }
                      },
                      onColorChange: () {},
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddDialog(context),
            icon: const Icon(Icons.add_a_photo),
            label: const Text('Add Image'),
          ),
        );
      }
    );
  }
}
