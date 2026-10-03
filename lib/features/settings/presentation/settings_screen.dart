import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/auth/auth_service.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/widgets/mfa_card.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isConnected = false;
  MfaChallenge? _mfaChallenge;
  String _logOutput = "";

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final storage = ref.read(secureStorageProvider);
    final creds = await storage.getCredentials();
    if (creds['username'] != null) {
      _usernameController.text = creds['username']!;
    }
    if (creds['password'] != null) {
      _passwordController.text = creds['password']!;
    }
    // We can assume if they are saved, we check connection later
  }

  Future<void> _testConnection() async {
    setState(() {
      _isLoading = true;
      _mfaChallenge = null;
      _logOutput = "Starting connection test...\n";
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    try {
      // Save them
      final storage = ref.read(secureStorageProvider);
      final previous = await storage.getCredentials();
      final unchanged = previous['username'] == username && previous['password'] == password;
      await storage.saveCredentials(username, password);
      setState(() => _logOutput += "Credentials saved to secure storage.\n");

      final authService = ref.read(authServiceProvider);

      // Same credentials and a live session: no need to bother Authenticator.
      var success = false;
      if (unchanged) {
        setState(() => _logOutput += "Checking the existing session...\n");
        success = await authService.resumeSession();
        setState(() => _logOutput += success
            ? "Existing session is still valid, no MFA needed.\n"
            : "Saved session has expired.\n");
      }

      if (!success) {
        setState(() => _logOutput += "Initiating ADFS login sequence...\n");

        success = await authService.login(
          username,
          password,
          onMfaChallenge: (challenge) {
            if (!mounted) return;
            setState(() {
              _mfaChallenge = challenge;
              _logOutput += "Waiting for Microsoft Authenticator approval...\n";
            });
          },
        );
      }

      ref.read(authStateProvider.notifier).state = success;

      setState(() {
        _isLoading = false;
        _isConnected = success;
        _mfaChallenge = null;
        _logOutput += success ? "Connected! Session saved.\n" : "Login FAILED. Check credentials.\n";
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Successfully connected to ADFS!' : 'Failed to connect. Check credentials.'),
            backgroundColor: success ? Colors.green : Colors.red,
          )
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isConnected = false;
        _mfaChallenge = null;
        _logOutput += "FATAL ERROR: $e\n";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ADFS Credentials',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your credentials are stored locally on your device. Signing in will asks for approval in '
                'Microsoft Authenticator, the session is then kept so you should not be asked again '
                'until it expires.',
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Student ID (e.g. 2100000)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _testConnection,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save credential locally'),
              ),
              if (_mfaChallenge != null) ...[
                const SizedBox(height: 24),
                MfaCard(challenge: _mfaChallenge!),
              ],
              const SizedBox(height: 24),
              if (_isConnected || ref.watch(authStateProvider))
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text('ADFS Status: Connected', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              if (_logOutput.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text('Connection Logs:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _logOutput,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
