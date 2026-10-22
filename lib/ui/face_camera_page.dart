import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../data/capture_cleanup.dart';

Future<T?> showFaceCamera<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function(String image) onCapture,
}) => Navigator.of(context).push<T>(
  MaterialPageRoute(
    builder: (_) => FaceCameraPage<T>(title: title, onCapture: onCapture),
  ),
);

/// Front-camera preview stays open on failed verification so users can retry.
/// The oval is a positioning guide; only the backend decides identity matches.
class FaceCameraPage<T> extends StatefulWidget {
  final String title;
  final Future<T> Function(String image) onCapture;
  const FaceCameraPage({
    super.key,
    required this.title,
    required this.onCapture,
  });
  @override
  State<FaceCameraPage<T>> createState() => _FaceCameraPageState<T>();
}

class _FaceCameraPageState<T> extends State<FaceCameraPage<T>>
    with WidgetsBindingObserver {
  CameraController? _camera;
  bool _starting = false;
  bool _busy = false;
  bool _active = true;
  bool _restartAfterInit = false;
  int _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _release(CameraController? camera) async {
    try {
      await camera?.dispose();
    } catch (_) {
      /* Device may already be closed. */
    }
  }

  Future<void> _initialize() async {
    if (_starting || !mounted || !_active) return;
    final generation = ++_generation;
    setState(() {
      _starting = true;
      _error = null;
    });
    CameraController? pending;
    try {
      final old = _camera;
      _camera = null;
      await _release(old);
      final cameras = await availableCameras();
      final front = cameras
          .where((c) => c.lensDirection == CameraLensDirection.front)
          .firstOrNull;
      if (front == null) {
        throw CameraException(
          'NoFrontCamera',
          'Không tìm thấy camera trước trên thiết bị này.',
        );
      }
      pending = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await pending.initialize();
      try {
        await pending.setJpegImageQuality(85);
      } on CameraException {
        /* Device default quality is usable. */
      }
      if (!mounted || !_active || generation != _generation) return;
      _camera = pending;
      pending = null;
    } on CameraException catch (e) {
      if (mounted && generation == _generation) {
        _error = e.code.contains('Access') || e.code.contains('Permission')
            ? 'Chưa có quyền camera. Cấp quyền Camera trong Cài đặt ứng dụng, rồi thử lại.'
            : e.description ??
                  'Không mở được camera trước. Đóng ứng dụng đang dùng camera và thử lại.';
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        _error = 'Không mở được camera. Hãy thử lại trên điện thoại thật.';
      }
    } finally {
      await _release(pending);
      if (mounted) {
        setState(() => _starting = false);
        if (_restartAfterInit && _active) {
          _restartAfterInit = false;
          unawaited(_initialize());
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active = true;
      if (_starting) {
        _restartAfterInit = true;
      } else {
        unawaited(_initialize());
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _active = false;
      _generation++;
      final camera = _camera;
      _camera = null;
      unawaited(_release(camera));
      if (mounted) setState(() {});
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (_busy ||
        _starting ||
        !_active ||
        camera == null ||
        !camera.value.isInitialized) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await camera.takePicture();
      final bytes = await image.readAsBytes().whenComplete(
        () => discardCameraCapture(image.path),
      );
      if (bytes.isEmpty || bytes.length > 3 * 1024 * 1024) {
        throw StateError('Ảnh không hợp lệ hoặc lớn hơn 3 MB. Hãy chụp lại.');
      }
      if (!mounted || !_active) return;
      final result = await widget.onCapture(base64Encode(bytes));
      if (mounted && _active) Navigator.of(context).pop<T>(result);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().replaceFirst(
            RegExp(r'^(Bad state: |Exception: )'),
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _active = false;
    unawaited(_release(_camera));
    _camera = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final ready = camera != null && camera.value.isInitialized && _active;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1D26),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF0D1D26),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Text(
                'Nhìn thẳng vào camera, đặt khuôn mặt trong khung và giữ máy ổn định. Chỉ một người trong ảnh.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, height: 1.5),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  alignment: Alignment.center,
                  children: [
                    if (ready)
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: CameraPreview(camera),
                        ),
                      )
                    else if (_starting)
                      const CircularProgressIndicator(color: Colors.white)
                    else
                      const Icon(
                        Icons.videocam_off_outlined,
                        color: Colors.white54,
                        size: 72,
                      ),
                    if (ready)
                      IgnorePointer(
                        child: Container(
                          width: math.min(constraints.maxWidth * .68, 270),
                          height: math.min(constraints.maxHeight * .8, 350),
                          decoration: BoxDecoration(
                            shape: BoxShape.rectangle,
                            borderRadius: BorderRadius.circular(180),
                            border: Border.all(
                              color: _busy
                                  ? Colors.amber
                                  : const Color(0xFF5EEAD4),
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(
                  140,
                  MediaQuery.sizeOf(context).height * .42,
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFECACA)),
                        ),
                      ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Đang xử lý ảnh…',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: !ready || _busy ? null : _capture,
                      icon: const Icon(Icons.face_retouching_natural),
                      label: const Text('Chụp & tiếp tục'),
                    ),
                    if ((!ready && !_starting) || (_error != null && !_busy))
                      OutlinedButton(
                        onPressed: _initialize,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Mở lại camera'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      child: const Text('Hủy và quay lại'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
