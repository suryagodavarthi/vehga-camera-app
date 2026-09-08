import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_menu_screen.dart';
import 'screens/login_screen.dart';
import 'services/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait by default; capture screens switch to landscape themselves.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const VehgaCameraApp());
}

class VehgaCameraApp extends StatelessWidget {
  const VehgaCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vehga Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Slate rather than the Vehga teal. The app is Vehga's — the wordmark
        // says so — but the cases it handles belong to either company, so
        // nothing in the UI colour should suggest which one a job is filed
        // under. Captures themselves carry no company mark at all; see
        // [WatermarkService].
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF455A64)),
        useMaterial3: true,
      ),
      home: const _StartupGate(),
    );
  }
}

/// Sends returning agencies straight to the home menu; others to login.
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Session?>(
      future: Session.load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data == null
            ? const LoginScreen()
            : const HomeMenuScreen();
      },
    );
  }
}
