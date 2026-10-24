import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/ui/face_camera_page.dart';

class FakeCamera extends CameraPlatform {
  int created = 0;
  int disposed = 0;
  int captures = 0;
  bool noFront = false;
  bool denied = false;
  final errors = StreamController<CameraErrorEvent>.broadcast();
  @override
  Future<List<CameraDescription>> availableCameras() async {
    if (denied) {
      throw CameraException('CameraAccessDenied', 'Permission denied');
    }
    return noFront
        ? []
        : [
            const CameraDescription(
              name: 'front',
              lensDirection: CameraLensDirection.front,
              sensorOrientation: 90,
            ),
          ];
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings settings,
  ) async {
    expectSync(settings.enableAudio, isFalse);
    return ++created;
  }

  @override
  Future<void> initializeCamera(
    int id, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int id) => Stream.value(
    CameraInitializedEvent(
      id,
      640,
      480,
      ExposureMode.auto,
      true,
      FocusMode.auto,
      true,
    ),
  );
  @override
  Stream<CameraErrorEvent> onCameraError(int id) => errors.stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Future<void> setJpegImageQuality(int id, int quality) async {}
  @override
  Widget buildPreview(int id) => const ColoredBox(color: Colors.black);
  @override
  Future<void> dispose(int id) async {
    disposed++;
  }

  @override
  Future<XFile> takePicture(int id) async {
    captures++;
    return XFile.fromData(
      Uint8List.fromList([255, 216, ...List.filled(200, 0)]),
      mimeType: 'image/jpeg',
    );
  }
}

void main() {
  late CameraPlatform original;
  late FakeCamera fake;
  setUp(() {
    original = CameraPlatform.instance;
    fake = FakeCamera();
    CameraPlatform.instance = fake;
  });
  tearDown(() {
    CameraPlatform.instance = original;
  });

  Future<void> open(
    WidgetTester tester,
    Future<String> Function(String) verify,
    void Function(String?) result,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result(
                await showFaceCamera<String>(
                  context,
                  title: 'Camera test',
                  onCapture: verify,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Wrong face keeps preview open and correct retry returns proof', (
    tester,
  ) async {
    var attempts = 0;
    String? result;
    await open(tester, (_) async {
      attempts++;
      if (attempts == 1) throw StateError('Face mismatch');
      return 'proof';
    }, (v) => result = v);
    await tester.tap(find.text('Chụp & tiếp tục'));
    await tester.pumpAndSettle();
    expect(find.text('Face mismatch'), findsOneWidget);
    expect(find.byType(CameraPreview), findsOneWidget);
    await tester.tap(find.text('Chụp & tiếp tục'));
    await tester.pumpAndSettle();
    expect(result, 'proof');
    expect(fake.captures, 2);
    expect(fake.disposed, 1);
  });

  testWidgets('Cancel during verification never returns its late success', (
    tester,
  ) async {
    final response = Completer<String>();
    String? result = 'not-returned';
    await open(tester, (_) => response.future, (v) => result = v);
    await tester.tap(find.text('Chụp & tiếp tục'));
    await tester.pump();
    await tester.tap(find.text('Hủy và quay lại'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    response.complete('late-proof');
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Permission refusal does not invoke verification', (
    tester,
  ) async {
    fake.denied = true;
    var calls = 0;
    await open(tester, (_) async {
      calls++;
      return 'proof';
    }, (_) {});
    expect(find.textContaining('Chưa có quyền camera'), findsOneWidget);
    expect(calls, 0);
    expect(fake.captures, 0);
  });

  testWidgets('Camera is released in background and reopened on resume', (
    tester,
  ) async {
    await open(tester, (_) async => 'proof', (_) {});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(fake.disposed, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fake.created, 2);
    expect(find.byType(CameraPreview), findsOneWidget);
    await tester.tap(find.text('Hủy và quay lại'));
    await tester.pumpAndSettle();
    expect(fake.disposed, 2);
  });
}
