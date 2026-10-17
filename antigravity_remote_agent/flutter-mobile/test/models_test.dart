import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/models/device_model.dart';
import 'package:antigravity_mobile/models/task_model.dart';
import 'package:antigravity_mobile/models/project_model.dart';
import 'package:antigravity_mobile/models/event_model.dart';

void main() {
  group('DeviceModel', () {
    test('fromJson creates a valid device', () {
      final json = {
        'id': 'device-123',
        'name': 'Test PC',
        'agent_version': '0.1.0',
        'is_online': true,
        'mock_mode': true,
      };

      final device = DeviceModel.fromJson(json);
      expect(device.id, 'device-123');
      expect(device.name, 'Test PC');
      expect(device.isOnline, true);
      expect(device.isMockMode, true);
    });

    test('copyWith preserves unchanged fields', () {
      const device = DeviceModel(
        id: 'dev-1',
        name: 'My PC',
        isOnline: true,
      );

      final updated = device.copyWith(isOnline: false);
      expect(updated.id, 'dev-1');
      expect(updated.name, 'My PC');
      expect(updated.isOnline, false);
    });
  });

  group('TaskModel', () {
    test('status enum values', () {
      expect(TaskStatus.pending.isTerminal, false);
      expect(TaskStatus.running.isTerminal, false);
      expect(TaskStatus.completed.isTerminal, true);
      expect(TaskStatus.failed.isTerminal, true);
    });

    test('fromJson creates a valid task', () {
      final json = {
        'request_id': 'req-1',
        'task_id': 'task-1',
        'operation': 'antigravity.prompt',
        'status': 'running',
        'prompt': 'Test prompt',
        'created_at': DateTime.now().toIso8601String(),
      };

      final task = TaskModel.fromJson(json);
      expect(task.requestId, 'req-1');
      expect(task.operation, 'antigravity.prompt');
      expect(task.status, TaskStatus.running);
    });
  });

  group('ProjectModel', () {
    test('fromJson and toJson round-trip', () {
      final json = {
        'id': 'proj-1',
        'name': 'Test Project',
        'path': r'C:\Projects\test',
        'device_id': 'dev-1',
      };

      final project = ProjectModel.fromJson(json);
      final output = project.toJson();

      expect(output['id'], json['id']);
      expect(output['name'], json['name']);
      expect(output['path'], json['path']);
    });
  });

  group('EventModel', () {
    test('fromJson with payload', () {
      final json = {
        'type': 'task.event',
        'request_id': 'req-1',
        'event': 'running',
        'payload': {'message': 'Task started'},
      };

      final event = EventModel.fromJson(json);
      expect(event.type, 'task.event');
      expect(event.event, 'running');
      expect(event.message, 'Task started');
    });
  });
}
