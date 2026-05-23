# Object Identifier

Offline visual recognition app for Android. Build a personal dataset of objects, then identify them live through the camera with on-device ML — no network, no accounts, no cloud upload.

- **Multi-detection**: clusters the camera frame into multiple disjoint ROIs per frame, each matched independently against your dataset.
- **On-device embedding**: MediaPipe MobileNetV3-Large image embedder, GPU-accelerated when available.
- **Encrypted local storage**: dataset (images + embeddings + OCR text) is AES-encrypted at rest with a key kept in the platform keystore.
- **OCR boost**: ML Kit Latin OCR is used as a secondary signal when image similarity is near the threshold.

## Requirements

- Flutter 3.41+ (Dart 3.11+).
- Android device with `minSdk = 26` (Android 8.0) and `targetSdk = 36`.
- ARM64 device recommended — GPU delegate uses OpenCL/OpenGL via the Adreno/Mali GPU.

## Setup

```bash
flutter pub get
flutter build apk --release                  # universal, ~110 MB
# or smaller, per-architecture APKs:
flutter build apk --split-per-abi --release  # ~40 MB each
```

### The TFLite model

The repo does **not** include the model file (it's a Google-hosted asset). Download once:

```
https://storage.googleapis.com/mediapipe-models/image_embedder/mobilenet_v3_large/float32/latest/mobilenet_v3_large.tflite
```

Save as [`assets/models/mobilenet_v3_large.tflite`](assets/models/mobilenet_v3_large.tflite).

If you swap to a different embedder, update three constants in [`lib/core/constants/app_constants.dart`](lib/core/constants/app_constants.dart) to match it:

```dart
static const String primaryModelPath = '...';
static const int modelInputWidth  = 224;   // model's expected H/W
static const int modelInputHeight = 224;
static const int embeddingDimension = 1280; // model's output feature dim
```

`MLService.initialize` prints the actual tensor shapes on startup to help you verify.

### Signing a release build

1. Generate a keystore:

   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 \
       -validity 10000 -alias upload
   ```

2. Create [`android/key.properties`](android/key.properties) (gitignored):

   ```
   storeFile=../../upload-keystore.jks   # relative to android/app
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```

3. Build — Gradle picks up the key automatically:

   ```bash
   flutter build apk --release
   ```

   Without `key.properties`, the build falls back to the debug key (works for `flutter run`, not for Play Store).

## Architecture

```
lib/
├── main.dart                              # bootstrap + permissions + error screen
├── core/
│   ├── constants/app_constants.dart       # model paths, thresholds, FPS
│   ├── constants/color_palette.dart       # high-contrast colours, validation
│   └── utils/image_utils.dart             # YUV→multi-ROI pipeline (runs in isolate)
├── data/
│   ├── models/dataset_item.dart           # @HiveType
│   ├── models/recognition_result.dart     # results + aggregation
│   ├── repositories/dataset_repository.dart
│   └── storage/hive_storage.dart          # AES-encrypted Hive box
├── domain/services/
│   ├── ml_service.dart                    # TFLite, GPU delegate, embeddings
│   ├── ocr_service.dart                   # ML Kit text recognition
│   ├── camera_service.dart                # frame stream + throttling
│   ├── recognition_service.dart           # per-frame match + temporal aggregation
│   └── dataset_manager.dart               # add/edit/delete items
└── presentation/
    ├── providers/{dataset,recognition}_provider.dart
    ├── screens/{home,dataset,dataset_group,recognition}_screen.dart
    └── widgets/{bounding_box_painter,dataset_item_card}.dart
```

### Recognition pipeline (per frame)

1. **CameraService** streams YUV frames; every Nth frame (`frameSkipRatio`) is forwarded.
2. **`processCameraFrameFullPipeline`** runs in a worker isolate:
   - Coarse edge-density grid on the luma plane.
   - Connected components → up to 5 disjoint ROIs.
   - Per-ROI reverse projection straight into a `Float32List` of model-input shape, normalized to `[0,1]`.
3. **MLService** writes the buffer into the TFLite input tensor (no nested-list reshape), invokes the model, copies the output, and L2-normalizes the embedding.
4. **RecognitionService** computes cosine similarity against cached dataset embeddings and aggregates over `resultAggregationFrames` for jitter reduction.
5. **BoundingBoxPainter** draws normalized 0..1 ROI rects directly on a `CustomPaint` that shares the camera-preview coordinate system.

### Storage

`Hive.openBox` is opened with `HiveAesCipher` using a 256-bit key. On first launch the key is generated with `Random.secure()` and persisted via [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) (Android EncryptedSharedPreferences / iOS Keychain). User images are stored as files in the app-private documents directory and are not encrypted on disk; if you handle sensitive material consider encrypting them as well.

## Permissions

Declared in [AndroidManifest.xml](android/app/src/main/AndroidManifest.xml):

- `CAMERA` — live recognition.
- `READ_MEDIA_IMAGES` (Android 13+) / `READ_EXTERNAL_STORAGE` (≤32) — gallery imports.

`android:allowBackup="false"` is set so encrypted Hive boxes and the OS-managed key never flow into Android Auto Backup.

## Known limitations

- The image-embedder model is classification-style; for cluster/categorical tasks you may want to fine-tune or swap to a domain-specific extractor.
- Bounding boxes assume portrait-locked orientation (the app pins that in `main.dart`).
- The bundled Flutter SDK copy in `/flutter/` is gitignored — clone the upstream Flutter SDK locally instead.

## License

[MIT](LICENSE) — replace the copyright holder ("Object Identifier Contributors") with your name before publishing.
