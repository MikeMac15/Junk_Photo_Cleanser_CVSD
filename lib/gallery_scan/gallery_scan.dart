import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:cvsd/detector/screenshot_detector.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GalleryScanner extends ChangeNotifier {
  final ScreenshotDetector detector = ScreenshotDetector();

  // --- PERSISTENT DATA ---
  int scannedIndexOffset = 0; 
  Set<String> noTouchFileNames = {}; 

  // --- RUNTIME DATA ---
  List<AssetEntity> allAssets = [];
  List<AssetEntity> flaggedAssets = [];
  double confidenceLevel = 0.80;

  // --- STATE FLAGS ---
  bool loading = false;
  bool isPaused = false;
  String statusMsg = "";

  Function()? onPermissionDenied;

  GalleryScanner(int? prevCount, List<String>? safeList) {
    scannedIndexOffset = prevCount ?? 0;
    noTouchFileNames = safeList != null ? Set<String>.from(safeList) : {};
    _initModelAndLoadPhotos();
  }

  Future<void> _initModelAndLoadPhotos() async {
    await detector.loadModel();
    notifyListeners();
  }

  void setConfidence(double value) {
    confidenceLevel = value;
    notifyListeners();
  }

  void togglePause() {
    isPaused = !isPaused;
    statusMsg = isPaused ? "Paused Scanning" : "Resuming...";
    notifyListeners();
  }

  void stopScan() {
    loading = false;
    isPaused = false;
    statusMsg = "Scan Stopped";
    notifyListeners();
  }

  Future<void> resetScanProgress() async {
    scannedIndexOffset = 0;
    flaggedAssets.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('prevScanCount', 0);
    statusMsg = "Scan progress reset.";
    notifyListeners();
  }

  Future<void> scanGallery() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) {
      if (onPermissionDenied != null) onPermissionDenied!();
      return;
    }

    loading = true;
    isPaused = false;
    statusMsg = "Resuming from $scannedIndexOffset...";
    flaggedAssets.clear();
    notifyListeners();

    List<AssetPathEntity> paths = [];
    try {
      paths = await PhotoManager.getAssetPathList(type: RequestType.image);
    } catch (e) {
      debugPrint("Error paths: $e");
    }

    if (paths.isEmpty) {
      loading = false;
      statusMsg = "No Albums Found";
      notifyListeners();
      return;
    }

    final List<AssetEntity> assets = await paths[0].getAssetListPaged(page: 0, size: 5000);
    
    if (assets.isEmpty) {
      loading = false;
      statusMsg = "No Images Found";
      notifyListeners();
      return;
    }

    allAssets = assets;
    if (!detector.isReady) await detector.loadModel();
    
    final prefs = await SharedPreferences.getInstance();

    for (int i = 0; i < assets.length; i++) {
      final asset = assets[i];

      if (i < scannedIndexOffset) continue; 
      if (noTouchFileNames.contains(asset.id)) {
        scannedIndexOffset = i + 1; 
        continue;
      }

      if (!loading) break; 
      while (isPaused && loading) {
        await Future.delayed(const Duration(milliseconds: 300));
      }

      try {
        final File? file = await asset.file;
        if (file != null) {
          final score = await detector.classifyImage(file);
          if (score > confidenceLevel) {
            flaggedAssets.add(asset);
            notifyListeners(); 
          }
        }
      } catch (e) {
        debugPrint("Error: $e");
      }

      scannedIndexOffset = i + 1;

      if (i % 10 == 0) {
        prefs.setInt('prevScanCount', scannedIndexOffset);
        statusMsg = "Scanning ($i / ${assets.length})...";
        notifyListeners();
      }
      
    }

    if (scannedIndexOffset >= assets.length) scannedIndexOffset = 0;
    await prefs.setInt('prevScanCount', scannedIndexOffset);
    loading = false;
    isPaused = false;
    statusMsg = "Done. Found ${flaggedAssets.length} screenshots.";
    notifyListeners();
  }

  // --- BATCH OPERATIONS ---

  // 1. Mark Single Safe
  Future<void> markAsSafe(AssetEntity asset) async {
    flaggedAssets.remove(asset);
    noTouchFileNames.add(asset.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('safePicFileNames', noTouchFileNames.toList());
    notifyListeners();
  }

  // 2. Mark Batch Safe
  Future<void> markAsSafeBatch(List<AssetEntity> assets) async {
    for (var asset in assets) {
      flaggedAssets.remove(asset);
      noTouchFileNames.add(asset.id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('safePicFileNames', noTouchFileNames.toList());
    notifyListeners();
  }

  // 3. Delete Batch
  Future<void> deleteBatch(List<String> ids) async {
    try {
      final List<String> deletedIds = await PhotoManager.editor.deleteWithIds(ids);
      flaggedAssets.removeWhere((e) => deletedIds.contains(e.id));
      notifyListeners();
    } catch (e) {
      debugPrint("Batch delete error: $e");
    }
  }

  Future<void> deleteAsset(AssetEntity asset) async {
    await deleteBatch([asset.id]);
  }
}