import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

/// Login screen with relay URL, credentials, and mock mode toggle.
///
/// Pre-populates defaults from the .env configuration and securely
/// connects to the relay or runs in local mock simulation.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _relayUrlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  bool _obscurePassword = true;
  bool _mockMode = false;
  late AnimationController _animController;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _mockMode = AuthService.defaultMockMode;
    _relayUrlController = TextEditingController(text: AuthService.defaultRelayUrl);
    _usernameController = TextEditingController(text: AuthService.defaultUsername);
    _passwordController = TextEditingController(text: AuthService.defaultPassword);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeIn = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _relayUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin({bool? useMock}) async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthService>();
    final isMock = useMock ?? _mockMode;
    final success = await auth.login(
      relayUrl: _relayUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      mockMode: isMock,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Login failed'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: FadeTransition(
              opacity: _fadeIn,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Logo / Title ──────────────────────
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF6C5CE7),
                          Color(0xFFA29BFE),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C5CE7).withAlpha(90),
                          blurRadius: 26,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.rocket_launch_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Antigravity',
                    style: GoogleFonts.inter(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Remote Agent Controller',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withAlpha(150),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Mode Indicator Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _mockMode
                          ? Colors.amber.withAlpha(25)
                          : Colors.green.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _mockMode
                            ? Colors.amber.withAlpha(80)
                            : Colors.green.withAlpha(80),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _mockMode ? Icons.science_outlined : Icons.cloud_done_rounded,
                          size: 15,
                          color: _mockMode ? Colors.amber.shade300 : Colors.greenAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _mockMode ? 'Mock Simulation Mode' : 'Live Relay Mode',
                          style: TextStyle(
                            color: _mockMode ? Colors.amber.shade300 : Colors.greenAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Form ──────────────────────────────
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _relayUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Relay Server URL',
                            prefixIcon: Icon(Icons.dns_rounded),
                          ),
                          keyboardType: TextInputType.url,
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Relay URL is required' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username / Agent User',
                            prefixIcon: Icon(Icons.person_rounded),
                          ),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Username is required' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password / Token',
                            prefixIcon: const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Password is required' : null,
                        ),

                        const SizedBox(height: 16),

                        const SizedBox(height: 12),

                        // Primary Connect Button
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: auth.isLoading ? null : () => _handleLogin(),
                            child: auth.isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Connect to Agent'),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Quick Connect with .env credentials
                        OutlinedButton.icon(
                          onPressed: auth.isLoading
                              ? null
                              : () {
                                  _relayUrlController.text = AuthService.defaultRelayUrl;
                                  _usernameController.text = AuthService.defaultUsername;
                                  _passwordController.text = AuthService.defaultPassword;
                                  setState(() => _mockMode = false);
                                  _handleLogin(useMock: false);
                                },
                          icon: const Icon(Icons.flash_on_rounded, size: 18),
                          label: const Text('Quick Connect (.env credentials)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFA29BFE),
                            side: const BorderSide(color: Color(0xFF6C5CE7)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
