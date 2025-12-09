import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

class ScreenshotDetector {
  OrtSession? _session;
  bool _isReady = false;
  bool get isReady => _isReady;

 Future<void> loadModel() async {
    if (_isReady) return;

    try {
      OrtEnv.instance.init();

      final supportDir = await getApplicationSupportDirectory();
      // Ensure this filename matches what is in your pubspec.yaml assets!
      final modelPath = '${supportDir.path}/model.onnx'; 
      final modelFile = File(modelPath);

      // --- FIX: ALWAYS OVERWRITE ---
      // We removed "if (!await modelFile.exists())" so it updates every time.
      debugPrint('Copying model from assets to: $modelPath');
      final raw = await rootBundle.load('assets/model/model.onnx');
      await modelFile.writeAsBytes(
        raw.buffer.asUint8List(),
        flush: true,
      );
      // -----------------------------

      final sessionOptions = OrtSessionOptions();
      _session = OrtSession.fromFile(modelFile, sessionOptions);
      _isReady = true;
      debugPrint('ONNX screenshot model loaded ✅');
    } catch (e, st) {
      debugPrint('Error loading ONNX model: $e');
      debugPrint(st.toString());
      _isReady = false;
    }
  }
 Float32List _preprocessImage(img.Image image) {
    const targetWidth = 224;
    const targetHeight = 224;

    // 1. Resize (Ideally keep aspect ratio, but simple resize is often 'okay' for simple CNNs)
    final resized = img.copyResize(
      image,
      width: targetWidth,
      height: targetHeight,
    );

    // 2. Prepare NCHW buffer (1 * 3 * 224 * 224)
    final input = Float32List(1 * 3 * targetHeight * targetWidth);

    // ImageNet Normalization Constants
    const mean = [0.485, 0.456, 0.406];
    const std = [0.229, 0.224, 0.225];

    // Calculate offsets for Red, Green, and Blue planes
    // We fill RRR... then GGG... then BBB...
    final planeSize = targetWidth * targetHeight;
    int rOffset = 0;
    int gOffset = planeSize;
    int bOffset = planeSize * 2;

    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        final pixel = resized.getPixelSafe(x, y);

        // Normalize: (Pixel/255 - mean) / std
        final rNormalized = ((pixel.r / 255.0) - mean[0]) / std[0];
        final gNormalized = ((pixel.g / 255.0) - mean[1]) / std[1];
        final bNormalized = ((pixel.b / 255.0) - mean[2]) / std[2];

        // Store in NCHW planar format
        input[rOffset++] = rNormalized;
        input[gOffset++] = gNormalized;
        input[bOffset++] = bNormalized;
      }
    }

    return input;
  }
 Future<double> classifyImage(File file) async {
    if (!isReady || _session == null) {
      throw StateError('Model not loaded');
    }

    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception("Failed to decode image");
    }

    // Preprocess (Resize + Normalize + NCHW Reorder)
    final inputData = _preprocessImage(image);

    // Create Tensor [1, 3, 224, 224]
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      inputData,
      [1, 3, 224, 224],
    );

    final runOptions = OrtRunOptions();
    final outputs = await _session!.runAsync(
      runOptions,
      {
        "input": inputTensor,
      },
    );

    inputTensor.release();
    runOptions.release();

    // 3. Handle Output
    // Output is usually [Batch, Classes] -> [1, 2]
    final rawOutput = outputs?[0]!.value as List; // This is a List<List<double>> or similar
    outputs?[0]!.release();
    
    // Depending on the ONNX library version, this might be a flat list or nested.
    // Usually it comes out as [ [logit0, logit1] ].
    final logits = (rawOutput[0] as List).map((e) => (e as num).toDouble()).toList();

    // 4. Apply Softmax to get probabilities (0.0 - 1.0)
    final probabilities = _softmax(logits);
    
    // Assume class 1 is "Screenshot" (based on your folder structure in training)
    // 0_Keep, 1_Delete
    return probabilities[1]; 
  }
 List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((x) => math.exp(x - maxLogit)).toList();
    final sum = exps.fold<double>(0.0, (a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }
  }