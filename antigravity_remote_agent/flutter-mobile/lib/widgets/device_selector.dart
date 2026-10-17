import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/device_service.dart';
import '../models/device_model.dart';
import '../models/project_model.dart';

/// Device and project selector widget.
///
/// Allows selecting an enrolled device and then a permitted project.
/// Prompt submission requires both selections.
class DeviceSelector extends StatelessWidget {
  const DeviceSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final devices = context.watch<DeviceService>();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131322),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Device row
          Row(
            children: [
              Icon(
                Icons.computer_rounded,
                size: 18,
                color: Colors.white.withAlpha(120),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: devices.selectedDevice != null
                    ? _buildSelectedDevice(devices.selectedDevice!)
                    : Text(
                        'Select a device',
                        style: TextStyle(
                          color: Colors.white.withAlpha(80),
                          fontSize: 14,
                        ),
                      ),
              ),
              PopupMenuButton<DeviceModel>(
                icon: Icon(
                  Icons.unfold_more_rounded,
                  size: 20,
                  color: Colors.white.withAlpha(120),
                ),
                color: const Color(0xFF1A1A2E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: devices.selectDevice,
                itemBuilder: (context) => devices.devices.map((device) {
                  return PopupMenuItem<DeviceModel>(
                    value: device,
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: device.isOnline
                                ? Colors.green
                                : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                device.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                device.isOnline
                                    ? 'Online'
                                    : device.lastSeen != null
                                        ? 'Last seen ${DateFormat.Hm().format(device.lastSeen!)}'
                                        : 'Offline',
                                style: TextStyle(
                                  color: Colors.white.withAlpha(80),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (device.isMockMode)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Mock',
                              style: TextStyle(
                                color: Colors.amber.shade300,
                                fontSize: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // Project row (visible after device selection)
          if (devices.selectedDevice != null) ...[
            Divider(
              color: Colors.white.withAlpha(20),
              height: 16,
            ),
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: Colors.white.withAlpha(120),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: devices.selectedProject != null
                      ? Text(
                          devices.selectedProject!.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        )
                      : Text(
                          'Select a project',
                          style: TextStyle(
                            color: Colors.white.withAlpha(80),
                            fontSize: 14,
                          ),
                        ),
                ),
                PopupMenuButton<ProjectModel>(
                  icon: Icon(
                    Icons.unfold_more_rounded,
                    size: 20,
                    color: Colors.white.withAlpha(120),
                  ),
                  color: const Color(0xFF1A1A2E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: devices.selectProject,
                  itemBuilder: (context) =>
                      devices.projects.map((project) {
                    return PopupMenuItem<ProjectModel>(
                      value: project,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            project.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            project.path,
                            style: TextStyle(
                              color: Colors.white.withAlpha(60),
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedDevice(DeviceModel device) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: device.isOnline ? Colors.green : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          device.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        if (device.isMockMode) ...[
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.withAlpha(25),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Mock',
              style: TextStyle(
                color: Colors.amber.shade300,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
