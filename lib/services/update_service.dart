import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class UpdateService {
  static const _ignoredKey = 'ignored_update_version';

  // GitHub update.json
  static const _updateJsonUrl =
      'https://raw.githubusercontent.com/ankityadav93/gatein/main/update.json';

  final BuildContext context;
  UpdateService(this.context);

  // ------------------------------
  // MAIN CHECK FUNCTION
  // ------------------------------
  Future<void> checkAndPrompt({bool showIfUpToDate = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      final resp = await http.get(Uri.parse(_updateJsonUrl));
      if (resp.statusCode != 200) {
        if (showIfUpToDate) {
          _simpleDialog("Update Check Failed",
              "Unable to check for updates at this moment.");
        }
        return;
      }

      final data = jsonDecode(resp.body);
      final latest = data["latest_version"]?.toString();
      final apkUrl = data["apk_url"]?.toString();
      final changelog = data["changelog"]?.toString() ?? "";

      if (latest == null || apkUrl == null) return;

      // User ignored this version
      final ignored = prefs.getString(_ignoredKey);
      if (ignored == latest) return;

      // Not newer?
      if (!_isNewerVersion(currentVersion, latest)) {
        if (showIfUpToDate) {
          _simpleDialog("Up to Date", "You're on version $currentVersion.");
        }
        return;
      }

      // Show update dialog
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text("Update Available (v$latest)"),
          content: SingleChildScrollView(
            child: Text(changelog.isEmpty
                ? "A new update is available."
                : "Changelog:\n$changelog"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, "ignore"),
              child: const Text("Ignore"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, "later"),
              child: const Text("Later"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, "update"),
              child: const Text("Update"),
            ),
          ],
        ),
      );

      if (action == "ignore") {
        await prefs.setString(_ignoredKey, latest);
        return;
      }

      if (action == "update") {
        await _downloadAndInstall(apkUrl, latest);
      }
    } catch (e) {
      debugPrint("Update error: $e");
    }
  }

  // ------------------------------
  // VERSION COMPARISON
  // ------------------------------
  bool _isNewerVersion(String current, String latest) {
    try {
      final a = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final b = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final av = i < a.length ? a[i] : 0;
        final bv = i < b.length ? b[i] : 0;
        if (bv > av) return true;
        if (bv < av) return false;
      }
      return false;
    } catch (_) {
      return latest != current;
    }
  }

  // ------------------------------
  // DOWNLOAD + INSTALL
  // ------------------------------
  Future<void> _downloadAndInstall(String apkUrl, String version) async {
    // Storage permission for Android <= 10
    if (Platform.isAndroid) {
      if (await _requiresStoragePermission()) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          _simpleDialog("Permission Required",
              "Storage permission is required to download updates.");
          return;
        }
      }
    }

    final dir = await _getDownloadDirectory();
    if (dir == null) {
      _simpleDialog("Error", "Unable to access device storage.");
      return;
    }

    final filePath = "${dir.path}/GateIn_v$version.apk";

    final dio = Dio();
    final progress = _ProgressDialogController(context);

    try {
      await progress.show();

      await dio.download(
        apkUrl,
        filePath,
        onReceiveProgress: (received, total) {
          final percent =
              total > 0 ? ((received / total) * 100).toInt() : 0;
          progress.update(percent);
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: Duration.zero,
        ),
      );

      await progress.close();

      await _showInstallingDialog();

      // OPEN ANDROID INSTALLER (modern way)
      final result = await OpenFilex.open(filePath);

      if (result.type != ResultType.done) {
        _simpleDialog(
          "Install Failed",
          "Could not open installer.\nPlease install manually from:\n$filePath",
        );
      }

      // Delete APK after short delay
      Future.delayed(const Duration(seconds: 5), () async {
        final f = File(filePath);
        if (await f.exists()) await f.delete();
      });
    } catch (e) {
      await progress.close();
      _simpleDialog("Update Failed", "Download failed, please try again.");
      debugPrint("Download error: $e");
    }
  }

  Future<bool> _requiresStoragePermission() async {
    try {
      final version = (await _androidVersion()) ?? 30;
      return version <= 29;
    } catch (_) {
      return false;
    }
  }

  Future<int?> _androidVersion() async {
    try {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _getDownloadDirectory() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return await getApplicationDocumentsDirectory();

      final download = Directory("${dir.path}/Download");
      if (!await download.exists()) {
        await download.create(recursive: true);
      }
      return download;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------
  // SIMPLE DIALOG
  // ------------------------------
  void _simpleDialog(String title, String msg) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // ------------------------------
  // INSTALLING DIALOG
  // ------------------------------
  Future<void> _showInstallingDialog() async {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        title: Text("Installing update"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text("Preparing installer…"),
          ],
        ),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 600));
    if (context.mounted) Navigator.of(context).pop();
  }
}

// -------------------------------------
// PROGRESS DIALOG HANDLER
// -------------------------------------
class _ProgressDialogController {
  final BuildContext context;
  late _ProgressDialogState _state;

  _ProgressDialogController(this.context);

  Future<void> show() async {
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ProgressDialog(
        onReady: (state) => _state = state,
      ),
    );
  }

  void update(int percent) {
    if (_state.mounted) _state.update(percent);
  }

  Future<void> close() async {
    if (context.mounted) Navigator.pop(context);
  }
}

class _ProgressDialog extends StatefulWidget {
  final void Function(_ProgressDialogState) onReady;
  const _ProgressDialog({required this.onReady});

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  int percent = 0;

  @override
  void initState() {
    super.initState();
    widget.onReady(this);
  }

  void update(int p) {
    if (mounted) {
      setState(() => percent = p.clamp(0, 100));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Downloading update…"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: percent / 100),
          const SizedBox(height: 10),
          Text("$percent%"),
        ],
      ),
    );
  }
}
