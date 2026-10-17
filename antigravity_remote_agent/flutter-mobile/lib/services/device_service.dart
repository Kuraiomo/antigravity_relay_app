import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import '../models/device_model.dart';
import '../models/project_model.dart';

/// Manages enrolled devices and their projects/workspaces.
///
/// Integrates with .env configuration and real relay endpoints
/// with intelligent mock fallback.
class DeviceService extends ChangeNotifier {
  AuthService? _auth;

  List<DeviceModel> _devices = [];
  List<ProjectModel> _projects = [];
  DeviceModel? _selectedDevice;
  ProjectModel? _selectedProject;
  bool _isLoading = false;
  String? _error;

  // ── Getters ───────────────────────────────────────────

  List<DeviceModel> get devices => List.unmodifiable(_devices);
  List<ProjectModel> get projects => List.unmodifiable(_projects);
  DeviceModel? get selectedDevice => _selectedDevice;
  ProjectModel? get selectedProject => _selectedProject;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasSelection =>
      _selectedDevice != null && _selectedProject != null;

  // ── Auth update ───────────────────────────────────────

  void updateAuth(AuthService auth) {
    _auth = auth;
    if (auth.isAuthenticated && _devices.isEmpty) {
      loadDevices();
    }
  }

  // ── Load devices ──────────────────────────────────────

  Future<void> loadDevices() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final isMock = _auth?.isMockMode ?? false;
      final relayUrl = _auth?.relayUrl;
      final token = _auth?.accessToken;

      if (!isMock && relayUrl != null && token != null) {
        try {
          final uri = Uri.parse('$relayUrl/api/devices');
          final response = await http.get(
            uri,
            headers: {'Authorization': 'Bearer $token'},
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as List<dynamic>;
            _devices = data
                .map((d) => DeviceModel.fromJson(d as Map<String, dynamic>))
                .toList();
            if (_devices.isNotEmpty) {
              selectDevice(_devices.first);
              return;
            }
          }
        } catch (e) {
          debugPrint('Relay device fetch error: $e, falling back to enrolled config');
        }
      }

      // Default enrolled devices including the Windows PC from .env
      final envDeviceId = dotenv.env['DEVICE_ID'] ?? 'ayaan-windows-pc';
      final envDeviceName = dotenv.env['DEVICE_NAME'] ?? "Ayaan's Windows PC";

      _devices = [
        DeviceModel(
          id: envDeviceId,
          name: envDeviceName,
          agentVersion: '0.1.0',
          isOnline: true,
          lastSeen: DateTime.now(),
          isMockMode: isMock,
        ),
        if (isMock)
          DeviceModel(
            id: 'mock-cloud-runner',
            name: 'Cloud Build Agent',
            agentVersion: '0.1.0',
            isOnline: true,
            lastSeen: DateTime.now().subtract(const Duration(minutes: 5)),
            isMockMode: true,
          ),
      ];

      // Auto-select primary device
      if (_devices.isNotEmpty) {
        selectDevice(_devices.first);
      }
    } catch (e) {
      _error = 'Failed to load devices: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Select device ─────────────────────────────────────

  void selectDevice(DeviceModel device) {
    _selectedDevice = device;
    _selectedProject = null;
    _projects = [];
    notifyListeners();
    loadProjects(device.id);
  }

  // ── Load projects ─────────────────────────────────────

  Future<void> loadProjects(String deviceId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final isMock = _auth?.isMockMode ?? false;
      final relayUrl = _auth?.relayUrl;
      final token = _auth?.accessToken;

      if (!isMock && relayUrl != null && token != null) {
        try {
          final uri = Uri.parse('$relayUrl/api/projects?device_id=$deviceId');
          final response = await http.get(
            uri,
            headers: {'Authorization': 'Bearer $token'},
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as List<dynamic>;
            _projects = data
                .map((p) => ProjectModel.fromJson(p as Map<String, dynamic>))
                .toList();
            if (_projects.isNotEmpty) {
              selectProject(_projects.first);
              return;
            }
          }
        } catch (e) {
          debugPrint('Relay project fetch error: $e, falling back to local projects');
        }
      }

      final defaultWorkspaceRoot = dotenv.env['DEFAULT_WORKSPACE_ID'] ??
          r'C:\Users\ayaan\OneDrive\Desktop';

      _projects = [
        ProjectModel(
          id: '$defaultWorkspaceRoot\\Antigravity_controller',
          name: 'Antigravity Controller',
          path: '$defaultWorkspaceRoot\\Antigravity_controller',
          deviceId: deviceId,
        ),
        ProjectModel(
          id: defaultWorkspaceRoot,
          name: 'Desktop Root',
          path: defaultWorkspaceRoot,
          deviceId: deviceId,
        ),
        ProjectModel(
          id: '$defaultWorkspaceRoot\\Antigravity_controller\\antigravity_remote_agent_bundle\\antigravity_remote_agent\\desktop-agent',
          name: 'desktop-agent',
          path: '$defaultWorkspaceRoot\\Antigravity_controller\\antigravity_remote_agent_bundle\\antigravity_remote_agent\\desktop-agent',
          deviceId: deviceId,
        ),
        ProjectModel(
          id: '$defaultWorkspaceRoot\\Antigravity_controller\\antigravity_remote_agent_bundle\\antigravity_remote_agent\\flutter-mobile',
          name: 'flutter-mobile',
          path: '$defaultWorkspaceRoot\\Antigravity_controller\\antigravity_remote_agent_bundle\\antigravity_remote_agent\\flutter-mobile',
          deviceId: deviceId,
        ),
      ];

      if (_projects.isNotEmpty) {
        selectProject(_projects.first);
      }
    } catch (e) {
      _error = 'Failed to load projects: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Select project ────────────────────────────────────

  void selectProject(ProjectModel project) {
    _selectedProject = project;
    notifyListeners();
  }

  /// Choose a custom local project/workspace directory on Windows.
  void setCustomWorkspace(String rawPath, {String? name}) {
    final cleanPath = rawPath.trim();
    if (cleanPath.isEmpty) return;

    final displayName = name ??
        cleanPath.replaceAll(RegExp(r'[\\/]+$'), '').split(RegExp(r'[\\/]')).last;

    // Check if project already exists
    final existingIdx = _projects.indexWhere((p) => p.path == cleanPath || p.id == cleanPath);
    if (existingIdx >= 0) {
      _selectedProject = _projects[existingIdx];
    } else {
      final newProject = ProjectModel(
        id: cleanPath,
        name: displayName.isNotEmpty ? displayName : cleanPath,
        path: cleanPath,
        deviceId: _selectedDevice?.id ?? '',
      );
      _projects = [newProject, ..._projects];
      _selectedProject = newProject;
    }
    notifyListeners();
  }

  // ── Clear selection ───────────────────────────────────

  void clearSelection() {
    _selectedDevice = null;
    _selectedProject = null;
    _projects = [];
    notifyListeners();
  }
}
