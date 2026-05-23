import 'package:flutter/material.dart';

/// High-contrast color palette for dataset items
/// Prevents near-white, near-black, or low-contrast colors
class ColorPalette {
  static const List<Color> defaultColors = [
    Color(0xFFE53935), // Vibrant Red
    Color(0xFF1E88E5), // Vibrant Blue
    Color(0xFF43A047), // Vibrant Green
    Color(0xFFFB8C00), // Vibrant Orange
    Color(0xFF8E24AA), // Vibrant Purple
    Color(0xFF00ACC1), // Vibrant Cyan
    Color(0xFFFFB300), // Vibrant Amber
    Color(0xFFD81B60), // Vibrant Pink
    Color(0xFF00897B), // Vibrant Teal
    Color(0xFF6D4C41), // Brown
    Color(0xFF5E35B1), // Deep Purple
    Color(0xFFC62828), // Dark Red
    Color(0xFF2E7D32), // Dark Green
    Color(0xFFEF6C00), // Deep Orange
    Color(0xFF1565C0), // Dark Blue
    Color(0xFF6A1B9A), // Dark Purple
  ];

  /// Get color by index (cycles through palette)
  static Color getColorByIndex(int index) {
    return defaultColors[index % defaultColors.length];
  }

  /// Get next available color based on existing dataset
  static Color getNextColor(List<int> usedColorValues) {
    for (final color in defaultColors) {
      if (!usedColorValues.contains(color.value)) {
        return color;
      }
    }
    // If all colors used, return random from palette
    return defaultColors[usedColorValues.length % defaultColors.length];
  }

  /// Validate color contrast (ensure it's not too dark or too light)
  static bool isValidColor(Color color) {
    final luminance = color.computeLuminance();
    // Reject colors that are too dark (< 0.1) or too light (> 0.9)
    return luminance > 0.1 && luminance < 0.9;
  }

  /// Get contrasting text color for background
  static Color getContrastingTextColor(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  /// Generate color swatch for picker
  static List<Color> getColorPickerPalette() {
    return defaultColors;
  }
}
