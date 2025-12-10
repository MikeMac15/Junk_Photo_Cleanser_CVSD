import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../detector/screenshot_detector.dart';

// --- LOGIC CLASS (Adapted for Desktop Files) ---
class DesktopScanner extends ChangeNotifier {
  final ScreenshotDetector detector = ScreenshotDetector();

  // Data
  List<File> allFiles = [];
  List<File> flaggedFiles = [];
  Set<String> safePaths = {}; 
  
  // State
  bool loading = false;
  bool isPaused = false;
  String statusMsg = "";
  double confidenceLevel = 0.80;
  int scannedCount = 0;

  DesktopScanner() {
    _init();
  }

  Future<void> _init() async {
    await detector.loadModel();
    final prefs = await SharedPreferences.getInstance();
    final savedSafe = prefs.getStringList('desktopSafePaths');
    if (savedSafe != null) {
      safePaths = savedSafe.toSet();
    }
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

  // --- SCAN LOGIC ---
  Future<void> scanFolder(String folderPath) async {
    loading = true;
    isPaused = false;
    statusMsg = "Reading folder...";
    allFiles.clear();
    flaggedFiles.clear();
    scannedCount = 0;
    notifyListeners();

    final dir = Directory(folderPath);
    List<FileSystemEntity> entries = [];
    try {
      // Get all files first (recursive: false for safety, or true if you want deep scan)
      entries = dir.listSync(recursive: false).where((e) => e is File).toList();
    } catch (e) {
      statusMsg = "Error reading folder";
      loading = false;
      notifyListeners();
      return;
    }

    // Filter images
    allFiles = entries.whereType<File>().where((f) {
      final ext = f.path.toLowerCase();
      return ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png');
    }).toList();

    if (allFiles.isEmpty) {
      statusMsg = "No images found in folder";
      loading = false;
      notifyListeners();
      return;
    }

    statusMsg = "Scanning ${allFiles.length} images...";
    notifyListeners();

    if (!detector.isReady) await detector.loadModel();

    // Scan Loop
    for (var file in allFiles) {
      // Checks
      if (!loading) break;
      while (isPaused && loading) {
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Skip Safe Files
      if (safePaths.contains(file.path)) {
        scannedCount++;
        continue;
      }

      try {
        final score = await detector.classifyImage(file);
        if (score > confidenceLevel) {
          flaggedFiles.add(file);
          notifyListeners();
        }
      } catch (_) {}

      scannedCount++;
      if (scannedCount % 5 == 0) {
        statusMsg = "Scanning ($scannedCount / ${allFiles.length})...";
        notifyListeners();
      }
    }

    loading = false;
    isPaused = false;
    statusMsg = "Done. Found ${flaggedFiles.length} screenshots.";
    notifyListeners();
  }

  // --- BATCH ACTIONS ---
  Future<void> markAsSafeBatch(List<File> files) async {
    for (var f in files) {
      flaggedFiles.remove(f);
      safePaths.add(f.path);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('desktopSafePaths', safePaths.toList());
    notifyListeners();
  }

  Future<void> deleteBatch(List<File> files) async {
    for (var f in files) {
      try {
        if (await f.exists()) {
          await f.delete();
        }
        flaggedFiles.remove(f);
      } catch (e) {
        debugPrint("Error deleting ${f.path}: $e");
      }
    }
    notifyListeners();
  }
}

// --- UI WIDGET ---
class DesktopScanPage extends StatefulWidget {
  const DesktopScanPage({super.key});

  @override
  State<DesktopScanPage> createState() => _DesktopScanPageState();
}

class _DesktopScanPageState extends State<DesktopScanPage> {
  final DesktopScanner scanner = DesktopScanner();
  
  // Selection State
  final Set<String> _selectedPaths = {};
  bool _isSelectionMode = false;
  final ScrollController _scrollController = ScrollController();

  // --- SELECTION HELPERS ---
  void _toggleSelection(File file) {
    setState(() {
      if (_selectedPaths.contains(file.path)) {
        _selectedPaths.remove(file.path);
      } else {
        _selectedPaths.add(file.path);
      }
      _isSelectionMode = _selectedPaths.isNotEmpty;
    });
  }

  void _selectAll() {
    setState(() {
      _selectedPaths.clear();
      for (var f in scanner.flaggedFiles) {
        _selectedPaths.add(f.path);
      }
      _isSelectionMode = true;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedPaths.clear();
      _isSelectionMode = false;
    });
  }

  // --- ACTIONS ---
  Future<void> _pickFolderAndScan() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      scanner.scanFolder(selectedDirectory);
    }
  }

  Future<void> _handleKeepSelected() async {
    if (_selectedPaths.isEmpty) return;
    final selectedFiles = scanner.flaggedFiles.where((f) => _selectedPaths.contains(f.path)).toList();
    
    await scanner.markAsSafeBatch(selectedFiles);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Saved ${selectedFiles.length} images to Safe List")),
      );
      _clearSelection();
    }
  }

  Future<void> _handleDeleteSelected() async {
    if (_selectedPaths.isEmpty) return;
    
    // Pause logic
    bool wasScanning = scanner.loading;
    if (wasScanning && !scanner.isPaused) scanner.togglePause();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete ${_selectedPaths.length} Files?"),
        content: const Text("These files will be permanently deleted from your disk."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete Permanently"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final selectedFiles = scanner.flaggedFiles.where((f) => _selectedPaths.contains(f.path)).toList();
      await scanner.deleteBatch(selectedFiles);
      _clearSelection();
    }

    if (wasScanning && scanner.isPaused) scanner.togglePause();
  }

  // --- DRAG SELECTION ---
  void _handleDragSelect(Offset globalPosition) {
    if (scanner.flaggedFiles.isEmpty) return;

    // Desktop Grid Config (Matches GridView below)
    const int crossAxisCount = 5; // Wider on desktop usually
    const double crossAxisSpacing = 10.0;
    const double mainAxisSpacing = 10.0;

    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localPos = box.globalToLocal(globalPosition);
    final double screenWidth = MediaQuery.of(context).size.width;
    
    // Calculate Item Width
    // Removing padding (16*2)
    final double itemWidth = (screenWidth - 32 - (crossAxisSpacing * (crossAxisCount - 1))) / crossAxisCount;

    // Account for scrolling and header offset
    // Header is roughly 250px high (Control bar)
    final double scrollOffset = _scrollController.offset;
    final double adjustedY = localPos.dy + scrollOffset - 220; 

    if (localPos.dy < 180) return; // Don't select if dragging in header

    int col = (localPos.dx / (itemWidth + crossAxisSpacing)).floor();
    int row = (adjustedY / (itemWidth + mainAxisSpacing)).floor();

    if (col < 0) col = 0;
    if (col >= crossAxisCount) col = crossAxisCount - 1;
    if (row < 0) row = 0;

    int index = row * crossAxisCount + col;

    if (index >= 0 && index < scanner.flaggedFiles.length) {
      final file = scanner.flaggedFiles[index];
      if (!_selectedPaths.contains(file.path)) {
        setState(() {
          _selectedPaths.add(file.path);
          _isSelectionMode = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scanner,
      builder: (context, child) {
        return Scaffold(
          // --- APP BAR ---
          appBar: _isSelectionMode
              ? AppBar(
                  backgroundColor: Colors.blue.shade50,
                  leading: IconButton(
                    icon: const Icon(Icons.close, color: Colors.black),
                    onPressed: _clearSelection,
                  ),
                  title: Text(
                    "${_selectedPaths.length} Selected",
                    style: const TextStyle(color: Colors.black, fontSize: 18),
                  ),
                  actions: [
                    TextButton.icon(
                      icon: const Icon(Icons.select_all, size: 20),
                      label: const Text("Select All"),
                      onPressed: _selectAll,
                    ),
                  ],
                )
              : AppBar(
                  title: const Text("Desktop Junk Photo Cleanser"),
                  leading: Image.asset('assets/icon.png'),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0, left: 8.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 6,
                            backgroundColor:
                                scanner.detector.isReady ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 5),
                          Text(scanner.detector.isReady ? 'Ready' : 'Not Ready', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )
                  ],
                ),

          // --- FLOATING ACTION BUTTON ---
          floatingActionButton: scanner.flaggedFiles.isNotEmpty && !_isSelectionMode
              ? FloatingActionButton.extended(
                  onPressed: () => setState(() => _isSelectionMode = true),
                  label: const Text("Select Photos"),
                  icon: const Icon(Icons.checklist),
                )
              : null,

          // --- BOTTOM ACTION BAR ---
          bottomNavigationBar: _isSelectionMode
              ? Container(
                  height: 80,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _handleKeepSelected,
                          icon: const Icon(Icons.check, color: Colors.blue),
                          label: const Text("Keep Safe"),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _handleDeleteSelected,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text("Delete Permanently"),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : null,

          body: GestureDetector(
            onPanUpdate: _isSelectionMode 
              ? (details) => _handleDragSelect(details.globalPosition) 
              : null,
            
            child: Column(
              children: [
                // --- CONTROL BAR ---
                if (!_isSelectionMode)
                Container(
                  padding: const EdgeInsets.all(16.0),
                  color: Colors.grey.shade100,
                  child: scanner.loading
                      ? Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(scanner.statusMsg,
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  const LinearProgressIndicator(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            IconButton.filled(
                              onPressed: scanner.togglePause,
                              style: IconButton.styleFrom(backgroundColor: Colors.blue.shade100),
                              color: Colors.blue.shade900,
                              icon: Icon(scanner.isPaused ? Icons.play_arrow : Icons.pause),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: scanner.stopScan,
                              style: IconButton.styleFrom(backgroundColor: Colors.red.shade100),
                              color: Colors.red.shade900,
                              icon: const Icon(Icons.stop),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Detection Sensitivity",
                                    style: TextStyle(fontWeight: FontWeight.w600)),
                                Text("${(scanner.confidenceLevel * 100).toInt()}%",
                                    style: TextStyle(
                                        color: Theme.of(context).primaryColor,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Slider(
                              value: scanner.confidenceLevel,
                              min: 0.50,
                              max: 0.95,
                              divisions: 9,
                              onChanged: (val) => scanner.setConfidence(val),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 48,
                              child: FilledButton.icon(
                                label: const Text("Select Folder to Scan"),
                                icon: const Icon(Icons.folder_open),
                                onPressed: _pickFolderAndScan,
                              ),
                            ),
                          ],
                        ),
                ),

                // --- RESULTS GRID ---
                Expanded(
                  child: scanner.flaggedFiles.isEmpty
                      ? Center(
                          child: Text(
                            scanner.loading ? "Analyzing..." : "No screenshots found.",
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : GridView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 5, // 5 columns for desktop width
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: scanner.flaggedFiles.length,
                          itemBuilder: (context, index) {
                            final file = scanner.flaggedFiles[index];
                            final isSelected = _selectedPaths.contains(file.path);

                            return GestureDetector(
                              onTap: () => _toggleSelection(file),
                              onLongPress: () {
                                if (!_isSelectionMode) _toggleSelection(file);
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // 1. Image
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      file,
                                      fit: BoxFit.cover,
                                      // Cache/Resize helps performance on desktop grids
                                      cacheWidth: 300, 
                                    ),
                                  ),
                                  
                                  // 2. Overlay
                                  if (isSelected)
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(alpha: 0.4),
                                        border: Border.all(color: Colors.blue, width: 3),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Center(
                                        child: CircleAvatar(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                          child: Icon(Icons.check),
                                        ),
                                      ),
                                    )
                                  else if (_isSelectionMode)
                                    Container(
                                        alignment: Alignment.topRight,
                                        padding: const EdgeInsets.all(4),
                                        child: const CircleAvatar(
                                          radius: 10,
                                          backgroundColor: Colors.white54,
                                          child: Icon(Icons.circle_outlined, size: 16, color: Colors.black54),
                                        ),
                                     )
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}