import 'package:flutter/material.dart';
import 'screens/auto_login_page.dart';
import 'controllers/webview_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WebViewControllerManager.initialize();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AutoLoginPage(),
    ),
  );
}
