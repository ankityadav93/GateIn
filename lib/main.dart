import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

late final WebViewController globalController;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  globalController = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..enableZoom(true)
    ..setBackgroundColor(Colors.white);

  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: AutoLoginPage()),
  );
}

class AutoLoginPage extends StatefulWidget {
  const AutoLoginPage({super.key});

  @override
  State<AutoLoginPage> createState() => _AutoLoginPageState();
}

class _AutoLoginPageState extends State<AutoLoginPage> with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _readyToShow = false; // hide webview until scaling injected/stable

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static const String _kUsernameKey = 'nkn_username';
  static const String _kPasswordKey = 'nkn_password';
  static const String _kPortalKey = 'last_portal';
  static const String _kAccountsKey = 'saved_accounts';

  String? _username;
  String? _password;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = globalController;
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _initialize();
  }

  Future<void> _initialize() async {
    final creds = await Future.wait([
      _secureStorage.read(key: _kUsernameKey),
      _secureStorage.read(key: _kPasswordKey),
    ]);
    _username = creds[0];
    _password = creds[1];

    String? cached = await _secureStorage.read(key: _kPortalKey);
    String targetUrl = cached ?? "http://172.16.222.1:1000/login?";

    setState(() {
      _readyToShow = false;
      _isLoading = true;
    });

    await _controller.loadRequest(Uri.parse(targetUrl));

    _detectLoginPortal()
        .timeout(const Duration(seconds: 2), onTimeout: () => cached)
        .then((newPortal) async {
      if (newPortal != null && newPortal != cached) {
        await _secureStorage.write(key: _kPortalKey, value: newPortal);
        await _controller.loadRequest(Uri.parse(newPortal));
      }
    });

    await _injectEarlyScaling();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _readyToShow = true);
    });

    _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) => setState(() {
          _isLoading = true;
        }),
        onPageFinished: (_) async {
          setState(() => _isLoading = false);
          await _forceCssZoom();
          await _detectSuccessAndMaybePromptSave();
          await _attemptAutoFillOnce();
        },
        onWebResourceError: (_) {},
      ),
    );
  }

  Future<String?> _detectLoginPortal() async {
    final commonIPs = [
      "http://127.16.222.1:1000/login?",
      "http://24.24.0.1:1000/login?",
      "http://20.20.0.1:1000/login?",
    ];

    for (final url in commonIPs) {
      if (await _isValidPortal(url)) return url;
    }

    final gateway = await _findGatewayIp();
    if (gateway != null) {
      final url = "http://$gateway:1000/login?";
      if (await _isValidPortal(url)) return url;
    }
    return null;
  }

  Future<bool> _isValidPortal(String url) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 700);
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      return (res.statusCode == 200 && res.headers.contentType?.mimeType == "text/html");
    } catch (_) {
      return false;
    }
  }

  Future<String?> _findGatewayIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            parts[3] = '1';
            return parts.join('.');
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _injectEarlyScaling() async {
    final double deviceWidth = MediaQuery.of(context).size.width;
    final String deviceWidthStr = deviceWidth.toStringAsFixed(1);

    final String js = """
      (function(){
        function applyScale() {
          try {
            var body = document.body;
            var doc = document.documentElement;
            var contentWidth = doc.scrollWidth || body && body.scrollWidth || window.innerWidth || $deviceWidthStr;
            if (!contentWidth || contentWidth <= 0) return;
            var target = $deviceWidthStr;
            var scale = target / contentWidth;
            if (scale > 1) scale = 1.0;
            body.style.transform = 'scale(' + scale + ')';
            body.style.transformOrigin = 'top left';
            body.style.width = (100 / scale) + '%';
            body.style.margin = '0';
            body.style.padding = '0';
            body.style.overflowX = 'hidden';
          } catch(e) {}
        }
        if (document.readyState === 'complete' || document.readyState === 'interactive') {
          applyScale();
        } else {
          document.addEventListener('DOMContentLoaded', function() {
            applyScale();
          }, {once:true});
        }
        setTimeout(applyScale, 200);
        return 'injected-scaling';
      })();
    """;

    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
  }

  Future<void> _forceCssZoom() async {
    final double targetWidth = MediaQuery.of(context).size.width;
    final String targetWidthStr = targetWidth.toStringAsFixed(1);

    final String js = '''
      (function() {
        try {
          var body = document.body;
          var doc = document.documentElement;
          var contentWidth = doc ? (doc.scrollWidth || (body && body.scrollWidth) || window.innerWidth) : window.innerWidth;
          if (!contentWidth || contentWidth <= 0) return;
          var target = $targetWidthStr;
          var scale = target / contentWidth;
          if (scale > 1) scale = 1.0;
          body.style.transform = 'scale(' + scale + ')';
          body.style.transformOrigin = 'top left';
          body.style.width = (100 / scale) + '%';
          body.style.margin = '0';
          body.style.padding = '0';
          body.style.overflowX = 'hidden';
        } catch(e){}
      })();
    ''';

    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
  }

  Future<void> _attemptAutoFillOnce() async {
    if (_username == null || _password == null) return;

    try {
      final Object? overLimitCheck = await _controller.runJavaScriptReturningResult('''(
        (function(){
          try {
            var text = (document.body && document.body.innerText || '').toLowerCase();
            return text.includes("concurrent authentication over limit") ||
                   text.includes("already logged") ||
                   text.includes("over limit") ||
                   text.includes("you are already logged in");
          } catch(e) { return false; }
        })()
      )''');

      if (overLimitCheck?.toString().toLowerCase() == 'true') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Concurrent login limit reached. Logout from another device."),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final Object? existsObj = await _controller.runJavaScriptReturningResult('''(
        (function(){
          try {
            var sel = document.querySelector('input[name="username"], input#ft_un, input[name="user"], input[name="uid"]');
            return sel != null;
          } catch(e) { return false; }
        })()
      )''');

      final bool exists = (existsObj?.toString().toLowerCase() == 'true');
      if (exists) await _autoFillAndSubmit();
    } catch (_) {}
  }

  Future<void> _autoFillAndSubmit() async {
    final String? user = _username;
    final String? pass = _password;
    if (user == null || pass == null) return;

    final String js = '''
      (function(){
        try {
          var u = document.querySelector('input[name="username"], input#ft_un, input[name="user"], input[name="uid"]');
          var p = document.querySelector('input[name="password"], input#ft_pd, input[type="password"]');
          if(u) u.value = ${_escapeForJsString(user)};
          if(p) p.value = ${_escapeForJsString(pass)};
          var btn = document.querySelector('input[type="submit"], button[type="submit"], button[name="login"], #login, .loginbtn, .btn-primary, button');
          if(btn) { btn.click(); return "clicked"; }
          var f = document.querySelector('form');
          if(f) { f.submit(); return "submitted"; }
          return "no-submit";
        } catch(e) { return "error:"+e; }
      })();
    ''';

    try {
      await _controller.runJavaScriptReturningResult(js);
    } catch (_) {}
  }

  Future<void> _detectSuccessAndMaybePromptSave() async {
    try {
      final Object? infoJson = await _controller.runJavaScriptReturningResult('''(
        (function(){
          try {
            var bodyText = document.body ? document.body.innerText.toLowerCase() : "";
            var success = bodyText.includes("logout") || bodyText.includes("welcome") ||
                          bodyText.includes("dashboard") || bodyText.includes("you are connected") ||
                          bodyText.includes("successfully");
            var uEl = document.querySelector('input[name="username"], input#ft_un, input[name="user"], input[name="uid"]');
            var pEl = document.querySelector('input[name="password"], input#ft_pd, input[type="password"]');
            var uVal = uEl ? uEl.value : null;
            var pVal = pEl ? pEl.value : null;
            return JSON.stringify({success: success, username: uVal, password: pVal});
          } catch(e) {
            return JSON.stringify({success:false});
          }
        })();
      )''');

      if (infoJson == null) return;
      final Map info = jsonDecode(infoJson.toString());
      final bool success = info['success'] == true;
      final String? pageUser = info['username'];
      final String? pagePass = info['password'];

      if (success && pageUser != null && pagePass != null) {
        await _maybePromptToSave(pageUser, pagePass);
      }
    } catch (_) {}
  }

  Future<void> _maybePromptToSave(String pageUser, String pagePass) async {
    final Map<String, String> accounts = await _readAllAccounts();
    final bool exists = accounts.containsKey(pageUser);
    final bool storageWasEmpty = accounts.isEmpty;
    final bool shouldPrompt = storageWasEmpty || !exists || (accounts[pageUser] != pagePass);
    if (!shouldPrompt) return;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save credentials?'),
        content: Text(
          storageWasEmpty
              ? "Save login for '$pageUser' (will be set as default)?"
              : (!exists ? "Save new account '$pageUser'?" : "Update saved password for '$pageUser'?"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'no'), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'yes'), child: const Text('Yes')),
        ],
      ),
    );

    if (action == 'yes') {
      accounts[pageUser] = pagePass;
      await _writeAllAccounts(accounts);

      if (storageWasEmpty) {
        await _secureStorage.write(key: _kUsernameKey, value: pageUser);
        await _secureStorage.write(key: _kPasswordKey, value: pagePass);
        _username = pageUser;
        _password = pagePass;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Credentials saved securely${storageWasEmpty ? ' and set as default.' : '.'}')),
        );
      }
    }
  }

  Future<Map<String, String>> _readAllAccounts() async {
    final raw = await _secureStorage.read(key: _kAccountsKey);
    if (raw == null) return {};
    try {
      final Map parsed = jsonDecode(raw);
      return parsed.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAllAccounts(Map<String, String> accounts) async {
    await _secureStorage.write(key: _kAccountsKey, value: jsonEncode(accounts));
  }

  Future<void> _openSettings() async {
    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CredentialsSettingsPage(secureStorage: _secureStorage),
      ),
    );
    if (res == true) {
      final creds = await Future.wait([
        _secureStorage.read(key: _kUsernameKey),
        _secureStorage.read(key: _kPasswordKey),
      ]);
      _username = creds[0];
      _password = creds[1];
      await _controller.reload();
    }
  }

  static String _escapeForJsString(String raw) {
    final escaped = raw
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return "'$escaped'";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GateIn"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _initialize),
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
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

/* -----------------------------
   CredentialsSettingsPage
   ----------------------------- */

class CredentialsSettingsPage extends StatefulWidget {
  final FlutterSecureStorage secureStorage;
  const CredentialsSettingsPage({required this.secureStorage, super.key});

  @override
  State<CredentialsSettingsPage> createState() => _CredentialsSettingsPageState();
}

class _CredentialsSettingsPageState extends State<CredentialsSettingsPage> {
  Map<String, String> _accounts = {};
  bool _loading = true;
  String? _defaultUser;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _uCtrl = TextEditingController();
  final TextEditingController _pCtrl = TextEditingController();

  static const String _kAccountsKey = 'saved_accounts';
  static const String _kUsernameKey = 'nkn_username';
  static const String _kPasswordKey = 'nkn_password';

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final raw = await widget.secureStorage.read(key: _kAccountsKey);
    final defUser = await widget.secureStorage.read(key: _kUsernameKey);
    if (raw != null) {
      try {
        final Map parsed = jsonDecode(raw);
        _accounts = parsed.map((k, v) => MapEntry(k.toString(), v.toString()));
      } catch (_) {
        _accounts = {};
      }
    }
    _defaultUser = defUser;
    setState(() => _loading = false);
  }

  Future<void> _saveAccounts() async {
    await widget.secureStorage.write(
      key: _kAccountsKey,
      value: jsonEncode(_accounts),
    );
    setState(() {});
  }

  Future<void> _setAsDefault(String user) async {
    final pass = _accounts[user];
    if (pass == null) return;
    await widget.secureStorage.write(key: _kUsernameKey, value: user);
    await widget.secureStorage.write(key: _kPasswordKey, value: pass);
    _defaultUser = user;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("'$user' set as default credentials")),
    );
  }

  Future<void> _deleteAccount(String user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text("Are you sure you want to delete '$user'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    final bool wasDefault = (_defaultUser == user);
    _accounts.remove(user);

    if (wasDefault) {
      if (_accounts.isNotEmpty) {
        final newDefaultUser = _accounts.keys.first;
        await _setAsDefault(newDefaultUser);
      } else {
        _defaultUser = null;
        await widget.secureStorage.delete(key: _kUsernameKey);
        await widget.secureStorage.delete(key: _kPasswordKey);
      }
    }

    await _saveAccounts();
  }

  Future<void> _editAccount(String user) async {
    final bool isAddingNew = user.isEmpty;
    final bool wasEmptyBefore = _accounts.isEmpty;
    final oldPass = _accounts[user] ?? '';
    _uCtrl.text = user;
    _pCtrl.text = oldPass;

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAddingNew ? 'Add Credentials' : 'Edit Credentials'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _uCtrl,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter username' : null,
              ),
              TextFormField(
                controller: _pCtrl,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) => (v ?? '').isEmpty ? 'Enter password' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (res == true) {
      final newUser = _uCtrl.text.trim();
      final newPass = _pCtrl.text;
      if (newUser.isEmpty) return;

      if (!isAddingNew && user != newUser) {
        _accounts.remove(user);
      }

      _accounts[newUser] = newPass;

      if (wasEmptyBefore || _defaultUser == user || (_defaultUser == null && isAddingNew)) {
        await _setAsDefault(newUser);
      } else if (_defaultUser == user && user != newUser) {
        await _setAsDefault(newUser);
      }

      await _saveAccounts();
      _uCtrl.clear();
      _pCtrl.clear();
      setState(() {});
    }
  }

  Future<void> _addAccount() async => _editAccount('');

  @override
  void dispose() {
    _uCtrl.dispose();
    _pCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Credentials'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addAccount),
          IconButton(icon: const Icon(Icons.check), onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
              ? const Center(child: Text('No saved accounts'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemCount: _accounts.length,
                  itemBuilder: (_, i) {
                    final user = _accounts.keys.elementAt(i);
                    final isDefault = (user == _defaultUser);
                    final masked = '*' * (_accounts[user]?.length ?? 6);

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      decoration: BoxDecoration(
                        color: isDefault
                            ? const Color.fromARGB(255, 30, 255, 49).withOpacity(0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDefault
                              ? const Color.fromARGB(255, 118, 187, 124)
                              : Colors.grey.shade300,
                          width: isDefault ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 3,
                            offset: const Offset(1, 1),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            title: Text(
                              user,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Colors.black,
                              ),
                            ),
                            subtitle: Text(masked),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                switch (v) {
                                  case 'use':
                                    await _setAsDefault(user);
                                    break;
                                  case 'edit':
                                    await _editAccount(user);
                                    break;
                                  case 'delete':
                                    await _deleteAccount(user);
                                    break;
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'use', child: Text('Set as Default')),
                                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ),
                          if (isDefault)
                            Positioned(
                              left: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.85),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(6),
                                    bottomRight: Radius.circular(6),
                                  ),
                                ),
                                child: const Text(
                                  'Default',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
