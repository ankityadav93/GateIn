import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/update_service.dart';


class CredentialsSettingsPage extends StatefulWidget {
  final StorageService storageService;

  const CredentialsSettingsPage({required this.storageService, super.key});

  @override
  State<CredentialsSettingsPage> createState() =>
      _CredentialsSettingsPageState();
}

class _CredentialsSettingsPageState extends State<CredentialsSettingsPage> {
  Map<String, String> _accounts = {};
  bool _loading = true;
  String? _defaultUser;
  String _appVersion = '';

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _uCtrl = TextEditingController();
  final TextEditingController _pCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _appVersion = info.version);
  }

  Future<void> _loadAccounts() async {
    _accounts = await widget.storageService.readAllAccounts();
    _defaultUser = await widget.storageService.getUsername();
    setState(() => _loading = false);
  }

  Future<void> _saveAccounts() async {
    await widget.storageService.writeAllAccounts(_accounts);
    setState(() {});
  }

  Future<void> _setAsDefault(String user) async {
    final pass = _accounts[user];
    if (pass == null) return;
    await widget.storageService.saveCredentials(user, pass);
    _defaultUser = user;
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("'$user' set as default credentials")),
      );
    }
  }

  Future<void> _deleteAccount(String user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text("Are you sure you want to delete '$user'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final wasDefault = (_defaultUser == user);
    _accounts.remove(user);

    if (wasDefault) {
      if (_accounts.isNotEmpty) {
        final newDefaultUser = _accounts.keys.first;
        await _setAsDefault(newDefaultUser);
      } else {
        _defaultUser = null;
        await widget.storageService.deleteDefaultCredentials();
      }
    }

    await _saveAccounts();
  }

  Future<void> _editAccount(String user) async {
    final isAddingNew = user.isEmpty;
    final wasEmptyBefore = _accounts.isEmpty;
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
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter username' : null,
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
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

      if (!isAddingNew && user != newUser) _accounts.remove(user);
      _accounts[newUser] = newPass;

      if (wasEmptyBefore ||
          _defaultUser == user ||
          (_defaultUser == null && isAddingNew)) {
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
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _accounts.isEmpty
                      ? const Center(child: Text('No saved accounts'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemCount: _accounts.length,
                          itemBuilder: (_, i) {
                            final user = _accounts.keys.elementAt(i);
                            final isDefault = (user == _defaultUser);
                            final masked =
                                '*' * (_accounts[user]?.length ?? 6);

                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              decoration: BoxDecoration(
                                gradient: isDefault
                                    ? const LinearGradient(
                                        colors: [
                                          Color.fromARGB(255, 216, 218, 221),
                                          Color.fromARGB(255, 134, 134, 143),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: isDefault ? null : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDefault
                                      ? Color.fromARGB(255, 168, 172, 168)
                                      : Colors.grey.shade300,
                                  width: isDefault ? 2.5 : 1.5,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
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
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'use',
                                          child: Text('Set as Default'),
                                        ),
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isDefault)
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      child: Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: const BoxDecoration(
                                          color: Color.fromARGB(255, 168, 172, 168),
                                          borderRadius: BorderRadius.only(
                                            topLeft: Radius.circular(7),
                                            bottomRight: Radius.circular(6),
                                          ),
                                        ),
                                        child: const Text(
                                          'Default',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
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
                ),

                // VERSION AT BOTTOM
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    "Version $_appVersion",
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
