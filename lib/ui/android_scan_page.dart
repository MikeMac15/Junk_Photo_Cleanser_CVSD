import 'package:cvsd/gallery_scan/gallery_scan.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AndroidScanPage extends StatefulWidget {
  const AndroidScanPage({super.key});

  @override
  State<AndroidScanPage> createState() => _AndroidScanPageState();
}

class _AndroidScanPageState extends State<AndroidScanPage> {
  GalleryScanner? scanner;

  // --- SELECTION STATE ---
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  Future<void> _initScanner() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final notouch = prefs.getStringList('safePicFileNames');
    final prevCount = prefs.getInt('prevScanCount');

    setState(() {
      scanner = GalleryScanner(prevCount, notouch);
      scanner!.onPermissionDenied = _showPermissionDialog;
    });
  }

  @override
  void dispose() {
    scanner?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- SELECTION LOGIC ---

  void _toggleSelection(AssetEntity asset) {
    setState(() {
      if (_selectedIds.contains(asset.id)) {
        _selectedIds.remove(asset.id);
      } else {
        _selectedIds.add(asset.id);
      }
      // Auto-exit selection mode if empty
      _isSelectionMode = _selectedIds.isNotEmpty;
    });
  }

  void _selectAll() {
    if (scanner == null) return;
    setState(() {
      _selectedIds.clear();
      for (var asset in scanner!.flaggedAssets) {
        _selectedIds.add(asset.id);
      }
      _isSelectionMode = true;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  // --- BATCH ACTIONS ---

  Future<void> _handleKeepSelected() async {
    if (scanner == null || _selectedIds.isEmpty) return;

    final count = _selectedIds.length;
    // Get the actual AssetEntity objects for the IDs
    final selectedAssets = scanner!.flaggedAssets
        .where((a) => _selectedIds.contains(a.id))
        .toList();

    await scanner!.markAsSafeBatch(selectedAssets);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Saved $count screenshots (won't be flagged again)"),
        ),
      );
      _clearSelection();
    }
  }

  Future<void> _handleDeleteSelected() async {
    if (scanner == null || _selectedIds.isEmpty) return;

    // Pause if scanning
    bool wasScanning = scanner!.loading;
    if (wasScanning && !scanner!.isPaused) {
      scanner!.togglePause();
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete ${_selectedIds.length} Items?"),
        content: const Text(
          "These screenshots will be permanently deleted from your device.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete Forever"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await scanner!.deleteBatch(_selectedIds.toList());
      _clearSelection();
    }

    // Resume if needed
    if (wasScanning && scanner!.isPaused) {
      scanner!.togglePause();
    }
  }

  void _showPermissionDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Permission Required"),
        content: const Text("Please allow access to Photos in Settings."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              PhotoManager.openSetting();
            },
            child: const Text("Settings"),
          ),
        ],
      ),
    );
  }

  // --- DRAG SELECTION HELPERS ---
  // Calculates which item is under the finger
  void _handleDragSelect(Offset globalPosition) {
    if (scanner == null || scanner!.flaggedAssets.isEmpty) return;

    // Grid settings matching the GridView below
    const int crossAxisCount = 3;
    const double crossAxisSpacing = 8.0;
    const double mainAxisSpacing = 8.0;

    // Calculate local position relative to the grid
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localPos = box.globalToLocal(globalPosition);

    // Grid Dimensions
    final double screenWidth = MediaQuery.of(context).size.width;
    final double itemWidth =
        (screenWidth - (crossAxisSpacing * (crossAxisCount - 1)) - 16) /
        crossAxisCount; // -16 for padding

    // Account for scrolling
    final double scrollOffset = _scrollController.offset;
    final double adjustedY =
        localPos.dy +
        scrollOffset -
        250; // Approx header height offset, crude but effective for simple list

    // Find Row and Column
    if (localPos.dy < 200) return; // Ignore dragging in header area

    int col = (localPos.dx / (itemWidth + crossAxisSpacing)).floor();
    int row = (adjustedY / (itemWidth + mainAxisSpacing))
        .floor(); // Assuming square items

    if (col < 0) col = 0;
    if (col >= crossAxisCount) col = crossAxisCount - 1;
    if (row < 0) row = 0;

    int index = row * crossAxisCount + col;

    if (index >= 0 && index < scanner!.flaggedAssets.length) {
      final asset = scanner!.flaggedAssets[index];
      if (!_selectedIds.contains(asset.id)) {
        setState(() {
          _selectedIds.add(asset.id);
          _isSelectionMode = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (scanner == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ListenableBuilder(
      listenable: scanner!,
      builder: (context, child) {
        return Scaffold(
          // --- APP BAR CHANGES BASED ON SELECTION ---
          appBar: _isSelectionMode
              ? AppBar(
                  backgroundColor: Colors.blue.shade50,
                  leading: IconButton(
                    icon: const Icon(Icons.close, color: Colors.black),
                    onPressed: _clearSelection,
                  ),
                  title: Text(
                    "${_selectedIds.length} Selected",
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
                  title: const Text("Junk Photo Cleanser"),
                  centerTitle: true,
                  leading: Image.asset('assets/icon.png'),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0, left: 8.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 6,
                            backgroundColor: scanner!.detector.isReady
                                ? Colors.green
                                : Colors.red,
                          ),
                          SizedBox(width: 5),
                          Text(
                            scanner!.loading
                                ? 'Scanning'
                                : scanner!.detector.isReady
                                ? 'Ready'
                                : 'Not Ready',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

          // --- FLOATING ACTION BUTTON (TRIGGER MODE) ---
          floatingActionButton:
              scanner!.flaggedAssets.isNotEmpty && !_isSelectionMode
              ? FloatingActionButton.extended(
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = true;
                    });
                  },
                  label: const Text("Select Photos"),
                  icon: const Icon(Icons.checklist),
                )
              : null,

          // --- BOTTOM ACTION BAR (WHEN SELECTED) ---
          bottomNavigationBar: _isSelectionMode
              ? Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // KEEP BUTTON
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _handleKeepSelected,
                          icon: const Icon(Icons.check, color: Colors.blue),
                          label: const Text("Keep Safe"),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.blue),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // DELETE BUTTON
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _handleDeleteSelected,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text("Delete"),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : null,

          body: GestureDetector(
            // --- DRAG TO SELECT LOGIC ---
            onPanUpdate: _isSelectionMode
                ? (details) => _handleDragSelect(details.globalPosition)
                : null,

            child: Column(
              children: [
                // --- CONTROL BAR (Only visible if not selecting) ---
                if (!_isSelectionMode)
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    color: Colors.grey.shade100,
                    child: scanner!.loading
                        ? Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      scanner!.statusMsg,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const LinearProgressIndicator(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              IconButton.filled(
                                onPressed: scanner!.togglePause,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.blue.shade100
                                      .withAlpha(100),
                                ),
                                color: Colors.blue.shade900,
                                icon: Icon(
                                  scanner!.isPaused
                                      ? Icons.play_arrow
                                      : Icons.pause,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                onPressed: scanner!.stopScan,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.red.shade100,
                                ),
                                color: Colors.red.shade900,
                                icon: const Icon(Icons.stop),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Detection Sensitivity",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    "${(scanner!.confidenceLevel * 100).toInt()}%",
                                    style: TextStyle(
                                      color: Theme.of(context).primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: scanner!.confidenceLevel,
                                min: 0.50,
                                max: 0.95,
                                divisions: 9,
                                onChanged: (val) => scanner!.setConfidence(val),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                spacing: 10,
                                children: [
                                  scanner!.scannedIndexOffset > 0
                                      ? SizedBox(
                                          height: 48,
                                          child: FilledButton.icon(
                                            label: Text(
                                              "Resume Scan (${scanner!.scannedIndexOffset})",
                                            ),
                                            icon: const Icon(Icons.play_arrow),
                                            onPressed: scanner!.scanGallery,
                                          ),
                                        )
                                      : SizedBox(
                                          height: 48,
                                          child: FilledButton.icon(
                                            label: Text("Start Gallery Scan"),
                                            icon: const Icon(
                                              Icons
                                                  .screen_search_desktop_rounded,
                                            ),
                                            onPressed: scanner!.scanGallery,
                                          ),
                                        ),
                                  if (scanner!.scannedIndexOffset > 0)
                                    SizedBox(
                                      height: 48,
                                      child: FilledButton.icon(
                                        label: const Text("Start New Scan"),
                                        icon: const Icon(Icons.refresh),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors
                                              .blueGrey,
                                        ),
                                        onPressed: () async {
                                          await scanner!.resetScanProgress();
                                          scanner!.scanGallery();
                                        },
                                      ),
                                    ),
                                ],
                              ),
                              SizedBox(height: 20),
                            ],
                          ),
                  ),
                // --- RESULTS GRID ---
                Expanded(
                  child: scanner!.flaggedAssets.isEmpty
                      ? Center(
                          child: Text(
                            scanner!.loading
                                ? "Searching..."
                                : "No screenshots found.",
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : GridView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                          itemCount: scanner!.flaggedAssets.length,
                          itemBuilder: (context, index) {
                            final asset = scanner!.flaggedAssets[index];
                            final isSelected = _selectedIds.contains(asset.id);

                            return GestureDetector(
                              onTap: () => _toggleSelection(asset),
                              onLongPress: () {
                                if (!_isSelectionMode) {
                                  _toggleSelection(asset);
                                }
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // 1. The Image
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: AssetEntityImage(
                                      asset,
                                      isOriginal: false,
                                      thumbnailSize: const ThumbnailSize.square(
                                        200,
                                      ),
                                      fit: BoxFit.cover,
                                    ),
                                  ),

                                  // 2. Selection Overlay
                                  if (isSelected)
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withValues(
                                          alpha: 0.4,
                                        ),
                                        border: Border.all(
                                          color: Colors.blue,
                                          width: 3,
                                        ),
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
                                    // Unselected state in selection mode (dim slightly or show ring)
                                    Container(
                                      alignment: Alignment.topRight,
                                      padding: const EdgeInsets.all(4),
                                      child: const CircleAvatar(
                                        radius: 10,
                                        backgroundColor: Colors.white54,
                                        child: Icon(
                                          Icons.circle_outlined,
                                          size: 16,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
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
