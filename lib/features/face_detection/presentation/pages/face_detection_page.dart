import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import '../../../victory/victory_page.dart';
import '../../domain/models/game_expression.dart';
import '../../domain/services/camera_service.dart';
import '../../domain/services/face_detector_service.dart';
import '../../domain/services/game_service.dart';

class FaceDetectionPage extends StatefulWidget {
  const FaceDetectionPage({super.key});

  @override
  State<FaceDetectionPage> createState() => _FaceDetectionPageState();
}

class _FaceDetectionPageState extends State<FaceDetectionPage> {
  // Services
  final CameraService _cameraService = CameraService();
  final FaceDetectorService _faceDetectorService = FaceDetectorService();
  final GameService _gameService = GameService();
  GameExpression? currentDetectedExpression;

  bool _isStreamActive = false;

  // State variables
  bool isDetecting = false;
  String instructionText = 'Bersiaplah!';
  Color instructionColor = Colors.white;
  Widget instructionIcon = const Icon(Icons.timer, color: Colors.amberAccent);

  // Face metrics
  double? smilingProbability;
  double? leftEyeOpenProbability;
  double? rightEyeOpenProbability;
  double? headEulerAngleY;
  double? headEulerAngleZ;

  // Landmark metrics
  double? mouthCornerRatio;
  double? eyebrowEyeRatio;
  double? mouthAspectRatio;

  // Expression timing
  DateTime? _expressionStartTime;
  bool _isExpressionValid = false;
  static const Duration _requiredHoldDuration = Duration(milliseconds: 500);
  static const Duration _roundPauseDuration = Duration(seconds: 2);
  bool _isInRoundPause = false;
  Timer? _expressionTimer;
  Timer? _roundPauseTimer;
  double _expressionProgress = 0.0;

  // Path foto senyum yang berhasil dicapture
  String? _smilePhotoPath;

  bool _isSmileDetectionActive = false;
  bool _isCapturingSmile = false;
  double _smileDetectionProgress = 0.0;
  DateTime? _smileDetectionStartTime;
  Timer? _smileDetectionTimer;
  static const Duration _smileHoldDuration = Duration(seconds: 2);

  // 3. Method untuk menampilkan dialog deteksi senyum
  void _showSmileDetectionDialog() {
    // Reset detection states
    _isSmileDetectionActive = false;
    _isCapturingSmile = false;
    _smileDetectionProgress = 0.0;
    _smileDetectionStartTime = null;
    _smileDetectionTimer?.cancel();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => Dialog(
                  backgroundColor: Colors.transparent,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    height: MediaQuery.of(context).size.height * 0.8,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF667eea), Color(0xFFf093fb)],
                            ),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(18),
                              topRight: Radius.circular(18),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    '😊 Foto Senyum Otomatis',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isSmileDetectionActive
                                    ? (_isCapturingSmile
                                        ? 'Tahan senyum... ${(_smileDetectionProgress * 100).toInt()}%'
                                        : 'Tersenyumlah untuk mengambil foto!')
                                    : 'Tekan "Mulai" lalu tersenyum selama 2 detik',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),

                        // Camera Preview
                        Expanded(
                          child: Stack(
                            children: [
                              // Camera preview
                              if (_cameraService.isInitialized)
                                Positioned.fill(
                                  child: ClipRRect(
                                    child: CameraPreview(
                                      _cameraService.cameraController,
                                    ),
                                  ),
                                )
                              else
                                const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),

                              // Smile detection overlay
                              if (_isSmileDetectionActive)
                                Positioned(
                                  top: 20,
                                  left: 20,
                                  right: 20,
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color:
                                          _isCapturingSmile
                                              ? Colors.green.withOpacity(0.8)
                                              : Colors.blue.withOpacity(0.8),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          _isCapturingSmile
                                              ? Icons.camera
                                              : Icons.face,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _isCapturingSmile
                                              ? 'Memproses senyum...'
                                              : 'Menunggu senyum...',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (_isCapturingSmile) ...[
                                          const SizedBox(height: 8),
                                          LinearProgressIndicator(
                                            value: _smileDetectionProgress,
                                            backgroundColor: Colors.white30,
                                            color: Colors.white,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),

                              // Face detection info
                              if (_isSmileDetectionActive &&
                                  smilingProbability != null)
                                Positioned(
                                  bottom: 80,
                                  left: 20,
                                  right: 20,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Smile Level: ${(smilingProbability! * 100).toStringAsFixed(1)}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Action Buttons
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(18),
                              bottomRight: Radius.circular(18),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Skip Button
                              TextButton.icon(
                                onPressed: () {
                                  _stopSmileDetection();
                                  Navigator.of(context).pop();
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder:
                                          (context) =>
                                              VictoryPage(smileImagePath: ''),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.skip_next,
                                  color: Colors.white70,
                                ),
                                label: const Text(
                                  'Skip',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),

                              // Start/Stop Detection Button
                              ElevatedButton.icon(
                                onPressed: () {
                                  if (_isSmileDetectionActive) {
                                    _stopSmileDetection();
                                    setState(() {});
                                  } else {
                                    _startSmileDetection(setState);
                                  }
                                },
                                icon: Icon(
                                  _isSmileDetectionActive
                                      ? Icons.stop
                                      : Icons.play_arrow,
                                ),
                                label: Text(
                                  _isSmileDetectionActive ? 'Stop' : 'Mulai',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      _isSmileDetectionActive
                                          ? Colors.red
                                          : Colors.greenAccent,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  void _startSmileDetection(StateSetter dialogSetState) {
    _isSmileDetectionActive = true;
    _isCapturingSmile = false;
    _smileDetectionProgress = 0.0;
    _smileDetectionStartTime = null;

    dialogSetState(() {});

    // Start camera stream untuk deteksi senyum
    if (_cameraService.isInitialized) {
      _cameraService.cameraController.startImageStream((CameraImage image) {
        if (_isSmileDetectionActive && !isDetecting) {
          isDetecting = true;
          _processSmileDetection(image, dialogSetState).then((_) {
            isDetecting = false;
          });
        }
      });
    }
  }

  Future<void> _processSmileDetection(
    CameraImage image,
    StateSetter dialogSetState,
  ) async {
    if (!_isSmileDetectionActive) return;

    final inputImage = _cameraService.getInputImageFromCameraImage(image);
    final faces = await _faceDetectorService.processImage(inputImage);

    if (!mounted || !_isSmileDetectionActive) return;

    dialogSetState(() {
      if (faces.isNotEmpty) {
        final face = faces.first;
        smilingProbability = face.smilingProbability;

        // Check if smiling (threshold bisa disesuaikan)
        bool isSmiling = (smilingProbability ?? 0) > 0.7;

        if (isSmiling) {
          if (_smileDetectionStartTime == null) {
            // Mulai timer senyum
            _smileDetectionStartTime = DateTime.now();
            _isCapturingSmile = true;
            _startSmileDetectionTimer(dialogSetState);
          } else {
            // Update progress
            final elapsed = DateTime.now().difference(
              _smileDetectionStartTime!,
            );
            _smileDetectionProgress = (elapsed.inMilliseconds /
                    _smileHoldDuration.inMilliseconds)
                .clamp(0.0, 1.0);

            if (elapsed >= _smileHoldDuration) {
              // Senyum cukup lama, ambil foto
              _captureSmileFromDetection(dialogSetState);
            }
          }
        } else {
          // Tidak tersenyum, reset timer
          _resetSmileDetectionTimer();
          _isCapturingSmile = false;
          _smileDetectionProgress = 0.0;
        }
      } else {
        // Tidak ada wajah terdeteksi
        _resetSmileDetectionTimer();
        _isCapturingSmile = false;
        _smileDetectionProgress = 0.0;
        smilingProbability = null;
      }
    });
  }

  void _startSmileDetectionTimer(StateSetter dialogSetState) {
    _smileDetectionTimer?.cancel();
    _smileDetectionTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (_smileDetectionStartTime != null && _isSmileDetectionActive) {
        final elapsed = DateTime.now().difference(_smileDetectionStartTime!);
        final progress = (elapsed.inMilliseconds /
                _smileHoldDuration.inMilliseconds)
            .clamp(0.0, 1.0);

        dialogSetState(() {
          _smileDetectionProgress = progress;
        });

        if (elapsed >= _smileHoldDuration) {
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  void _resetSmileDetectionTimer() {
    _smileDetectionStartTime = null;
    _smileDetectionTimer?.cancel();
    _smileDetectionProgress = 0.0;
  }

  Future<void> _captureSmileFromDetection(StateSetter dialogSetState) async {
    try {
      // First stop detection without stopping stream
      _isSmileDetectionActive = false;
      _isCapturingSmile = false;
      _resetSmileDetectionTimer();

      dialogSetState(() {
        _isCapturingSmile = true;
      });

      if (_cameraService.isInitialized) {
        try {
          await _cameraService.cameraController.stopImageStream();
        } catch (e) {
          print('Stream may already be stopped: $e');
        }
      }

      final picture = await _cameraService.cameraController.takePicture();

      final tempDir = await getTemporaryDirectory();
      final fileName = 'smile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final smilePath = '${tempDir.path}/$fileName';
      await picture.saveTo(smilePath);

      _smilePhotoPath = smilePath;

      if (mounted) {
        // Tutup dialog dan ke VictoryPage
        debugPrint("smilePath: $_smilePhotoPath");
        Navigator.of(context).pop();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => VictoryPage(smileImagePath: _smilePhotoPath!),
          ),
        );
      }
    } catch (e) {
      print('Error capturing smile: $e');
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal mengambil foto senyum'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => VictoryPage(smileImagePath: ''),
          ),
        );
      }
    }
  }

  // 9. Stop smile detection
  void _stopSmileDetection() {
    _isSmileDetectionActive = false;
    _isCapturingSmile = false;
    _resetSmileDetectionTimer();

    if (_cameraService.isInitialized) {
      try {
        _cameraService.cameraController.stopImageStream();
      } catch (e) {
        print('Error stopping stream: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Set up game completion callback
    _gameService.onGameCompleted = () {
      print('[UI] Game completion callback triggered');
      _finishGame();
    };
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _cameraService.initializeCamera();
    if (mounted) {
      setState(() {});
      _startGame();
    }
  }

  void _startGame() {
    _gameService.startCountdown(
      (value) {
        setState(() {
          instructionText = value.toString();
          instructionIcon = const Icon(Icons.timer);
          instructionColor = Colors.amberAccent;
        });
      },
      () {
        setState(() {
          instructionText = _gameService.requiredExpression.instructionText;
          instructionIcon = _gameService.requiredExpression.expressionImage;
          instructionColor = Colors.white;
        });
        _startFaceDetection();
      },
    );
  }

  void _startFaceDetection() {
    if (_cameraService.isInitialized) {
      _cameraService.cameraController.startImageStream((CameraImage image) {
        // Add strict check for round pause to prevent any detection during jeda
        if (!isDetecting &&
            _gameService.isGameStarted &&
            !_gameService.isGameFinished &&
            !_isInRoundPause) {
          // This prevents detection during round pause
          isDetecting = true;
          _processCameraImage(image).then((_) {
            isDetecting = false;
          });
        }
      });
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    // Early return if in round pause - no processing at all
    if (_isInRoundPause) {
      return;
    }

    final inputImage = _cameraService.getInputImageFromCameraImage(image);
    final faces = await _faceDetectorService.processImage(inputImage);

    if (!mounted) return;

    setState(() {
      if (faces.isNotEmpty && !_isInRoundPause) {
        // Double check round pause
        final face = faces.first;
        smilingProbability = face.smilingProbability;
        leftEyeOpenProbability = face.leftEyeOpenProbability;
        rightEyeOpenProbability = face.rightEyeOpenProbability;
        headEulerAngleY = face.headEulerAngleY;
        headEulerAngleZ = face.headEulerAngleZ;

        // Calculate landmark-based metrics
        mouthCornerRatio = _calculateMouthCornerRatio(face);
        eyebrowEyeRatio = _calculateEyebrowEyeRatio(face);
        mouthAspectRatio = _calculateMouthAspectRatio(face);

        // Debug logging for neutral expression calibration
        if (_gameService.requiredExpression == GameExpression.netral) {
          print(
            '[Debug Neutral] Smile: ${smilingProbability?.toStringAsFixed(3)} | '
            'Eyes: L${leftEyeOpenProbability?.toStringAsFixed(3)} R${rightEyeOpenProbability?.toStringAsFixed(3)} | '
            'Mouth Ratio: ${mouthAspectRatio?.toStringAsFixed(3)} | '
            'Corner Ratio: ${mouthCornerRatio?.toStringAsFixed(3)}',
          );
        }

        currentDetectedExpression = _faceDetectorService
            .getCurrentDetectedExpression(face);
        _checkExpression(face);
      } else {
        // Clear values when no face detected or during round pause
        _clearFaceMetrics();
        if (!_isInRoundPause) {
          instructionText = 'Wajah tidak terdeteksi!';
          instructionColor = Colors.red;
          instructionIcon = const Icon(Icons.face_retouching_off);
        }
      }
    });
  }

  // Enhanced method to clear all face metrics completely
  void _clearFaceMetrics() {
    smilingProbability = null;
    leftEyeOpenProbability = null;
    rightEyeOpenProbability = null;
    headEulerAngleY = null;
    headEulerAngleZ = null;
    mouthCornerRatio = null;
    eyebrowEyeRatio = null;
    mouthAspectRatio = null;
    currentDetectedExpression = null;
  }

  double? _calculateMouthCornerRatio(Face face) {
    final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;
    final bottomMouth = face.landmarks[FaceLandmarkType.bottomMouth]?.position;

    if (leftMouth == null || rightMouth == null || bottomMouth == null) {
      return null;
    }

    final mouthWidth = (rightMouth.x - leftMouth.x).abs();
    final leftCornerHeight = (leftMouth.y - bottomMouth.y).abs();
    final rightCornerHeight = (rightMouth.y - bottomMouth.y).abs();
    final avgCornerHeight = (leftCornerHeight + rightCornerHeight) / 2;

    return mouthWidth / (avgCornerHeight + 1);
  }

  double? _calculateEyebrowEyeRatio(Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final leftCheek = face.landmarks[FaceLandmarkType.leftCheek]?.position;
    final rightCheek = face.landmarks[FaceLandmarkType.rightCheek]?.position;

    if (leftEye == null ||
        rightEye == null ||
        leftCheek == null ||
        rightCheek == null) {
      return null;
    }

    final eyeDistance = (rightEye.x - leftEye.x).abs();
    final cheekDistance = (rightCheek.x - leftCheek.x).abs();

    return eyeDistance / cheekDistance;
  }

  double? _calculateMouthAspectRatio(Face face) {
    final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;
    final bottomMouth = face.landmarks[FaceLandmarkType.bottomMouth]?.position;
    final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;

    if (leftMouth == null ||
        rightMouth == null ||
        bottomMouth == null ||
        noseBase == null) {
      return null;
    }

    final mouthWidth = (rightMouth.x - leftMouth.x).abs();
    final mouthHeight = (bottomMouth.y - noseBase.y).abs();

    return mouthHeight / mouthWidth;
  }

  void _checkExpression(Face face) async {
    // Absolutely no expression checking during round pause
    if (_isInRoundPause) {
      return;
    }

    bool expressionMatched = _faceDetectorService.matchesExpression(
      face,
      _gameService.requiredExpression,
    );

    if (expressionMatched) {
      if (_expressionStartTime == null) {
        // Start timing the expression
        _expressionStartTime = DateTime.now();
        _startExpressionTimer();
        setState(() {
          instructionText = 'Tahan ekspresi ini selama 2 detik...';
          instructionColor = Colors.orangeAccent;
        });
      } else {
        // Update progress
        final elapsed = DateTime.now().difference(_expressionStartTime!);
        final progress =
            elapsed.inMilliseconds / _requiredHoldDuration.inMilliseconds;

        setState(() {
          _expressionProgress = progress.clamp(0.0, 1.0);
        });

        if (elapsed >= _requiredHoldDuration && !_isExpressionValid) {
          _isExpressionValid = true;
          _expressionTimer?.cancel();
          setState(() {
            instructionText = 'Sempurna! 😊';
            instructionColor = Colors.greenAccent;
            _expressionProgress = 1.0;
          });
          // Tambahan: Capture foto jika ekspresi senyum
          if (_gameService.requiredExpression == GameExpression.senyum) {
            await _captureSmilePhotoAndNavigate();
          } else {
            _nextExpression();
          }
        }
      }
    } else {
      // Expression doesn't match, reset timer
      _resetExpressionTimer();
      setState(() {
        instructionText = _getInstructionForExpression(
          _gameService.requiredExpression,
        );
        instructionColor = Colors.white;
        _expressionProgress = 0.0;
      });
    }

    // Always update the icon based on required expression
    instructionIcon = _gameService.requiredExpression.expressionImage;
  }

  Future<void> _captureSmilePhotoAndNavigate() async {
    try {
      // Stop image stream sebelum capture
      await _cameraService.cameraController.stopImageStream();
      final picture = await _cameraService.cameraController.takePicture();
      // Simpan ke temporary directory
      final tempDir = await getTemporaryDirectory();
      final fileName = 'smile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final smilePath = '${tempDir.path}/$fileName';
      await picture.saveTo(smilePath);
      // Simpan path ke variabel, JANGAN navigasi ke VictoryPage di sini
      _smilePhotoPath = smilePath;
      // Mulai ulang stream kamera untuk ronde berikutnya
      await _cameraService.cameraController.startImageStream((
        CameraImage image,
      ) {
        if (!isDetecting &&
            _gameService.isGameStarted &&
            !_gameService.isGameFinished &&
            !_isInRoundPause) {
          isDetecting = true;
          _processCameraImage(image).then((_) {
            isDetecting = false;
          });
        }
      });
      // Lanjut ke ekspresi berikutnya
      _nextExpression();
    } catch (e) {
      print('Error capturing smile photo: $e');
      // Jika gagal, lanjutkan ke ekspresi berikutnya
      _nextExpression();
    }
  }

  void _startExpressionTimer() {
    _expressionTimer?.cancel();
    _expressionTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (_expressionStartTime != null) {
        final elapsed = DateTime.now().difference(_expressionStartTime!);
        final progress =
            elapsed.inMilliseconds / _requiredHoldDuration.inMilliseconds;

        setState(() {
          _expressionProgress = progress.clamp(0.0, 1.0);
        });

        if (elapsed >= _requiredHoldDuration) {
          timer.cancel();
        }
      }
    });
  }

  void _resetExpressionTimer() {
    _expressionStartTime = null;
    _isExpressionValid = false;
    _expressionTimer?.cancel();
    _expressionProgress = 0.0;
  }

  void _nextExpression() {
    print('[UI] _nextExpression() called');
    bool gameFinished = _gameService.nextExpression();

    print('[UI] Game finished: $gameFinished');

    if (gameFinished) {
      print('[UI] Calling _finishGame()');
      _finishGame();
      return;
    }

    // Immediately start round pause and completely reset all values
    _isInRoundPause = true;
    _resetExpressionTimer();

    // Force clear all face detection values immediately
    _clearFaceMetrics();

    print(
      '[Round Pause] Entering jeda antar ronde - all detection stopped and values cleared',
    );

    // Update UI for round transition
    setState(() {
      instructionText = 'Bersiap untuk ekspresi berikutnya...';
      instructionColor = Colors.yellowAccent;
      instructionIcon = const Icon(Icons.timer, color: Colors.yellowAccent);
    });

    // Cancel any existing timer before starting new one
    _roundPauseTimer?.cancel();

    // Pause before next round with proper duration
    _roundPauseTimer = Timer(_roundPauseDuration, () {
      if (mounted && !_gameService.isGameFinished) {
        print('[Round Pause] Ending jeda antar ronde - detection can resume');

        _isInRoundPause = false;

        // Clear metrics one more time to ensure clean state
        _clearFaceMetrics();

        setState(() {
          instructionText = _getInstructionForExpression(
            _gameService.requiredExpression,
          );
          instructionColor = Colors.white;
          instructionIcon = _gameService.requiredExpression.expressionImage;
        });
      }
    });
  }

  void _finishGame() {
    print('[UI] _finishGame() called');

    // Check if already finished to prevent multiple dialogs
    if (_gameService.isGameFinished) {
      print('[UI] Game already finished, dialog might already be showing');
    }

    // Force set game as finished
    _gameService.isGameFinished = true;

    // Stop camera stream properly
    if (_cameraService.isInitialized) {
      try {
        _cameraService.cameraController.stopImageStream();
        print('[UI] Camera stream stopped');
      } catch (e) {
        print('[UI] Error stopping camera stream: $e');
      }
    }

    // Cancel all timers
    _resetExpressionTimer();
    _roundPauseTimer?.cancel();
    _isInRoundPause = false;

    // Show completion dialog immediately
    print('[UI] Showing completion dialog');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF667eea),
                        Color(0xFF764ba2),
                        Color(0xFFf093fb),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '🎉 Game Selesai! 🎉',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    '🏆 SELAMAT! 🏆',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Anda telah menyelesaikan semua ${_gameService.totalRounds} ronde!',
                                    style: const TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '⏱️ Waktu total: ${_gameService.elapsedTimeInSeconds} detik',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '📊 Rata-rata per ronde: ${(_gameService.elapsedTimeInSeconds / _gameService.totalRounds).toStringAsFixed(1)} detik',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Main Lagi Button
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _resetGame();
                                  },
                                  icon: const Icon(
                                    Icons.refresh,
                                    color: Color(0xFFf093fb),
                                  ),
                                  label: const Text(
                                    'Main Lagi',
                                    style: TextStyle(
                                      color: Color(0xFFf093fb),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.white.withOpacity(
                                      0.12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                                // Victory & Share Button
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    if (_smilePhotoPath != null &&
                                        _smilePhotoPath!.isNotEmpty) {
                                      Navigator.of(context).pushReplacement(
                                        MaterialPageRoute(
                                          builder:
                                              (context) => VictoryPage(
                                                smileImagePath:
                                                    _smilePhotoPath!,
                                              ),
                                        ),
                                      );
                                    } else {
                                      _showSmileDetectionDialog();
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.share,
                                    color: Colors.greenAccent,
                                  ),
                                  label: const Text(
                                    'Victory & Share',
                                    style: TextStyle(
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    backgroundColor: Colors.white.withOpacity(
                                      0.12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Home Button di bawah sendiri
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).pop();
                                  Navigator.of(context).pop();
                                },
                                icon: const Icon(
                                  Icons.home,
                                  color: Colors.white70,
                                ),
                                label: const Text(
                                  'Home',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.white.withOpacity(
                                    0.10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        );
      }
    });
  }

  void _resetGame() {
    Navigator.of(context).pop(); // Close the dialog

    // Stop camera stream completely before reset
    if (_cameraService.isInitialized) {
      try {
        _cameraService.cameraController.stopImageStream();
        print('[Game Reset] Camera stream stopped');
      } catch (e) {
        print('[Game Reset] Error stopping camera stream: $e');
      }
    }

    // Cancel all timers and reset all states completely
    _resetExpressionTimer();
    _roundPauseTimer?.cancel();
    _isInRoundPause = false;

    // Force clear all face detection values
    _clearFaceMetrics();

    // Reset game service completely
    _gameService.resetGame();

    print('[Game Reset] All values cleared and timers cancelled');

    setState(() {
      // Reset all UI state
      isDetecting = false;
      instructionText = 'Bersiaplah!';
      instructionColor = Colors.white;
      instructionIcon = const Icon(Icons.timer, color: Colors.amberAccent);
      _expressionProgress = 0.0;
    });

    // Small delay to ensure camera is properly stopped before restart
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _startGame();
      }
    });
  }

  // ini

  @override
  void dispose() {
    _expressionTimer?.cancel();
    _roundPauseTimer?.cancel();
    _smileDetectionTimer?.cancel();
    _gameService.dispose();
    _faceDetectorService.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF667eea), Color(0xFF764ba2), Color(0xFFf093fb)],
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            toolbarHeight: 80,
            centerTitle: true,
            elevation: 0,
            title: const Text(
              "Tantangan Ekspresi",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 24,
                letterSpacing: 1.2,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (currentDetectedExpression != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Center(
                    child: Text(
                      'Waktu: ${_gameService.elapsedTimeInSeconds}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      body:
          _cameraService.isInitialized
              ? Stack(
                children: [
                  // Camera Preview
                  Positioned.fill(
                    child: AspectRatio(
                      aspectRatio:
                          _cameraService.cameraController.value.aspectRatio,
                      child: CameraPreview(_cameraService.cameraController),
                    ),
                  ),

                  // Progress Indicator
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value:
                          _gameService.isGameStarted
                              ? (_gameService.completedRounds /
                                  _gameService.totalRounds)
                              : 0,
                      backgroundColor: Colors.grey.shade800,
                      color: Colors.greenAccent,
                      minHeight: 10,
                    ),
                  ),

                  // Instruction Panel
                  Positioned(
                    top: 60,
                    left: 0,
                    right: 0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF1A0033),
                                Color(0xFF320040),
                                Color(0xFF00354D),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: instructionIcon,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  instructionText,
                                  style: TextStyle(
                                    color: instructionColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Expression Progress Indicator (new)
                  if (_expressionStartTime != null && !_isInRoundPause)
                    Positioned(
                      top: 140,
                      left: 0,
                      right: 0,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          children: [
                            Text(
                              'Tahan ekspresi: ${(_expressionProgress * 100).toInt()}%',
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: _expressionProgress,
                              backgroundColor: Colors.grey.shade800,
                              color: Colors.orangeAccent,
                              minHeight: 8,
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Round Pause Indicator (new)
                  if (_isInRoundPause)
                    Positioned(
                      top: 140,
                      left: 0,
                      right: 0,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.yellowAccent,
                            width: 2,
                          ),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.pause_circle_filled,
                              color: Colors.yellowAccent,
                              size: 32,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Jeda antar ronde...',
                              style: TextStyle(
                                color: Colors.yellowAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Face Metrics Panel - completely hidden during round pause
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Round ${_gameService.completedRounds + 1} of ${_gameService.totalRounds}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_isInRoundPause) ...[
                            const SizedBox(height: 4),
                            const Text(
                              '⏸️ Jeda antar ronde - Tidak ada deteksi',
                              style: TextStyle(
                                color: Colors.yellowAccent,
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const Text(
                              'Semua nilai landmark direset',
                              style: TextStyle(
                                color: Colors.yellow,
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                          // Only show face metrics when NOT in round pause AND values exist
                          if (!_isInRoundPause &&
                              smilingProbability != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Smile: ${(smilingProbability! * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(color: Colors.white),
                            ),
                            Text(
                              'Left Eye: ${(leftEyeOpenProbability! * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'Right Eye: ${(rightEyeOpenProbability! * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (!_isInRoundPause && mouthCornerRatio != null) ...[
                            Text(
                              'Mouth Ratio: ${mouthCornerRatio!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (!_isInRoundPause && eyebrowEyeRatio != null) ...[
                            Text(
                              'Eyebrow Ratio: ${eyebrowEyeRatio!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (!_isInRoundPause && mouthAspectRatio != null) ...[
                            Text(
                              'Mouth Aspect: ${mouthAspectRatio!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          // Debug info for current detection - only when not in pause
                          if (!_isInRoundPause &&
                              _gameService.requiredExpression ==
                                  GameExpression.netral &&
                              currentDetectedExpression != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Target: NEUTRAL | Current: ${_getExpressionName(currentDetectedExpression!)}',
                              style: const TextStyle(
                                color: Colors.cyan,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              )
              : const Center(
                child: CircularProgressIndicator(color: Colors.amberAccent),
              ),
    );
  }

  String _getInstructionForExpression(GameExpression expression) {
    switch (expression) {
      case GameExpression.senyum:
        return 'Tunjukkan senyum terbaik Anda! 😊';
      case GameExpression.netral:
        return 'Buat wajah netral (tanpa ekspresi)';
      case GameExpression.marah:
        return 'Tunjukkan ekspresi marah! 😠';
      case GameExpression.sedih:
        return 'Tunjukkan ekspresi sedih 😢';
      case GameExpression.kaget:
        return 'Tunjukkan ekspresi kaget! 😲';
      case GameExpression.ngantuk:
        return 'Tunjukkan ekspresi ngantuk 😴';
    }
  }

  String _getExpressionName(GameExpression expression) {
    switch (expression) {
      case GameExpression.senyum:
        return 'Senyum';
      case GameExpression.netral:
        return 'Netral';
      case GameExpression.marah:
        return 'Marah';
      case GameExpression.sedih:
        return 'Sedih';
      case GameExpression.kaget:
        return 'Kaget';
      case GameExpression.ngantuk:
        return 'Ngantuk';
    }
  }
}
