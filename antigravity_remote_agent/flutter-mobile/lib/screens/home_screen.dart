import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/relay_service.dart';
import '../widgets/connection_indicator.dart';
import '../widgets/mock_mode_banner.dart';
import 'task_screen.dart';
import 'events_screen.dart';
import 'files_screen.dart';

/// Main home screen with bottom navigation.
///
/// Shows device connection state, project selection, and provides
/// access to tasks, events, and file browsing.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    TaskScreen(),
    EventsScreen(),
    FilesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final relay = context.watch<RelayService>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Antigravity'),
        actions: [
          // Connection indicator
          const ConnectionIndicator(),
          const SizedBox(width: 8),
          // Logout
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Disconnect and log out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await relay.disconnect();
                await auth.logout();
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Mock mode banner
          const MockModeBanner(),

          // Page content
          Expanded(child: _pages[_currentIndex]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: const Color(0xFF0D0D1A),
        indicatorColor: colorScheme.primary.withAlpha(40),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.terminal_rounded),
            selectedIcon: Icon(Icons.terminal_rounded),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.stream_rounded),
            selectedIcon: Icon(Icons.stream_rounded),
            label: 'Events',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Files',
          ),
        ],
      ),
    );
  }
}
