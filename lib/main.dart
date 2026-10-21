import 'package:flutter/material.dart';
import 'data/local_store.dart';
import 'domain/app_controller.dart';
import 'ui/auth_page.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AttendanceApp(controller: AppController(LocalStore())));
}

class AttendanceApp extends StatefulWidget {
  final AppController controller;
  const AttendanceApp({super.key, required this.controller});
  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  late Future<void> ready;
  @override
  void initState() {
    super.initState();
    ready = widget.controller.load();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chấm công • Tống Nhật Bảo An',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087F8C)),
      scaffoldBackgroundColor: const Color(0xFFF3F6FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF3F6FA),
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDCE4ED)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ),
    home: FutureBuilder<void>(
      future: ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const Text(
                      'Không đọc được dữ liệu. Dữ liệu hiện có chưa bị xóa.',
                    ),
                    Text('${snapshot.error}'),
                    TextButton(
                      onPressed: () =>
                          setState(() => ready = widget.controller.load()),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return ListenableBuilder(
          listenable: widget.controller,
          builder: (_, _) => widget.controller.user == null
              ? AuthPage(controller: widget.controller)
              : HomePage(controller: widget.controller),
        );
      },
    ),
  );
}
