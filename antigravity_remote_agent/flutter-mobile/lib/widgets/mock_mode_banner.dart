import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

/// Banner displayed only when the app is in mock mode.
class MockModeBanner extends StatelessWidget {
  const MockModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isMock = context.watch<AuthService>().isMockMode;
    if (!isMock) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.amber.withAlpha(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.science_outlined,
              size: 14, color: Colors.amber.shade300),
          const SizedBox(width: 6),
          Text(
            'Mock Mode — Not connected to real Antigravity',
            style: TextStyle(
              color: Colors.amber.shade300,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
