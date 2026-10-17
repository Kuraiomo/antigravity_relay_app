import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/device_model.dart';
import '../models/project_model.dart';
import '../services/device_service.dart';
import '../services/relay_service.dart';
import '../services/task_service.dart';
import '../models/token_usage.dart';

/// Redesigned mobile chat interface for Antigravity Remote Controller.
///
/// Features:
/// - Single-message focus panel with vertical scrolling (prevents overflow)
/// - Bottom navigation: Previous / Position Counter (e.g. "3 of 12") / Next
/// - Multiline message composer kept visible during navigation
/// - Individual message copy button (clean text, no metadata, code blocks preserved)
/// - Dedicated "Copy for ChatGPT" button
/// - Workspace selector with configured roots + custom Windows directory dialog
/// - Live incremental streaming into the active message
/// - Auto-selection of newest messages
class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key});

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  final _inputController = TextEditingController();
  final _customPathController = TextEditingController();
  final _messageScrollController = ScrollController();
  bool _isTerminalMode = false;
  bool _isNavPanelExpanded = false;

  @override
  void dispose() {
    _inputController.dispose();
    _customPathController.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  Future<void> _handlePermissionModeSelection(String newMode) async {
    final tasks = context.read<TaskService>();
    if (newMode == tasks.permissionMode) return;

    if (newMode == 'full-auto') {
      final confirmed = await _showFullAutoConfirmationDialog(context);
      if (confirmed == true) {
        tasks.setPermissionMode('full-auto');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.bolt_rounded, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Full Auto enabled: Actions run without interactive prompts.'),
                  ),
                ],
              ),
              backgroundColor: Color(0xFF2C1515),
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } else {
      tasks.setPermissionMode(newMode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newMode == 'accept-edits'
                  ? 'Permission mode: Edit (Accept edits in workspace)'
                  : 'Permission mode: Review (Request review for sensitive actions)',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<bool?> _showFullAutoConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1418),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.redAccent, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Enable Full Auto Mode?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withAlpha(70)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.gavel_rounded, color: Colors.redAccent, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Uses official CLI automatic-approval (--dangerously-skip-permissions)',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Full Auto grants Antigravity unrestricted autonomous execution on the remote Windows desktop:',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            _buildWarningBullet('Execute arbitrary shell and terminal commands'),
            _buildWarningBullet('Modify, create, overwrite, and delete files'),
            _buildWarningBullet('Install, update, or remove software and packages'),
            _buildWarningBullet('Perform potentially destructive system operations'),
            const SizedBox(height: 12),
            Text(
              'Warning: Workspace restrictions may not prevent every action outside the project directory. Use with extreme caution.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.amber.shade300,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.bolt_rounded, size: 16),
            label: const Text('Enable Full Auto'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitMessage() async {
    final devices = context.read<DeviceService>();
    final tasks = context.read<TaskService>();

    if (!devices.hasSelection) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an enrolled device and workspace first'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final text = _inputController.text.trim();
    if (text.isEmpty || tasks.isSubmitting) return;

    if (_isTerminalMode) {
      await _submitTerminalCommand(text);
    } else {
      _inputController.clear();
      await tasks.submitPrompt(
        prompt: text,
        deviceId: devices.selectedDevice!.id,
        workspaceId: devices.selectedProject!.id,
      );
    }
  }

  Future<void> _submitTerminalCommand(String command) async {
    final devices = context.read<DeviceService>();
    final tasks = context.read<TaskService>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.orange),
            SizedBox(width: 8),
            Text('Execute Command?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will run on the remote device under request-review permissions:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withAlpha(30)),
              ),
              child: Text(
                command,
                style: GoogleFonts.firaCode(
                  color: const Color(0xFFA29BFE),
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Workspace: ${devices.selectedProject?.name}',
              style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12),
            ),
            Text(
              'Device: ${devices.selectedDevice?.name}',
              style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
            child: const Text('Execute'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _inputController.clear();
      await tasks.submitCommand(
        command: command,
        deviceId: devices.selectedDevice!.id,
        workspaceId: devices.selectedProject!.id,
      );
    }
  }

  void _showCustomWorkspaceDialog() {
    final devices = context.read<DeviceService>();
    _customPathController.text = devices.selectedProject?.path ?? '';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.create_new_folder_outlined, color: Color(0xFF6C5CE7)),
            SizedBox(width: 8),
            Text('Choose Windows Workspace'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a local project or workspace directory path on your Windows machine:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customPathController,
              style: GoogleFonts.firaCode(fontSize: 13),
              decoration: const InputDecoration(
                hintText: r'C:\Users\ayaan\OneDrive\Desktop\MyProject',
                labelText: 'Windows Directory Path',
                prefixIcon: Icon(Icons.folder_open),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The desktop agent validates that the directory exists and is in allowed roots before running tasks.',
              style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(140)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final path = _customPathController.text.trim();
              if (path.isNotEmpty) {
                devices.setCustomWorkspace(path);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Selected workspace: $path'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  void _copyMessageToClipboard(String content, {bool isForChatGpt = false}) {
    // Preserve formatting, whitespace, code blocks, and strip metadata
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isForChatGpt
                    ? 'Copied output to clipboard (ready to paste in ChatGPT)'
                    : 'Message copied to clipboard',
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<TaskService>();
    final devices = context.watch<DeviceService>();
    final relay = context.watch<RelayService>();
    final colorScheme = Theme.of(context).colorScheme;

    final currentMessage = tasks.currentMessage;

    return Column(
      children: [
        // ── Collapsible Top Navigation Panel ────────────────
        _buildCollapsibleNavigationPanel(devices, tasks),

        // ── Error Banner (if any) ───────────────────────────
        if (tasks.error != null)
          _buildErrorBanner(tasks),

        // ── Center Message Panel (Single-Message View) ───────
        Expanded(
          child: currentMessage == null
              ? _buildEmptyState(devices)
              : _buildMessagePanel(currentMessage, colorScheme),
        ),

        // ── Bottom Controls ─────────────────────────────────
        // 1. Navigation row: Previous / position / Next
        _buildNavigationRow(tasks),

        // 2. Multiline message composer
        _buildComposer(tasks, devices, colorScheme),

        // 3. Status bar + Mode toggle + Send button
        _buildStatusBarAndSend(tasks, devices, relay, colorScheme),
      ],
    );
  }

  // ── 1. Collapsible Navigation Panel ─────────────────────────

  Widget _buildCollapsibleNavigationPanel(DeviceService devices, TaskService tasks) {
    return _isNavPanelExpanded
        ? _buildExpandedNavigationPanel(devices, tasks)
        : _buildCollapsedNavigationPanel(devices, tasks);
  }

  Widget _buildCollapsedNavigationPanel(DeviceService devices, TaskService tasks) {
    final selectedDevice = devices.selectedDevice;
    final selectedProj = devices.selectedProject;
    final deviceLabel = selectedDevice?.name ?? 'No Device';
    final projLabel = selectedProj?.name ?? 'No Workspace';

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: InkWell(
        onTap: () => setState(() => _isNavPanelExpanded = true),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            // Controls menu icon
            const Icon(
              Icons.tune_rounded,
              size: 16,
              color: Color(0xFFA29BFE),
            ),
            const SizedBox(width: 8),
            // Device & Project Summary
            Expanded(
              child: Text(
                '$deviceLabel • $projLabel',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            // Permission chip in collapsed bar
            _buildPermissionModeChip(tasks, compact: true),
            const SizedBox(width: 4),
            // Quick New Chat button
            IconButton(
              icon: const Icon(Icons.add_comment_outlined, size: 16, color: Colors.white70),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Start fresh conversation',
              onPressed: () {
                tasks.startNewConversation();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Started a fresh conversation session'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const SizedBox(width: 2),
            // Expand arrow
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Colors.white60,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedNavigationPanel(DeviceService devices, TaskService tasks) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA29BFE).withAlpha(60), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row with Collapse button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune_rounded, size: 16, color: Color(0xFFA29BFE)),
                  SizedBox(width: 6),
                  Text(
                    'Environment & Controls',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => setState(() => _isNavPanelExpanded = false),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Collapse', style: TextStyle(fontSize: 11, color: Colors.white70)),
                      SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 10),

          // 1. Device Selector Row
          _buildDeviceSelectorRow(devices),
          const SizedBox(height: 8),

          // 2. Workspace Selector & Path Row
          _buildWorkspaceSelectorRow(devices),
          const SizedBox(height: 10),

          // 3. Permission Mode Selector Row (Review, Edit, Full Auto)
          _buildPermissionModeSelectorRow(tasks),
          const SizedBox(height: 10),

          // 4. Conversation Controls & Token Usage Row
          _buildConversationRow(tasks),
        ],
      ),
    );
  }

  Widget _buildDeviceSelectorRow(DeviceService devices) {
    final sel = devices.selectedDevice;
    return Row(
      children: [
        const Icon(Icons.computer_rounded, size: 16, color: Colors.white60),
        const SizedBox(width: 8),
        const Text(
          'Device:',
          style: TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E1C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: sel?.isOnline == true ? Colors.greenAccent : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sel?.name ?? 'Select device',
                    style: TextStyle(
                      fontSize: 12,
                      color: sel != null ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (sel?.isMockMode == true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Mock', style: TextStyle(color: Colors.amberAccent, fontSize: 9)),
                  ),
                PopupMenuButton<DeviceModel>(
                  tooltip: 'Choose enrolled device',
                  icon: const Icon(Icons.unfold_more_rounded, size: 16, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  color: const Color(0xFF1E1E38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                              color: device.isOnline ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              device.name,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                          if (device.isMockMode)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Mock', style: TextStyle(color: Colors.amberAccent, fontSize: 9)),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceSelectorRow(DeviceService devices) {
    final sel = devices.selectedProject;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.folder_outlined, size: 16, color: Colors.white60),
            const SizedBox(width: 8),
            const Text(
              'Workspace:',
              style: TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E0E1C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        sel?.name ?? 'Select workspace',
                        style: TextStyle(
                          fontSize: 12,
                          color: sel != null ? Colors.white : Colors.white38,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    PopupMenuButton<dynamic>(
                      tooltip: 'Choose workspace',
                      icon: const Icon(Icons.unfold_more_rounded, size: 16, color: Colors.white70),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      color: const Color(0xFF1E1E38),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      onSelected: (val) {
                        if (val == 'custom') {
                          _showCustomWorkspaceDialog();
                        } else if (val is ProjectModel) {
                          devices.selectProject(val);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem<dynamic>(
                          enabled: false,
                          child: Text(
                            'CONFIGURED WORKSPACES',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54),
                          ),
                        ),
                        ...devices.projects.map(
                          (p) => PopupMenuItem<ProjectModel>(
                            value: p,
                            child: Row(
                              children: [
                                Icon(
                                  p.id == sel?.id ? Icons.check_circle_rounded : Icons.folder,
                                  size: 16,
                                  color: p.id == sel?.id ? Colors.greenAccent : Colors.white60,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    p.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: p.id == sel?.id ? Colors.white : Colors.white70,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem<String>(
                          value: 'custom',
                          child: Row(
                            children: [
                              Icon(Icons.edit_location_alt_outlined, size: 16, color: Color(0xFFA29BFE)),
                              SizedBox(width: 8),
                              Text('Enter custom Windows directory...', style: TextStyle(fontSize: 12.5, color: Color(0xFFA29BFE))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (sel?.path != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              'Path: ${sel!.path}',
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.white.withAlpha(120),
                fontFamily: GoogleFonts.firaCode().fontFamily,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPermissionModeSelectorRow(TaskService tasks) {
    final currentMode = tasks.permissionMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.security_rounded, size: 15, color: Colors.white60),
                SizedBox(width: 8),
                Text(
                  'Permission Mode:',
                  style: TextStyle(fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            if (tasks.isPermissionModeMismatch)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orangeAccent.withAlpha(100)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.orangeAccent),
                    const SizedBox(width: 4),
                    Text(
                      'CLI applied: ${tasks.effectivePermissionMode}',
                      style: const TextStyle(fontSize: 10, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // 1. Review
            Expanded(
              child: _buildPermissionModeOption(
                label: 'Review',
                subtitle: 'Ask before action',
                modeValue: 'request-review',
                isSelected: currentMode == 'request-review' || currentMode == 'review',
                color: Colors.blueAccent,
                icon: Icons.shield_outlined,
                onTap: () => _handlePermissionModeSelection('request-review'),
              ),
            ),
            const SizedBox(width: 6),
            // 2. Edit
            Expanded(
              child: _buildPermissionModeOption(
                label: 'Edit',
                subtitle: 'Accept edits',
                modeValue: 'accept-edits',
                isSelected: currentMode == 'accept-edits' || currentMode == 'edit',
                color: Colors.amberAccent,
                icon: Icons.edit_note_rounded,
                onTap: () => _handlePermissionModeSelection('accept-edits'),
              ),
            ),
            const SizedBox(width: 6),
            // 3. Full Auto
            Expanded(
              child: _buildPermissionModeOption(
                label: 'Full Auto',
                subtitle: 'Auto-approve all',
                modeValue: 'full-auto',
                isSelected: currentMode == 'full-auto' || currentMode == 'auto',
                color: Colors.redAccent,
                icon: Icons.bolt_rounded,
                onTap: () => _handlePermissionModeSelection('full-auto'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPermissionModeOption({
    required String label,
    required String subtitle,
    required String modeValue,
    required bool isSelected,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(30) : const Color(0xFF0E0E1C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.white12,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: isSelected ? color : Colors.white60),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? color : Colors.white70,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 8.5,
                color: isSelected ? color.withAlpha(200) : Colors.white38,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationRow(TaskService tasks) {
    final sessionTokens = tasks.conversationTokenUsage;
    final fmt = NumberFormat('#,###');
    final convId = tasks.activeConversationId;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Color(0xFFA29BFE)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  convId != null ? 'Session: ${convId.substring(0, convId.length > 12 ? 12 : convId.length)}...' : 'Session: Fresh conversation',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    fontFamily: GoogleFonts.firaCode().fontFamily,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: () {
                  tasks.startNewConversation();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Started a fresh conversation session'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C5CE7).withAlpha(40),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF6C5CE7).withAlpha(100)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 12, color: Color(0xFFA29BFE)),
                      SizedBox(width: 2),
                      Text('New Chat', style: TextStyle(fontSize: 10.5, color: Color(0xFFA29BFE), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 12, color: Colors.amberAccent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  sessionTokens.isEmpty
                      ? 'Total Tokens: 0 (In: 0 | Out: 0)'
                      : 'Tokens: In: ${fmt.format(sessionTokens.inputTokens)} | Out: ${fmt.format(sessionTokens.outputTokens)} | Total: ${fmt.format(sessionTokens.totalTokens)}${sessionTokens.cacheReadTokens > 0 ? ' (Cached: ${fmt.format(sessionTokens.cacheReadTokens)})' : ''}',
                  style: TextStyle(
                    fontSize: 10,
                    color: sessionTokens.isEmpty ? Colors.white38 : Colors.white70,
                    fontFamily: GoogleFonts.firaCode().fontFamily,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionModeChip(TaskService tasks, {bool compact = false}) {
    final mode = tasks.permissionMode;
    final isFullAuto = mode == 'full-auto' || mode == 'auto';
    final isEdit = mode == 'accept-edits' || mode == 'edit';

    final Color badgeColor = isFullAuto
        ? Colors.redAccent
        : isEdit
            ? Colors.amberAccent
            : Colors.blueAccent;

    final IconData badgeIcon = isFullAuto
        ? Icons.bolt_rounded
        : isEdit
            ? Icons.edit_note_rounded
            : Icons.shield_outlined;

    final String badgeLabel = isFullAuto
        ? 'Full Auto'
        : isEdit
            ? 'Edit'
            : 'Review';

    return PopupMenuButton<String>(
      tooltip: 'Permission Mode',
      initialValue: mode,
      onSelected: _handlePermissionModeSelection,
      itemBuilder: (ctx) => [
        const PopupMenuItem<String>(
          value: 'request-review',
          child: Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text('Review (Ask before action)'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'accept-edits',
          child: Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 16, color: Colors.amberAccent),
              SizedBox(width: 8),
              Text('Edit (Accept edits)'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'full-auto',
          child: Row(
            children: [
              Icon(Icons.bolt_rounded, size: 16, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Full Auto (Automatic approval)'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 7, vertical: compact ? 2 : 3),
        decoration: BoxDecoration(
          color: badgeColor.withAlpha(25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: badgeColor.withAlpha(80),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              badgeIcon,
              size: compact ? 12 : 13,
              color: badgeColor,
            ),
            const SizedBox(width: 4),
            Text(
              badgeLabel,
              style: TextStyle(
                fontSize: compact ? 10.5 : 11,
                fontWeight: FontWeight.bold,
                color: badgeColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 2. Error Banner ─────────────────────────────────────────

  Widget _buildErrorBanner(TaskService tasks) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withAlpha(60)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tasks.error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
          InkWell(
            onTap: tasks.clearError,
            child: const Icon(Icons.close, size: 16, color: Colors.white60),
          ),
        ],
      ),
    );
  }

  // ── 3. Empty State ──────────────────────────────────────────

  Widget _buildEmptyState(DeviceService devices) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF6C5CE7).withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.smart_toy_outlined, size: 48, color: Color(0xFFA29BFE)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Antigravity Remote Controller',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              devices.hasSelection
                  ? 'Ready to assist in ${devices.selectedProject?.name}.\nSend a prompt below to begin.'
                  : 'Select an enrolled device & workspace to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(160)),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildPromptSuggestion('List top files in workspace'),
                _buildPromptSuggestion('Run tests with pytest'),
                _buildPromptSuggestion('Explain repository architecture'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptSuggestion(String suggestion) {
    return ActionChip(
      label: Text(suggestion, style: const TextStyle(fontSize: 11, color: Color(0xFFA29BFE))),
      backgroundColor: const Color(0xFF1E1E38),
      side: BorderSide(color: const Color(0xFF6C5CE7).withAlpha(50)),
      onPressed: () {
        _inputController.text = suggestion;
      },
    );
  }

  // ── 4. Large Readable Message Panel ─────────────────────────

  Widget _buildMessagePanel(ChatMessage message, ColorScheme colorScheme) {
    final isUser = message.sender == MessageSender.user;
    final isAssistant = message.sender == MessageSender.assistant;
    final isError = message.kind == MessageKind.error || message.isFailed;
    final isPermission = message.kind == MessageKind.permissionRequest;

    Color borderColor;
    Color headerColor;
    IconData headerIcon;
    String senderLabel;

    if (isUser) {
      borderColor = const Color(0xFF6C5CE7).withAlpha(80);
      headerColor = const Color(0xFF6C5CE7);
      headerIcon = Icons.person_outline_rounded;
      senderLabel = 'You';
    } else if (isError) {
      borderColor = Colors.red.withAlpha(100);
      headerColor = Colors.redAccent;
      headerIcon = Icons.error_outline_rounded;
      senderLabel = 'System Error';
    } else if (isPermission) {
      borderColor = Colors.amber.withAlpha(120);
      headerColor = Colors.amber;
      headerIcon = Icons.gpp_maybe_outlined;
      senderLabel = 'Permission Request';
    } else {
      borderColor = Colors.green.withAlpha(60);
      headerColor = const Color(0xFF00B894);
      headerIcon = Icons.auto_awesome_rounded;
      senderLabel = 'Antigravity Assistant';
    }

    final formattedTime = DateFormat('h:mm a').format(message.timestamp);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF141424),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Card Header ───────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C30),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(headerIcon, size: 16, color: headerColor),
                const SizedBox(width: 8),
                Text(
                  senderLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: headerColor,
                  ),
                ),
                const SizedBox(width: 8),
                // Status badge
                if (message.isStreaming)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.blueAccent),
                        ),
                        SizedBox(width: 4),
                        Text('Streaming...', style: TextStyle(fontSize: 10, color: Colors.blueAccent)),
                      ],
                    ),
                  )
                else if (message.isCompleted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Complete', style: TextStyle(fontSize: 10, color: Colors.greenAccent)),
                  ),
                const Spacer(),
                Text(
                  formattedTime,
                  style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(100)),
                ),
                const SizedBox(width: 4),
                // Copy for ChatGPT Button (dedicated)
                if (isAssistant && message.content.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFF10A37F).withAlpha(40),
                      foregroundColor: const Color(0xFF10A37F),
                    ),
                    icon: const Icon(Icons.smart_toy_outlined, size: 14),
                    label: const Text('Gemini', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () => _copyMessageToClipboard(message.content, isForChatGpt: true),
                  ),
                // Copy full message button
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  tooltip: 'Copy full text',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copyMessageToClipboard(message.content),
                ),
              ],
            ),
          ),

          // ── Scrollable Message Body ───────────────────────
          Expanded(
            child: Scrollbar(
              controller: _messageScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _messageScrollController,
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  message.content.isEmpty
                      ? (message.isStreaming ? 'Thinking...' : 'No response text.')
                      : message.content,
                  style: GoogleFonts.firaCode(
                    fontSize: 13,
                    height: 1.5,
                    color: Colors.white.withAlpha(230),
                  ),
                ),
              ),
            ),
          ),

          // ── Per-message Token Usage Footer ─────────────────
          if (isAssistant)
            _buildMessageTokenFooter(message.tokenUsage, message.isStreaming),
        ],
      ),
    );
  }

  Widget _buildMessageTokenFooter(TokenUsage? usage, bool isStreaming) {
    final fmt = NumberFormat('#,###');
    String text;
    bool hasData = false;

    if (usage != null && !usage.isEmpty) {
      hasData = true;
      final parts = <String>[
        'Input: ${fmt.format(usage.inputTokens)}',
        'Output: ${fmt.format(usage.outputTokens)}',
        'Total: ${fmt.format(usage.totalTokens)}',
      ];
      if (usage.cacheReadTokens > 0) {
        parts.add('Cached: ${fmt.format(usage.cacheReadTokens)}');
      }
      text = parts.join(' | ');
    } else if (isStreaming) {
      text = 'Tokens: calculating...';
    } else {
      text = 'Tokens: N/A';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF131325),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
        border: Border(
          top: BorderSide(color: Colors.white.withAlpha(15)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 13,
            color: hasData ? const Color(0xFFA29BFE) : Colors.white38,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 10.5,
                fontFamily: GoogleFonts.firaCode().fontFamily,
                color: hasData ? Colors.white70 : Colors.white38,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (usage?.contextUsagePercent != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usage!.contextUsagePercent!,
                  minHeight: 4,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6C5CE7)),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${(usage.contextUsagePercent! * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 9.5, color: Colors.white60),
            ),
          ],
        ],
      ),
    );
  }

  // ── 5. Navigation Row ───────────────────────────────────────
  // Order Requirement 1: Previous / message counter / Next controls

  Widget _buildNavigationRow(TaskService tasks) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous Button
          FilledButton.tonalIcon(
            onPressed: tasks.canGoPrevious ? tasks.previousMessage : null,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
            label: const Text('Previous', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
          ),

          // Position Indicator: e.g. "3 of 12"
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E38),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: Text(
              tasks.positionIndicatorText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ),

          // Next Button
          FilledButton.tonalIcon(
            onPressed: tasks.canGoNext ? tasks.nextMessage : null,
            icon: const Text('Next', style: TextStyle(fontSize: 12)),
            label: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  // ── 6. Multiline Composer ───────────────────────────────────
  // Order Requirement 2: A multiline message composer

  Widget _buildComposer(TaskService tasks, DeviceService devices, ColorScheme colorScheme) {
    final hint = !devices.hasSelection
        ? 'Select a workspace above to message Antigravity...'
        : _isTerminalMode
            ? 'Enter command (e.g. git status, pytest)...'
            : 'Message Antigravity (multiline supported)...';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF18182E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isTerminalMode ? Colors.orange.withAlpha(80) : colorScheme.primary.withAlpha(50),
        ),
      ),
      child: TextField(
        controller: _inputController,
        minLines: 1,
        maxLines: 3,
        style: GoogleFonts.firaCode(fontSize: 13, color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13, color: Colors.white.withAlpha(70)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: InputBorder.none,
        ),
      ),
    );
  }

  // ── 7. Send Button and Connection/Task Status ───────────────
  // Order Requirement 3: Send button and connection/task status

  Widget _buildStatusBarAndSend(
    TaskService tasks,
    DeviceService devices,
    RelayService relay,
    ColorScheme colorScheme,
  ) {
    final isConnected = relay.isConnected;
    final isBusy = tasks.isSubmitting;

    String statusLabel = 'Ready';
    Color statusColor = Colors.greenAccent;

    if (!isConnected) {
      statusLabel = 'Disconnected';
      statusColor = Colors.redAccent;
    } else if (isBusy) {
      statusLabel = 'Sending task...';
      statusColor = Colors.blueAccent;
    } else if (tasks.currentMessage?.isStreaming == true) {
      statusLabel = 'Streaming...';
      statusColor = Colors.blueAccent;
    }

    final mode = tasks.permissionMode;
    final isFullAuto = mode == 'full-auto' || mode == 'auto';
    final isEdit = mode == 'accept-edits' || mode == 'edit';

    final Color badgeColor = isFullAuto
        ? Colors.redAccent
        : isEdit
            ? Colors.amberAccent
            : Colors.blueAccent;

    final IconData badgeIcon = isFullAuto
        ? Icons.bolt_rounded
        : isEdit
            ? Icons.edit_note_rounded
            : Icons.shield_outlined;

    final String badgeLabel = isFullAuto
        ? 'Full Auto'
        : isEdit
            ? 'Edit'
            : 'Review';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          // Connection & task status indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withAlpha(160),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Active permission mode chip in chat status area (always visible)
                GestureDetector(
                  onTap: () {
                    setState(() => _isNavPanelExpanded = !_isNavPanelExpanded);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: badgeColor.withAlpha(90),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeIcon, size: 11, color: badgeColor),
                        const SizedBox(width: 3),
                        Text(
                          badgeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                        if (tasks.isPermissionModeMismatch) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'CLI applied ${tasks.effectivePermissionMode} instead of $mode',
                            child: const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.orangeAccent),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Terminal Mode Toggle Chip
          GestureDetector(
            onTap: () => setState(() => _isTerminalMode = !_isTerminalMode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isTerminalMode ? Colors.orange.withAlpha(40) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isTerminalMode ? Colors.orange : Colors.white24,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.terminal,
                    size: 13,
                    color: _isTerminalMode ? Colors.orangeAccent : Colors.white60,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Terminal',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isTerminalMode ? Colors.orangeAccent : Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Send Button
          FilledButton.icon(
            onPressed: (devices.hasSelection && !isBusy) ? _submitMessage : null,
            icon: isBusy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(
                    _isTerminalMode ? Icons.play_arrow_rounded : Icons.send_rounded,
                    size: 16,
                  ),
            label: Text(_isTerminalMode ? 'Run' : 'Send', style: const TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              backgroundColor: _isTerminalMode ? Colors.orange.shade700 : const Color(0xFF6C5CE7),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
