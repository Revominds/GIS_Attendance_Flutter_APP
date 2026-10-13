// Face check — photo-based (no live frame stream).
//
// Earlier versions fed raw camera-stream bytes to MLKit and broke on
// device-specific frame layouts (RangeError, InputImageConverter NPEs).
// This screen now only shows the camera preview; verification runs on a
// captured photo via InputImage.fromFilePath (the rock-solid path):
// auto-capture a few seconds after opening, or tap the camera button.
// An on-device face-presence check runs first; the server then does the
// real 1:1 match via POST /api/verify.

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:gis_attendance/services/attendance_service.dart';

class FaceVerificationScreen extends StatefulWidget {
  final CameraDescription camera;

  /// The logged-in officer's id (e.g. "P/012/2025"). The captured photo
  /// is checked 1:1 against THIS officer's registered face via
  /// POST /api/verify. On a match the screen pops `true` and the caller
  /// performs the clock in/out.
  final String userId;

  const FaceVerificationScreen({
    super.key,
    required this.camera,
    required this.userId,
  });

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  late FaceDetector _faceDetector;
  late AnimationController _animationController;

  bool _isInitialized = false;
  bool _isVerifying = false;
  File? _capturedImage; // Holds the "frozen" frame
  bool _hasFace = false;
  String? _debugStatus;
  Timer? _autoCaptureTimer;

  final AttendanceService _attendanceService = AttendanceService();

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        // Fast mode is more lenient than accurate and doesn't wait on a
        // downloadable model — accurate silently throws on devices without
        // Play-services face models, which this screen used to swallow as
        // "No face found". Keep the threshold low so small/dark faces pass
        // the local gate; the server (Face++) is the real matcher.
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: false,
        enableClassification: false,
        enableContours: false,
        minFaceSize: 0.1,
        enableTracking: false,
      ),
    );

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _debugStatus = 'Center your face — auto capture in a moment…';
      });
      // Auto-capture once the preview settles. No image stream involved.
      _autoCaptureTimer?.cancel();
      _autoCaptureTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && !_isVerifying && _capturedImage == null) {
          _captureAndVerify();
        }
      });
    } catch (e) {
      debugPrint("Camera Error: $e");
      if (mounted) setState(() => _debugStatus = 'Camera error: $e');
    }
  }

  /// Manual captures (camera button) always run; auto-capture also runs.
  /// A photo is taken, checked on-device for a face, then sent to the
  /// server for the real 1:1 match.
  Future<void> _captureAndVerify({bool manual = false}) async {
    final controller = _controller;
    if (_isVerifying ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    _autoCaptureTimer?.cancel();

    setState(() {
      _isVerifying = true;
      _debugStatus = manual ? 'Checking photo…' : 'Captured — checking…';
    });

    try {
      // Let auto-exposure/focus settle — a photo grabbed the instant the
      // button is tapped (or 3s after open) is often dark/blurry and MLKit
      // returns zero faces for it.
      await Future.delayed(const Duration(milliseconds: 400));
      final XFile imageFile = await controller.takePicture();
      final file = File(imageFile.path);

      if (!await file.exists() || await file.length() == 0) {
        throw Exception('Camera returned an empty photo — try again.');
      }

      // 1. On-device presence check (file path = stable MLKit route).
      // This is ADVISORY only: MLKit misses faces in poor light where the
      // server (Face++) still matches, and on some devices the detector
      // throws (missing Play-services model). Neither case should hard-
      // block verification — the server is the ground truth and reports
      // "no face" itself when there really isn't one.
      bool faceFound = false;
      String? detectorError;
      try {
        final faces =
            await _faceDetector.processImage(InputImage.fromFilePath(file.path));
        faceFound = faces.isNotEmpty;
        debugPrint('local face check: ${faces.length} face(s)');
      } catch (e) {
        detectorError = e.toString();
        debugPrint('file detect error: $e');
      }
      if (!mounted) return;

      setState(() {
        _capturedImage = file;
        _hasFace = faceFound;
        _debugStatus = faceFound
            ? 'Face found — verifying identity…'
            : detectorError != null
                ? 'Local check errored ($detectorError) — asking server…'
                : 'Local check missed — asking server…';
      });

      // 2. 1:1 check against this officer's registered face. On a match
      // the caller does the actual clock in/out.
      final result = await _attendanceService.verifyFace(
        officerId: widget.userId,
        imageFile: file,
      );

      if (result.ok) {
        if (kDebugMode) print("✅ Identity verified: ${result.message}");
        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _debugStatus = 'Server: ${result.message}';
      });
      _showRetryDialog(result.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _debugStatus = 'Capture failed — retry';
      });
      _showRetryDialog("Verification failed: $e");
    }
  }

  void _showRetryDialog(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Verification Failed"),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resetCamera();
            },
            child: const Text("Retry"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  Future<void> _resetCamera() async {
    _autoCaptureTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _isVerifying = false;
      _capturedImage = null;
      _hasFace = false;
      _debugStatus = 'Center your face — auto capture in a moment…';
    });
    _autoCaptureTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isVerifying && _capturedImage == null) {
        _captureAndVerify();
      }
    });
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _animationController.dispose();
    try {
      _controller?.dispose();
    } catch (_) {}
    try {
      _faceDetector.close();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_isInitialized || controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (_debugStatus != null) ...[
                const SizedBox(height: 12),
                Text(_debugStatus!,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _capturedImage != null
              ? Image.file(_capturedImage!, fit: BoxFit.cover)
              : CameraPreview(controller),

          if (_capturedImage == null) ...[
            _buildOverlay(),
            _buildHeader(),
            _buildCaptureButton(),
          ],

          if (_isVerifying)
            Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.greenAccent),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                      child: const Text("VERIFYING IDENTITY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Column(
        children: [
          const Text("Biometric Check", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _hasFace
                ? "Hold still..."
                : "Center your face in the circle — or tap 📷",
            style: TextStyle(
              color: _hasFace ? Colors.greenAccent : Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_debugStatus != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _debugStatus!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCaptureButton() {
    return Positioned(
      bottom: 50,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () => _captureAndVerify(manual: true),
          child: Container(
            height: 85,
            width: 85,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 3)),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt, color: Colors.black, size: 35),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return CustomPaint(
          painter: ScannerPainter(
            scanProgress: _animationController.value,
            hasFace: _hasFace,
          ),
        );
      },
    );
  }
}

class ScannerPainter extends CustomPainter {
  final double scanProgress;
  final bool hasFace;

  ScannerPainter({required this.scanProgress, required this.hasFace});

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()
      ..addOval(Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2.2),
        width: size.width * 0.75,
        height: size.width * 1.0,
      ));

    canvas.drawPath(
      Path.combine(PathOperation.difference, backgroundPath, cutoutPath),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );

    final borderPaint = Paint()
      ..color = hasFace ? Colors.greenAccent : Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawPath(cutoutPath, borderPaint);

    if (hasFace) {
      final centerY = size.height / 2.2;
      final radiusY = size.width * 0.5;
      final lineY = (centerY - radiusY) + (radiusY * 2 * scanProgress);

      canvas.drawLine(
        Offset(size.width * 0.25, lineY),
        Offset(size.width * 0.75, lineY),
        Paint()..color = Colors.greenAccent.withValues(alpha: 0.6)..strokeWidth = 2.0,
      );
    }
  }

  @override
  bool shouldRepaint(ScannerPainter oldDelegate) => true;
}
