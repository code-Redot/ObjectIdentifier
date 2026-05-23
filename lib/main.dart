import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'data/storage/hive_storage.dart';
import 'domain/services/ml_service.dart';
import 'domain/services/ocr_service.dart';
import 'domain/services/camera_service.dart';
import 'domain/services/recognition_service.dart';
import 'presentation/providers/dataset_provider.dart';
import 'presentation/providers/recognition_provider.dart';
import 'presentation/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Request permissions
  await _requestPermissions();

  // Initialize services
  final mlService = MLService();
  final ocrService = OcrService();
  final cameraService = CameraService();
  final recognitionService = RecognitionService(
    mlService: mlService,
    ocrService: ocrService,
  );

  // Initialize Hive storage
  await HiveStorage.instance.initialize();

  // Initialize ML model
  debugPrint('⏳ Initializing ML model...');
  final mlInitialized = await mlService.initialize();
  
  // CRITICAL FIX: Handle ML model loading failure
  if (!mlInitialized) {
    debugPrint('✗ Failed to initialize ML model');
    debugPrint('✗ Please ensure TFLite models are in assets/models/');
    
    // Show error screen instead of continuing
    runApp(
      MaterialApp(
        title: 'Visual Recognition - Error',
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 24),
                  const Text(
                    'Failed to Load ML Model',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Please ensure the following file exists:\n'
                    '• assets/models/mobilenet_v3_large.tflite',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Download from storage.googleapis.com/mediapipe-models/\n'
                    'image_embedder/mobilenet_v3_large/float32/latest/',
                    style: TextStyle(fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return; // Stop execution
  }
  
  debugPrint('✓ ML model initialized successfully');

  // Initialize OCR
  debugPrint('⏳ Initializing OCR...');
  await ocrService.initialize();

  runApp(
    VisualRecognitionApp(
      mlService: mlService,
      ocrService: ocrService,
      cameraService: cameraService,
      recognitionService: recognitionService,
    ),
  );
}

/// Request necessary permissions
Future<void> _requestPermissions() async {
  final permissions = [
    Permission.camera,
    Permission.photos,
  ];

  for (final permission in permissions) {
    final status = await permission.request();
    if (status.isDenied) {
      debugPrint('⚠ Permission denied: $permission');
    }
  }
}

class VisualRecognitionApp extends StatelessWidget {
  final MLService mlService;
  final OcrService ocrService;
  final CameraService cameraService;
  final RecognitionService recognitionService;

  const VisualRecognitionApp({
    Key? key,
    required this.mlService,
    required this.ocrService,
    required this.cameraService,
    required this.recognitionService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Dataset Provider
        ChangeNotifierProvider(
          create: (_) => DatasetProvider(
            mlService: mlService,
            ocrService: ocrService,
          )..initialize(),
        ),
        
        // Recognition Provider
        ChangeNotifierProvider(
          create: (_) => RecognitionProvider(
            recognitionService: recognitionService,
            cameraService: cameraService,
          ),
        ),
        
        // Provide services for direct access if needed
        Provider.value(value: mlService),
        Provider.value(value: ocrService),
        Provider.value(value: cameraService),
        Provider.value(value: recognitionService),
      ],
      child: MaterialApp(
        title: 'Visual Recognition',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
