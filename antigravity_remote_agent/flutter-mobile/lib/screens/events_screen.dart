import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/relay_service.dart';
import '../models/event_model.dart';

/// Live event stream screen.
///
/// Shows all events received from the relay, with timestamps,
/// event types, and messages. Distinguishes connection states.
class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final relay = context.watch<RelayService>();
    final events = relay.events.reversed.toList();

    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.stream_rounded,
              size: 64,
              color: Colors.white.withAlpha(40),
            ),
            const SizedBox(height: 16),
            Text(
              'No events yet',
              style: TextStyle(
                color: Colors.white.withAlpha(100),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Events will appear here as tasks are processed',
              style: TextStyle(
                color: Colors.white.withAlpha(60),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Clear button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${events.length} events',
                style: TextStyle(
                  color: Colors.white.withAlpha(120),
                  fontSize: 13,
                ),
              ),
              TextButton.icon(
                onPressed: relay.clearEvents,
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withAlpha(140),
                ),
              ),
            ],
          ),
        ),

        // Event list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: events.length,
            itemBuilder: (context, index) {
              return _EventCard(event: events[index]);
            },
          ),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventModel event;

  const _EventCard({required this.event});

  Color _eventColor() {
    switch (event.event) {
      case 'accepted':
        return Colors.blue;
      case 'running':
        return Colors.amber;
      case 'stdout':
        return Colors.green;
      case 'stderr':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.white.withAlpha(140);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _eventColor();
    final timeStr = DateFormat('HH:mm:ss').format(event.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF131322),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timeStr,
            style: GoogleFonts.firaCode(
              fontSize: 11,
              color: Colors.white.withAlpha(80),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              event.event.isNotEmpty ? event.event : event.type,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              event.message,
              style: TextStyle(
                color: Colors.white.withAlpha(200),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
