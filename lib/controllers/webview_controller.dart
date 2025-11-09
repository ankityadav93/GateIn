import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewControllerManager {
  static late final WebViewController globalController;

  static Future<void> initialize() async {
    globalController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..setBackgroundColor(Colors.white);
  }
}