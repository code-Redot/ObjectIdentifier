import 'dart:async';
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

void main() {
  // Surface any uncaught error as a visible screen instead of an opaque crash.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _crash('Flutter framework error', details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _crash('Platform error', error, stack);
      return true;
    };

    await _bootstrap();
  }, (error, stack) {
    _crash('Uncaught zone error', error, stack);
  });
}

Future<void> _bootstrap() async {
  String stage = 'orientation lock';
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    stage = 'permissions';
    await _requestPermissions();

    stage = 'service construction';
    final mlService = MLService();
    final ocrService = OcrService();
    final cameraService = CameraService();
    final recognitionService = RecognitionService(
      mlService: mlService,
      ocrService: ocrService,
    );

    stage = 'Hive storage init';
    debugPrint('⏳ Initializing Hive storage...');
    await HiveStorage.instance.initialize();
    debugPrint('✓ Hive storage initialized');

    stage = 'ML model init';
    debugPrint('⏳ Initializing ML model...');
    final mlInitialized = await mlService.initialize();
    if (!mlInitialized) {
      _showModelMissingScreen();
      return;
    }
    debugPrint('✓ ML model initialized');

    stage = 'OCR init';
    debugPrint('⏳ Initializing OCR...');
    await ocrService.initialize();

    stage = 'runApp';
    runApp(VisualRecognitionApp(
      mlService: mlService,
      ocrService: ocrService,
      cameraService: cameraService,
      recognitionService: recognitionService,
    ));
  } catch (e, stack) {
    _crash('Startup failed at: $stage', e, stack);
  }
}

void _crash(String label, Object error, StackTrace? stack) {
  // Log to logcat AND show on-screen so we never lose the cause.
  debugPrint('✗ $label: $error');
  if (stack != null) debugPrintStack(stackTrace: stack);
  runApp(_StartupErrorApp(label: label, error: error, stack: stack));
}

void _showModelMissingScreen() {
  runApp(
    MaterialApp(
      title: 'Visual Recognition - Error',
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.error_outline, size: 64, color: Colors.red),
                SizedBox(height: 24),
                Text(
                  'Failed to Load ML Model',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Text(
                  'Please ensure the following file exists:\n'
                  '• assets/models/mobilenet_v3_large.tflite',
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24),
                Text(
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
}

/// Request runtime permissions. Failures (denied, restricted, etc.) are
/// logged but never thrown — the app can run with fewer features.
Future<void> _requestPermissions() async {
  final permissions = <Permission>[Permission.camera, Permission.photos];
  for (final p in permissions) {
    try {
      final status = await p.request();
      if (!status.isGranted) {
        debugPrint('⚠ Permission not granted: $p ($status)');
      }
    } catch (e) {
      debugPrint('⚠ Permission request failed for $p: $e');
    }
  }
}

/// Fallback UI shown when bootstrap throws — displays the error so we can
/// diagnose without a USB cable.
class _StartupErrorApp extends StatelessWidget {
  final String label;
  final Object error;
  final StackTrace? stack;
  const _StartupErrorApp({
    required this.label,
    required this.error,
    required this.stack,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visual Recognition - Startup Error',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.red.shade700,
          foregroundColor: Colors.white,
          title: const Text('Startup error'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SelectableText(
                  error.toString(),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13),
                ),
                if (stack != null) ...[
                  const SizedBox(height: 16),
                  const Text('Stack trace:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SelectableText(
                    stack.toString(),
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1E88E5),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFF6F7FB)
        : null,
    cardTheme: CardThemeData(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
  );
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
        ChangeNotifierProvider(
          create: (_) => DatasetProvider(
            mlService: mlService,
            ocrService: ocrService,
          )..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => RecognitionProvider(
            recognitionService: recognitionService,
            cameraService: cameraService,
          ),
        ),
        Provider.value(value: mlService),
        Provider.value(value: ocrService),
        Provider.value(value: cameraService),
        Provider.value(value: recognitionService),
      ],
      child: MaterialApp(
        title: 'Object Identifier',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: const HomeScreen(),
      ),
    );
  }
}
