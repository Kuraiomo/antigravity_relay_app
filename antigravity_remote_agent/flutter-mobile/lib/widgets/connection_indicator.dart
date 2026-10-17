import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/relay_service.dart' as relay;

/// Connection state indicator shown in the app bar.
///
/// Displays the current relay connection state with an animated
/// dot indicator and descriptive tooltip.
class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final relayClient = context.watch<relay.RelayService>();
    final state = relayClient.state;

    Color dotColor;
    String tooltip;

    switch (state) {
      case relay.ConnectionState.connected:
        dotColor = Colors.green;
        tooltip = 'Connected to relay';
      case relay.ConnectionState.connecting:
        dotColor = Colors.amber;
        tooltip = 'Connecting...';
      case relay.ConnectionState.reconnecting:
        dotColor = Colors.orange;
        tooltip = 'Reconnecting...';
      case relay.ConnectionState.unauthorized:
        dotColor = Colors.red;
        tooltip = 'Unauthorized';
      case relay.ConnectionState.error:
        dotColor = Colors.red;
        tooltip = 'Connection error';
      case relay.ConnectionState.disconnected:
        dotColor = Colors.grey;
        tooltip = 'Disconnected';
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: dotColor.withAlpha(20),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated pulse for active states
            if (state == relay.ConnectionState.connecting ||
                state == relay.ConnectionState.reconnecting)
              _PulsingDot(color: dotColor)
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withAlpha(80),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 6),
            Text(
              state.displayName,
              style: TextStyle(
                color: dotColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Opacity(
        opacity: 0.4 + (_controller.value * 0.6),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
