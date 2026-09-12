// ignore_for_file: unused_field

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:gis_attendance/services/attendance_service.dart';

class FaceVerificationScreen extends StatefulWidget {
  final CameraDescription camera;

  /// The logged-in officer's id (e.g. "P/012/2025"). The captured frame
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
  late CameraController _controller;
  late FaceDetector _faceDetector;
  late AnimationController _animationController;

  bool _isInitialized = false;
  bool _isVerifying = false;
  File? _capturedImage; // Holds the "frozen" frame
  List<Face> _faces = [];
  Size? _imageSize;
  Timer? _autoCaptureTimer;
  bool _isProcessing = false;

  final AttendanceService _attendanceService = AttendanceService();

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller.initialize();
      await _controller.startImageStream(_processCameraImage);
      setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isVerifying || _capturedImage != null || _isProcessing) return;

    _isProcessing = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(widget.camera.sensorOrientation) ??
            InputImageRotation.rotation0deg,
        format: InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);

      final faces = await _faceDetector.processImage(inputImage);

      if (mounted) {
        setState(() {
          _faces = faces;
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        });

        if (faces.isNotEmpty && _autoCaptureTimer == null) {
          _autoCaptureTimer = Timer(const Duration(milliseconds: 800), () {
            _captureAndVerify();
          });
        } else if (faces.isEmpty) {
          _autoCaptureTimer?.cancel();
          _autoCaptureTimer = null;
        }
      }
    } catch (e) {
      debugPrint("Processing error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _captureAndVerify() async {
    if (_isVerifying || _faces.isEmpty) return;

    try {
      // 1. Capture the frame
      final XFile imageFile = await _controller.takePicture();

      setState(() {
        _isVerifying = true;
        _capturedImage = File(imageFile.path);
      });

      await _controller.stopImageStream();

      // 2. 1:1 check against this officer's registered face. On a match
      // the caller does the actual clock in/out.
      final result = await _attendanceService.verifyFace(
        officerId: widget.userId,
        imageFile: _capturedImage!,
      );

      if (result.ok) {
        if (kDebugMode) print("✅ Identity verified: ${result.message}");
        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      _showRetryDialog(result.message);
    } catch (e) {
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
    _autoCaptureTimer = null;
    setState(() {
      _isVerifying = false;
      _capturedImage = null;
      _faces = [];
    });
    await _controller.startImageStream(_processCameraImage);
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _animationController.dispose();
    _controller.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _capturedImage != null
              ? Image.file(_capturedImage!, fit: BoxFit.cover)
              : CameraPreview(_controller),

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
            _faces.isEmpty
                ? "Center your face in the circle"
                : "Hold still...",
            style: TextStyle(
              color: _faces.isEmpty ? Colors.white70 : Colors.greenAccent,
              fontWeight: FontWeight.w500,
            ),
          ),
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
          onTap: _captureAndVerify,
          child: Container(
            height: 85,
            width: 85,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 3)),
            child: Container(
              decoration: BoxDecoration(
                color: _faces.isEmpty ? Colors.white24 : Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.camera_alt, color: _faces.isEmpty ? Colors.white38 : Colors.black, size: 35),
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
            hasFace: _faces.isNotEmpty,
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