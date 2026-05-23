import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../../domain/services/recognition_service.dart';
import '../providers/dataset_provider.dart';
import '../providers/recognition_provider.dart';
import '../widgets/bounding_box_painter.dart';

/// Live camera recognition screen
/// Displays camera preview with real-time object detection overlays
class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({Key? key}) : super(key: key);

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen>
    with WidgetsBindingObserver {
  bool _isInitialized = false;
  bool _showStats = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final recognitionProvider = context.read<RecognitionProvider>();
    final cameraService = recognitionProvider.cameraService;

    if (!cameraService.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      cameraService.pause();
    } else if (state == AppLifecycleState.resumed) {
      cameraService.resume();
      if (recognitionProvider.isRecognizing) {
        _startRecognition();
      }
    }
  }

  Future<void> _initializeCamera() async {
    final recognitionProvider = context.read<RecognitionProvider>();
    final cameraService = recognitionProvider.cameraService;

    final success = await cameraService.initialize();
    if (success) {
      setState(() => _isInitialized = true);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to initialize camera')),
        );
      }
    }
  }

  Future<void> _disposeCamera() async {
    final recognitionProvider = context.read<RecognitionProvider>();
    await _stopRecognition();
    await recognitionProvider.cameraService.dispose();
  }

  Future<void> _startRecognition() async {
    final recognitionProvider = context.read<RecognitionProvider>();
    final datasetProvider = context.read<DatasetProvider>();
    final cameraService = recognitionProvider.cameraService;
    final recognitionService = context.read<RecognitionService>();

    if (datasetProvider.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items in dataset')),
      );
      return;
    }

    recognitionProvider.startRecognition();

    // CRITICAL FIX: Memory leak prevention
    // Check mounted BEFORE async operations to prevent accessing disposed providers
    cameraService.startFrameStream((cameraImage) async {
      // ENFORCEMENT: Check mounted state immediately
      if (!mounted) return; // Widget disposed, stop processing
      
      recognitionProvider.incrementTotalFrames();

      // MANDATORY: 5 FPS enforcement with frame dropping
      // RecognitionService has hard lock - will drop frame if still processing
      final results = await recognitionService.processFrame(
        cameraImage: cameraImage,
        dataset: datasetProvider.items,
      );

      // CRITICAL FIX: Check mounted again after async operation
      if (mounted) {
        recognitionProvider.updateResults(results);
      }
    });
  }

  Future<void> _stopRecognition() async {
    final recognitionProvider = context.read<RecognitionProvider>();
    final cameraService = recognitionProvider.cameraService;

    recognitionProvider.stopRecognition();
    await cameraService.stopFrameStream();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : _buildCameraView(),
    );
  }

  Widget _buildCameraView() {
    return Consumer<RecognitionProvider>(
      builder: (context, recognitionProvider, child) {
        final cameraService = recognitionProvider.cameraService;
        final controller = cameraService.controller;

        if (controller == null || !controller.value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        // Preview is locked to portrait orientation. The camera produces a
        // landscape frame, so the portrait aspect ratio is the inverse.
        final previewAspect = 1 / controller.value.aspectRatio;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview + overlay share a single coordinate system.
            // Letterboxed if the screen aspect differs from the preview's,
            // so normalized 0..1 ROIs map 1:1 to displayed pixels.
            Center(
              child: AspectRatio(
                aspectRatio: previewAspect,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(controller),
                    if (recognitionProvider.isRecognizing &&
                        recognitionProvider.currentResults.isNotEmpty)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: BoundingBoxPainter(
                            results: recognitionProvider.currentResults,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Top controls
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopControls(recognitionProvider),
            ),

            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomControls(recognitionProvider),
            ),

            // Stats overlay (optional)
            if (_showStats)
              Positioned(
                top: 100,
                right: 16,
                child: _buildStatsOverlay(recognitionProvider),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTopControls(RecognitionProvider recognitionProvider) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.only(top: 40, left: 16, right: 16, bottom: 20),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              _showStats ? Icons.analytics : Icons.analytics_outlined,
              color: Colors.white,
            ),
            onPressed: () => setState(() => _showStats = !_showStats),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(RecognitionProvider recognitionProvider) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.only(bottom: 40, left: 16, right: 16, top: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Match count indicator
          if (recognitionProvider.currentResults.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${recognitionProvider.currentResults.length} match(es) found',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Recognition toggle button
          Center(
            child: GestureDetector(
              onTap: () {
                if (recognitionProvider.isRecognizing) {
                  _stopRecognition();
                } else {
                  _startRecognition();
                }
              },
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: recognitionProvider.isRecognizing
                      ? Colors.red
                      : Colors.green,
                  boxShadow: [
                    BoxShadow(
                      color: (recognitionProvider.isRecognizing
                              ? Colors.red
                              : Colors.green)
                          .withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  recognitionProvider.isRecognizing
                      ? Icons.stop
                      : Icons.play_arrow,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsOverlay(RecognitionProvider recognitionProvider) {
    final stats = recognitionProvider.getStats();
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Statistics',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          _buildStatRow('Processed', '${stats['framesProcessed']}'),
          _buildStatRow('Total', '${stats['totalFrames']}'),
          _buildStatRow('Rate', '${stats['processingRate']}%'),
          _buildStatRow('Matches', '${stats['currentMatches']}'),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
