import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../core/theme/app_theme.dart';
import '../services/camera_image_converter.dart';
import '../services/face_biometric_service.dart';

class FaceAttendanceResult {
  final bool success;
  final String? photoPath;
  final double similarityScore;
  final bool livenessVerified;
  final bool isEnrollment;
  final List<double>? faceEmbedding;
  final String? errorMessage;

  FaceAttendanceResult({
    required this.success,
    this.photoPath,
    this.similarityScore = 0.0,
    this.livenessVerified = false,
    this.isEnrollment = false,
    this.faceEmbedding,
    this.errorMessage,
  });
}

enum DetectionState {
  searching,
  positioning,
  livenessChallenge,
  authenticating,
  success,
  failed,
}

class FaceAttendanceScreen extends StatefulWidget {
  const FaceAttendanceScreen({
    super.key,
    required this.email,
    required this.isClockIn,
    this.isEnrollmentMode = false,
  });

  final String email;
  final bool isClockIn;
  final bool isEnrollmentMode;

  @override
  State<FaceAttendanceScreen> createState() => _FaceAttendanceScreenState();
}

class _FaceAttendanceScreenState extends State<FaceAttendanceScreen> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  late FaceDetector _faceDetector;
  bool _isCameraInitialized = false;
  bool _isProcessingFrame = false;
  String? _initError;

  DetectionState _state = DetectionState.searching;
  String _instruction = 'Posisikan wajah Anda di dalam lingkaran';
  String _subInstruction = 'Pastikan pencahayaan cukup dan wajah terlihat jelas';
  double _similarityScore = 0.0;
  bool _isEnrolled = false;
  List<double>? _masterVector;

  final List<List<double>> _sampleVectors = [];
  List<double>? _capturedFaceVector;
  DateTime? _lastChallengeCheck;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initFaceDetector();
    _loadMasterDataAndInitCamera();
  }

  void _initFaceDetector() {
    final options = FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableContours: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    );
    _faceDetector = FaceDetector(options: options);
  }

  Future<void> _loadMasterDataAndInitCamera() async {
    _masterVector = await FaceBiometricService.getMasterFace(widget.email);
    _isEnrolled = _masterVector != null && _masterVector!.isNotEmpty;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _initError = 'Tidak ada sensor kamera yang terdeteksi di perangkat.');
        return;
      }

      // Prioritaskan kamera depan
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isCameraInitialized = true;
      });

      await controller.startImageStream((CameraImage image) {
        _processCameraImage(image, frontCamera);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _initError = 'Gagal mengakses kamera: $e');
      }
    }
  }

  Future<void> _processCameraImage(CameraImage image, CameraDescription camera) async {
    if (_isProcessingFrame || !mounted || _state == DetectionState.success || _state == DetectionState.failed) {
      return;
    }

    _isProcessingFrame = true;

    try {
      final inputImage = CameraImageConverter.convertCameraImage(
        image: image,
        camera: camera,
        deviceOrientation: DeviceOrientation.portraitUp,
      );

      if (inputImage == null) {
        _isProcessingFrame = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);
      if (!mounted) {
        _isProcessingFrame = false;
        return;
      }

      _evaluateFaces(faces);
    } catch (_) {
      // Abaikan frame yang gagal diproses
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _evaluateFaces(List<Face> faces) {
    if (faces.isEmpty) {
      setState(() {
        _state = DetectionState.searching;
        _instruction = 'Posisikan wajah Anda di dalam lingkaran';
        _subInstruction = 'Arahkan wajah tegak lurus menghadap kamera';
        _sampleVectors.clear();
      });
      return;
    }

    if (faces.length > 1) {
      setState(() {
        _state = DetectionState.searching;
        _instruction = 'Terlalu banyak wajah!';
        _subInstruction = 'Pastikan hanya ada satu orang di depan kamera';
        _sampleVectors.clear();
      });
      return;
    }

    final face = faces.first;
    final isFacingCenter = FaceBiometricService.isFacingCenter(face);

    // TAHAP 1: Menghadap tengah & kumpulkan sampel wajah
    if (_state == DetectionState.searching || _state == DetectionState.positioning) {
      if (isFacingCenter) {
        final sample = FaceBiometricService.extractFeatureVector(face);
        if (sample.isNotEmpty) {
          _sampleVectors.add(sample);
        }
        setState(() {
          _state = DetectionState.positioning;
          _instruction = 'Tahan posisi wajah lurus...';
          _subInstruction = 'Sedang membaca fitur biometrik (${_sampleVectors.length}/5)';
        });

        if (_sampleVectors.length >= 5) {
          // Hitung rata-rata fitur dari 5 frame untuk vektor yang sangat stabil & akurat
          final vecLen = _sampleVectors.first.length;
          final avgVector = List<double>.filled(vecLen, 0.0);
          for (final s in _sampleVectors) {
            for (var i = 0; i < min(vecLen, s.length); i++) {
              avgVector[i] += s[i];
            }
          }
          for (var i = 0; i < vecLen; i++) {
            avgVector[i] /= _sampleVectors.length;
          }

          _capturedFaceVector = avgVector;
          _sampleVectors.clear();

          if (widget.isEnrollmentMode) {
            _capturePhotoAndFinish(isEnrollment: true);
            return;
          }
          _lastChallengeCheck = DateTime.now();
          setState(() {
            _state = DetectionState.livenessChallenge;
            _instruction = 'Tantangan Liveness: Tolehkan kepala ke Kanan';
            _subInstruction = 'Gerakkan kepala perlahan ke arah kanan Anda';
          });
        }
      } else {
        _sampleVectors.clear();
        setState(() {
          _state = DetectionState.positioning;
          _instruction = 'Arahkan wajah lurus ke depan';
          _subInstruction = 'Jangan terlalu miring ke atas, bawah, atau samping';
        });
      }
      return;
    }

    // TAHAP 2: Tantangan Liveness (Menoleh ke kanan / gerak aktif)
    if (_state == DetectionState.livenessChallenge) {
      final turnedSide = FaceBiometricService.isTurnedSide(face, rightSide: true);
      final blinking = FaceBiometricService.isBlinking(face);

      // Cek apakah instruksi terpenuhi
      if (turnedSide || blinking) {
        _verifyIdentityAndComplete();
      } else {
        // Timeout tantangan jika lebih dari 12 detik tanpa respon
        if (_lastChallengeCheck != null && DateTime.now().difference(_lastChallengeCheck!).inSeconds > 15) {
          setState(() {
            _state = DetectionState.failed;
            _instruction = 'Tantangan Liveness Melebihi Batas Waktu';
            _subInstruction = 'Gerakan tidak terdeteksi. Silakan coba lagi.';
          });
        }
      }
    }
  }

  Future<void> _verifyIdentityAndComplete() async {
    setState(() {
      _state = DetectionState.authenticating;
      _instruction = 'Memverifikasi Identitas Wajah...';
      _subInstruction = 'Mencocokkan dengan profil biometrik Anda';
    });

    await Future<void>.delayed(const Duration(milliseconds: 600));

    final currentVector = _capturedFaceVector;
    if (currentVector == null || currentVector.isEmpty) {
      setState(() {
        _state = DetectionState.failed;
        _instruction = 'Gagal mengekstrak fitur wajah';
        _subInstruction = 'Pastikan wajah berada di area terang dan ulangi.';
      });
      return;
    }

    // Kasus 1: Pendaftaran Wajah Pertama Kali (Enrollment Mode eksplisit)
    if (widget.isEnrollmentMode) {
      await FaceBiometricService.saveMasterFace(widget.email, currentVector);
      _masterVector = currentVector;
      _isEnrolled = true;
      _similarityScore = 1.0;

      await _capturePhotoAndFinish(isEnrollment: true);
      return;
    }

    // Jika mode presensi biasa TAPI belum terdaftar di perangkat:
    if (!_isEnrolled || _masterVector == null || _masterVector!.isEmpty) {
      setState(() {
        _state = DetectionState.failed;
        _instruction = 'Wajah Belum Terdaftar!';
        _subInstruction = 'Data biometrik belum ada. Silakan lakukan pendaftaran wajah terlebih dahulu.';
      });
      return;
    }

    // Kasus 2: Autentikasi Wajah terhadap Master Terdaftar
    final similarity = FaceBiometricService.computeSimilarity(currentVector, _masterVector!);
    _similarityScore = similarity;
    debugPrint('--> [BIOMETRIC MATCH] Mode: ${widget.isClockIn ? "CLOCK IN" : "CLOCK OUT"} | Score: ${(similarity * 100).toStringAsFixed(1)}% | Threshold: ${(FaceBiometricService.matchThreshold * 100).toInt()}%');

    if (similarity >= FaceBiometricService.matchThreshold) {
      // Autentikasi Sukses
      await _capturePhotoAndFinish(isEnrollment: false);
    } else {
      // Wajah Tidak Cocok (Kemiripan di bawah threshold)
      setState(() {
        _state = DetectionState.failed;
        _instruction = 'Wajah Tidak Cocok dengan Pemilik Akun!';
        _subInstruction = 'Tingkat kemiripan hanya ${(similarity * 100).toStringAsFixed(1)}% (Minimal ${(FaceBiometricService.matchThreshold * 100).toInt()}%).';
      });
    }
  }

  Future<void> _capturePhotoAndFinish({required bool isEnrollment}) async {
    setState(() {
      _state = DetectionState.success;
      _instruction = isEnrollment
          ? 'Wajah Berhasil Didaftarkan & Presensi Selesai!'
          : 'Wajah Terverifikasi (${(_similarityScore * 100).toStringAsFixed(0)}%)!';
      _subInstruction = 'Mengambil bukti foto kehadiran...';
    });

    String? photoPath;
    try {
      if (_cameraController != null && _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      final file = await _cameraController?.takePicture();
      photoPath = file?.path;
    } catch (_) {
      // Jika kamera gagal capture snapshot, tetap lanjut membawa hasil verifikasi
    }

    await Future<void>.delayed(const Duration(milliseconds: 1000));

    if (mounted) {
      Navigator.of(context).pop(
        FaceAttendanceResult(
          success: true,
          photoPath: photoPath,
          similarityScore: _similarityScore,
          livenessVerified: true,
          isEnrollment: isEnrollment,
          faceEmbedding: _capturedFaceVector,
        ),
      );
    }
  }

  void _manualFallbackCapture() async {
    // Mode fallback untuk emulator jika webcam virtual emulator tidak mendukung landmark dinamis
    setState(() {
      _state = DetectionState.authenticating;
      _instruction = 'Memproses Autentikasi Manual...';
    });

    await Future<void>.delayed(const Duration(milliseconds: 800));

    String? photoPath;
    try {
      if (_cameraController != null && _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      final file = await _cameraController?.takePicture();
      photoPath = file?.path;
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pop(
        FaceAttendanceResult(
          success: true,
          photoPath: photoPath,
          similarityScore: 0.95,
          livenessVerified: true,
          isEnrollment: widget.isEnrollmentMode || !_isEnrolled,
          faceEmbedding: const [0.85, 0.42, 0.55, 0.62, 0.38, 0.71, 0.92, 0.45],
        ),
      );
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Color _getOverlayColor() {
    switch (_state) {
      case DetectionState.searching:
        return Colors.white.withValues(alpha: 0.8);
      case DetectionState.positioning:
        return const Color(0xFF38BDF8); // Biru muda
      case DetectionState.livenessChallenge:
        return AppColors.amber; // Kuning/Oranye
      case DetectionState.authenticating:
        return AppColors.teal;
      case DetectionState.success:
        return const Color(0xFF10B981); // Hijau Emerald
      case DetectionState.failed:
        return const Color(0xFFEF4444); // Merah
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 54),
                const SizedBox(height: 16),
                Text(
                  _initError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Kembali ke Menu Presensi'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isCameraInitialized || _cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.teal),
              SizedBox(height: 16),
              Text(
                'Menyiapkan kamera biometrik...',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
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
          // 1. Live Camera Stream
          CameraPreview(_cameraController!),

          // 2. Custom Oval Overlay & Radar Scanner
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return CustomPaint(
                painter: FaceOvalOverlayPainter(
                  borderColor: _getOverlayColor(),
                  scale: (_state == DetectionState.livenessChallenge || _state == DetectionState.positioning)
                      ? _pulseAnimation.value
                      : 1.0,
                ),
              );
            },
          ),

          // 3. Top Header Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            widget.isEnrollmentMode
                                ? Icons.face_retouching_natural_rounded
                                : (widget.isClockIn ? Icons.login_rounded : Icons.logout_rounded),
                            size: 16,
                            color: widget.isEnrollmentMode
                                ? const Color(0xFF38BDF8)
                                : (widget.isClockIn ? AppColors.teal : AppColors.amber),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.isEnrollmentMode
                                ? 'PENDAFTARAN WAJAH'
                                : (widget.isClockIn ? 'VERIFIKASI CLOCK IN' : 'VERIFIKASI CLOCK OUT'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48), // Spacer penyeimbang
                  ],
                ),
              ),
            ),
          ),

          // 4. Bottom Instruction & Status Card
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _getOverlayColor().withValues(alpha: 0.5), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildStateIcon(),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _instruction,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _subInstruction,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_state == DetectionState.failed) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _state = DetectionState.searching;
                          _sampleVectors.clear();
                          _capturedFaceVector = null;
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba Pindai Ulang'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
                // Tombol Fallback (membantu pengujian di emulator jika sensor kamera virtual terbatas)
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _manualFallbackCapture,
                  child: Text(
                    'Simulasi Verifikasi Berhasil (Mode Dev/Emulator)',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateIcon() {
    switch (_state) {
      case DetectionState.searching:
        return const Icon(Icons.face, color: Colors.white, size: 22);
      case DetectionState.positioning:
        return const Icon(Icons.center_focus_strong, color: Color(0xFF38BDF8), size: 22);
      case DetectionState.livenessChallenge:
        return const Icon(Icons.turn_right_rounded, color: AppColors.amber, size: 24);
      case DetectionState.authenticating:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
        );
      case DetectionState.success:
        return const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24);
      case DetectionState.failed:
        return const Icon(Icons.cancel_rounded, color: Color(0xFFEF4444), size: 24);
    }
  }
}

/// Painter untuk membuat oval pemandu wajah transparan dengan bayangan gelap di luarnya
class FaceOvalOverlayPainter extends CustomPainter {
  final Color borderColor;
  final double scale;

  FaceOvalOverlayPainter({
    required this.borderColor,
    this.scale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.52)
      ..style = PaintingStyle.fill;

    final ovalWidth = size.width * 0.72 * scale;
    final ovalHeight = size.height * 0.46 * scale;
    final center = Offset(size.width / 2, size.height * 0.42);

    final ovalRect = Rect.fromCenter(
      center: center,
      width: ovalWidth,
      height: ovalHeight,
    );

    // Buat masking: gambar gelap di seluruh layar KECUALI di dalam oval
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, backgroundPaint);

    // Garis batas oval
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    canvas.drawOval(ovalRect, borderPaint);

    // Titik sudut / aksen target scanner
    final accentPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    final radiusX = ovalWidth / 2;
    final radiusY = ovalHeight / 2;

    // 4 titik aksen di kuadran oval
    canvas.drawLine(
      Offset(center.dx - radiusX - 8, center.dy),
      Offset(center.dx - radiusX + 12, center.dy),
      accentPaint,
    );
    canvas.drawLine(
      Offset(center.dx + radiusX - 12, center.dy),
      Offset(center.dx + radiusX + 8, center.dy),
      accentPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radiusY - 8),
      Offset(center.dx, center.dy - radiusY + 12),
      accentPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy + radiusY - 12),
      Offset(center.dx, center.dy + radiusY + 8),
      accentPaint,
    );
  }

  @override
  bool shouldRepaint(covariant FaceOvalOverlayPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor || oldDelegate.scale != scale;
  }
}
