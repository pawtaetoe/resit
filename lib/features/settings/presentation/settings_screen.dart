import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';

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
      _logOutput = "Starting connection test...\n";
    });
    
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    
    try {
      // Save them
      final storage = ref.read(secureStorageProvider);
      await storage.saveCredentials(username, password);
      setState(() => _logOutput += "Credentials saved to secure storage.\n");

      // Test auth
      final authService = ref.read(authServiceProvider);
      setState(() => _logOutput += "Initiating ADFS login sequence...\n");
      
      final success = await authService.login(username, password);
      
      ref.read(authStateProvider.notifier).state = success;

      setState(() {
        _isLoading = false;
        _isConnected = success;
        _logOutput += success ? "Login SUCCESS!\n" : "Login FAILED. Check credentials.\n";
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
              const Text('Your credentials are encrypted and stored locally on your device.'),
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
                    : const Text('Save & Test Connection'),
              ),
              const SizedBox(height: 24),
              if (_isConnected)
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
