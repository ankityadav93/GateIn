import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../controllers/webview_controller.dart';
import '../services/storage_service.dart';
import '../services/network_service.dart';
import '../utils/javascript_injector.dart';
import '../utils/constants.dart';
import 'credentials_settings_page.dart';

// Added for OTA Update
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AutoLoginPage extends StatefulWidget {
  const AutoLoginPage({super.key});
  @override
  State<AutoLoginPage> createState() => _AutoLoginPageState();
}

class _AutoLoginPageState extends State<AutoLoginPage> with WidgetsBindingObserver {
  late final WebViewController _controller;
  late final StorageService _storageService;
  late final NetworkService _networkService;

  bool _isLoading = true;
  bool _readyToShow = false;
  bool _hasAttemptedCapture = false;
  bool _hasAttemptedAutoFill = false;

  String? _username;
  String? _password;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewControllerManager.globalController;
    _storageService = const StorageService(FlutterSecureStorage());
    _networkService = NetworkService();
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      try {
        final String? currentUrl = await _controller.currentUrl();
        final bool isLoggedIn = currentUrl != null &&
            (currentUrl.toLowerCase().contains("keepalive"));
        if (!isLoggedIn) {
          _initialize();
        }
      } catch (_) {
        _initialize();
      }
    }
  }

  Future<void> _initialize() async {
    _hasAttemptedCapture = false;
    _hasAttemptedAutoFill = false;

    _username = await _storageService.getUsername();
    _password = await _storageService.getPassword();

    const defaultUrl = "http://172.16.222.1:1000/login?";
    setState(() {
      _readyToShow = false;
      _isLoading = true;
    });

    await _controller.loadRequest(Uri.parse(defaultUrl));

    _networkService
        .detectLoginPortal()
        .timeout(AppConstants.portalDetectionTimeout)
        .then((newPortal) async {
      if (newPortal != null) {
        await _controller.loadRequest(Uri.parse(newPortal));
      }
    });

    await _injectEarlyScaling();
    Future.delayed(AppConstants.pageLoadDelay, () {
      if (mounted) setState(() => _readyToShow = true);
    });

    _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) {
          setState(() => _isLoading = true);
        },
        onPageFinished: (url) async {
          setState(() => _isLoading = false);
          await _forceCssZoom();
          await _detectSuccessAndMaybePromptSave();
          await _attemptAutoFillOnce();
        },
        onWebResourceError: (_) {},
      ),
    );

 
    _checkForUpdate(); // Check for updates after initialization
  }

  //OTA UPDATE SYSTEM START

  Future<void> _checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse('https://raw.githubusercontent.com/ankityadav93/gatein/main/update.json'),
      );

      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      final latest = data['latest_version'];
      final apkUrl = data['apk_url'];
      final changelog = data['changelog'] ?? '';

      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      if (latest != null && latest != current) {
        if (!mounted) return;
        final action = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Update Available'),
            content: Text(
              'New version $latest is available.\n\nChanges:\n$changelog',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'later'),
                child: const Text('Later'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'update'),
                child: const Text('Download & Install'),
              ),
            ],
          ),
        );

        if (action == 'update') {
          await _startOtaUpdate(apkUrl);
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  Future<void> _startOtaUpdate(String apkUrl) async {
    try {
      await for (final event in OtaUpdate().execute(
        apkUrl,
        destinationFilename: 'GateIn_latest.apk',
      )) {
        if (event.status == OtaStatus.DOWNLOADING) {
          debugPrint('Downloading: ${event.value}%');
        } else if (event.status == OtaStatus.INSTALLING) {
          debugPrint('Installing update...');
        } else if (event.status == OtaStatus.PERMISSION_NOT_GRANTED_ERROR) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Install permission denied')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('OTA update error: $e');
    }
  }

  // ↑↑↑ OTA UPDATE SYSTEM END ↑↑↑

  Future<void> _injectEarlyScaling() async {
    final double deviceWidth = MediaQuery.of(context).size.width;
    final js = JavaScriptInjector.getScalingScript(deviceWidth);
    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
  }

  Future<void> _forceCssZoom() async {
    final double w = MediaQuery.of(context).size.width;
    final js = JavaScriptInjector.getCssZoomScript(w);
    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
  }

  Future<void> _captureCredentialsFromForm() async {
    try {
      final Object? creds = await _controller.runJavaScriptReturningResult(
        JavaScriptInjector.getCredentialCaptureScript(),
      );

      if (creds == null) return;
      final String s = creds.toString();
      if (s.isEmpty || s == 'null' || s == '{}') return;

      final Map<String, dynamic> parsed = jsonDecode(s);
      final String? u = parsed['username'];
      final String? p = parsed['password'];

      if (u != null && u.trim().isNotEmpty) _username = u;
      if (p != null && p.isNotEmpty) _password = p;
    } catch (_) {}
  }

  Future<void> _attemptAutoFillOnce() async {
    if (_hasAttemptedAutoFill) {
      return;
    }
    try {
      if (_username == null || _password == null) {
        if (!_hasAttemptedCapture) {
          await _setupCredentialCapture();
          _hasAttemptedCapture = true;
        }
        return;
      }

      final Object? overLimit = await _controller.runJavaScriptReturningResult(
        JavaScriptInjector.getOverLimitCheckScript(),
      );
      if (overLimit?.toString().toLowerCase() == 'true') return;

      final Object? existsObj = await _controller.runJavaScriptReturningResult(
        JavaScriptInjector.getLoginFormExistsScript(),
      );

      final bool formExists =
          existsObj?.toString().toLowerCase() == 'true';

      if (formExists) {
        if (!_hasAttemptedCapture) {
          await _captureCredentialsFromForm();
          _hasAttemptedCapture = true;
        }

        _hasAttemptedAutoFill = true;
        await _autoFillAndSubmit();
      }
    } catch (_) {}
  }

  Future<void> _setupCredentialCapture() async {
    try {
      await _controller.runJavaScript('''
        (function(){
          if(window._credCaptureSetup) return;
          window._credCaptureSetup = true;

          function setupCapture() {
            var u = document.querySelector('input[name="username"], input#ft_un, input[name="user"], input[name="uid"], input[type="text"]');
            var p = document.querySelector('input[name="password"], input#ft_pd, input[type="password"]');
            if(!u || !p) { setTimeout(setupCapture, 500); return; }

            try {
              var stored = sessionStorage.getItem('_loginCreds');
              if(stored) {
                window._manualCreds = JSON.parse(stored);
              } else {
                window._manualCreds = {username: '', password: ''};
              }
            } catch(e) {
              window._manualCreds = {username: '', password: ''};
            }

            let debounceTimer;
            function capture() {
              clearTimeout(debounceTimer);
              debounceTimer = setTimeout(() => {
                if(u.value) window._manualCreds.username = u.value;
                if(p.value) window._manualCreds.password = p.value;
                try {
                  sessionStorage.setItem('_loginCreds', JSON.stringify(window._manualCreds));
                } catch(e) {}
              }, 200);
            }

            u.addEventListener('input', capture);
            p.addEventListener('input', capture);
            u.addEventListener('change', capture);
            p.addEventListener('change', capture);

            var form = u.closest('form') || document.querySelector('form');
            if(form) form.addEventListener('submit', capture);

            var buttons = document.querySelectorAll('input[type="submit"], button[type="submit"], button[name="login"], #login, .loginbtn, .btn-primary');
            buttons.forEach(btn => btn.addEventListener('click', capture));
          }

          if(document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', setupCapture);
          } else {
            setupCapture();
          }
        })();
      ''');
    } catch (_) {}
  }

  Future<void> _autoFillAndSubmit() async {
    final user = _username;
    final pass = _password;
    if (user == null || pass == null) return;

    final String js = JavaScriptInjector.getAutoFillScript(user, pass);
    try {
      await _controller.runJavaScriptReturningResult(js);
    } catch (_) {}
  }

  Future<void> _detectSuccessAndMaybePromptSave() async {
    try {
      final String? currentUrl = await _controller.currentUrl();
      final bool isSuccessPage = currentUrl != null &&
          (currentUrl.toLowerCase().contains("keepalive"));

      if (!isSuccessPage) return;
      _checkForUpdate();

      if (_username == null || _password == null) {
        final Object? storedCreds = await _controller.runJavaScriptReturningResult('''
          (function(){
            try{
              var data = null;
              if(sessionStorage.getItem('_loginCreds')){
                var s = sessionStorage.getItem('_loginCreds');
                data = JSON.parse(s);
              } else if(window._manualCreds){
                data = window._manualCreds;
              } else if(window._capturedCreds){
                data = window._capturedCreds;
              } else { data = {}; }
              return JSON.stringify(data);
            } catch(e){ return "{}"; }
          })()
        ''');

        if (storedCreds != null) {
          final String raw = storedCreds.toString();
          if (raw.isNotEmpty && raw != '{}' && raw != 'null') {
            dynamic decoded;
            try {
              decoded = jsonDecode(raw);
              if (decoded is String) decoded = jsonDecode(decoded);
            } catch (_) {
              decoded = {};
            }

            if (decoded is Map<String, dynamic>) {
              final u = decoded['username'];
              final p = decoded['password'];
              if (u != null && u.toString().trim().isNotEmpty) _username = u;
              if (p != null && p.toString().isNotEmpty) _password = p;
            }
          }
        }
      }

      if (_username == null || _password == null) return;

      await _controller.runJavaScript('sessionStorage.removeItem("_loginCreds");');

      final user = _username!;
      final pass = _password!;
      final accounts = await _storageService.readAllAccounts();
      final bool storageEmpty = accounts.isEmpty;

      final normalizedUser = user.trim().toLowerCase();
      String? existingKey;
      for (final key in accounts.keys) {
        if (key.trim().toLowerCase() == normalizedUser) {
          existingKey = key;
          break;
        }
      }

      final bool exists = existingKey != null;
      final bool samePassword = exists && accounts[existingKey] == pass;
      final bool shouldPrompt = storageEmpty || !exists || !samePassword;

      if (!shouldPrompt) return;
      if (!mounted) return;

      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Save credentials?'),
          content: Text(
            storageEmpty
                ? "Save login for '$user' (will be set as default)?"
                : (!exists
                    ? "Save new account '$user'?"
                    : "Update saved password for '$user'?"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'no'),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'yes'),
              child: const Text('Yes'),
            ),
          ],
        ),
      );

      if (action == 'yes') {
        accounts[existingKey ?? user] = pass;
        await _storageService.writeAllAccounts(accounts);
        if (storageEmpty) await _storageService.saveCredentials(user, pass);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Credentials saved securely${storageEmpty ? ' and set as default.' : '.'}",
              ),
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _openSettings() async {
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CredentialsSettingsPage(
          storageService: _storageService,
        ),
      ),
    );
    if (res == true) {
      _username = await _storageService.getUsername();
      _password = await _storageService.getPassword();
      await _controller.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GateIn"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Portal',
            onPressed: _initialize,
          ),
          IconButton(
            icon: const Icon(Icons.system_update),
            tooltip: 'Check for Updates',
            onPressed: _checkForUpdate,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Credentials Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (!_readyToShow)
            const Center(child: CircularProgressIndicator())
          else
            WebViewWidget(controller: _controller),
          if (_isLoading) const LinearProgressIndicator(minHeight: 3),
        ],
      ),
    );
  }
}
