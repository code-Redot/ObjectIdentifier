import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:io';

void main() {
  test('Inspect TFLite Models', () async {
    try {
      final interpreter = await Interpreter.fromFile(File('assets/models/efficientnet_lite2.tflite'));
      print('EfficientNet-Lite2 Input Tensors:');
      for (var tensor in interpreter.getInputTensors()) {
        print('Name: ${tensor.name}, Shape: ${tensor.shape}, Type: ${tensor.type}');
      }
      print('\nEfficientNet-Lite2 Output Tensors:');
      for (var tensor in interpreter.getOutputTensors()) {
        print('Name: ${tensor.name}, Shape: ${tensor.shape}, Type: ${tensor.type}');
      }
    } catch (e) {
      print('efficientnet_lite2: $e');
    }

    try {
      final interpreter = await Interpreter.fromFile(File('assets/models/mobilenet_v2.tflite'));
      print('\nMobileNet_V2 Input Tensors:');
      for (var tensor in interpreter.getInputTensors()) {
        print('Name: ${tensor.name}, Shape: ${tensor.shape}, Type: ${tensor.type}');
      }
      print('\nMobileNet_V2 Output Tensors:');
      for (var tensor in interpreter.getOutputTensors()) {
        print('Name: ${tensor.name}, Shape: ${tensor.shape}, Type: ${tensor.type}');
      }
    } catch (e) {
      print('mobilenet_v2: $e');
    }
  });
}
