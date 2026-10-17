import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/task_model.dart';

/// Displays a scrollable list of events for a task.
class TaskEventList extends StatelessWidget {
  final List<TaskEvent> events;

  const TaskEventList({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF16162A),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded,
                    size: 16, color: Colors.white.withAlpha(120)),
                const SizedBox(width: 8),
                Text(
                  'Task Output',
                  style: TextStyle(
                    color: Colors.white.withAlpha(160),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${events.length} events',
                  style: TextStyle(
                    color: Colors.white.withAlpha(60),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Events
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                final timeStr =
                    DateFormat('HH:mm:ss').format(event.timestamp);

                Color eventColor;
                switch (event.event) {
                  case 'stdout':
                    eventColor = Colors.green.shade300;
                  case 'stderr':
                    eventColor = Colors.orange.shade300;
                  case 'completed':
                    eventColor = Colors.green;
                  case 'failed':
                    eventColor = Colors.red;
                  default:
                    eventColor = Colors.white.withAlpha(160);
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        timeStr,
                        style: GoogleFonts.firaCode(
                          fontSize: 10,
                          color: Colors.white.withAlpha(50),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.message,
                          style: GoogleFonts.firaCode(
                            fontSize: 12,
                            color: eventColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
