import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/dataset_provider.dart';
import '../screens/dataset_screen.dart';
import '../screens/recognition_screen.dart';

/// Main home screen with navigation to dataset management and recognition
class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual Recognition'),
        elevation: 0,
      ),
      body: Consumer<DatasetProvider>(
        builder: (context, datasetProvider, child) {
          final stats = datasetProvider.statistics;
          
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Statistics Card
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Dataset Statistics',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildStatRow(
                          'Total Items',
                          '${stats['totalItems'] ?? 0}',
                          Icons.photo_library,
                        ),
                        const SizedBox(height: 8),
                        _buildStatRow(
                          'Camera Captures',
                          '${stats['cameraItems'] ?? 0}',
                          Icons.camera_alt,
                        ),
                        const SizedBox(height: 8),
                        _buildStatRow(
                          'Gallery Imports',
                          '${stats['galleryItems'] ?? 0}',
                          Icons.photo,
                        ),
                        const SizedBox(height: 8),
                        _buildStatRow(
                          'Items with OCR',
                          '${stats['itemsWithOcr'] ?? 0}',
                          Icons.text_fields,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Navigation Buttons
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildNavigationButton(
                        context,
                        title: 'Manage Dataset',
                        subtitle: 'Add, edit, and organize items',
                        icon: Icons.folder_open,
                        color: Colors.blue,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DatasetScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildNavigationButton(
                        context,
                        title: 'Start Recognition',
                        subtitle: 'Live camera recognition mode',
                        icon: Icons.camera,
                        color: Colors.green,
                        onTap: () {
                          if ((stats['totalItems'] ?? 0) == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please add items to dataset first'),
                              ),
                            );
                            return;
                          }
                          
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RecognitionScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[700],
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButton(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
