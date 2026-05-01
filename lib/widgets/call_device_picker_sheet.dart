import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../services/call_coordinator_service.dart';

class CallDevicePickerSheet extends StatefulWidget {
  const CallDevicePickerSheet({
    super.key,
    required this.coordinator,
  });

  final CallCoordinatorService coordinator;

  @override
  State<CallDevicePickerSheet> createState() => _CallDevicePickerSheetState();
}

class _CallDevicePickerSheetState extends State<CallDevicePickerSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(widget.coordinator.refreshInputDevices());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: AnimatedBuilder(
          animation: widget.coordinator,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune_rounded),
                      const SizedBox(width: 10),
                      Text(
                        'Источники звука и видео',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: widget.coordinator.isRefreshingInputDevices
                            ? null
                            : () => unawaited(
                                  widget.coordinator.refreshInputDevices(),
                                ),
                        tooltip: 'Обновить устройства',
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (widget.coordinator.isRefreshingInputDevices &&
                      widget.coordinator.microphoneDevices.isEmpty &&
                      widget.coordinator.cameraDevices.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else ...[
                    _DeviceSection(
                      title: 'Микрофон',
                      emptyText: 'Микрофоны не найдены.',
                      icon: Icons.mic_rounded,
                      devices: widget.coordinator.microphoneDevices,
                      selectedDeviceId:
                          widget.coordinator.selectedMicrophoneDeviceId,
                      isSelecting: widget.coordinator.isSelectingMediaDevice,
                      onSelect: widget.coordinator.selectMicrophoneDevice,
                    ),
                    const SizedBox(height: 14),
                    _DeviceSection(
                      title: 'Камера',
                      emptyText: 'Камеры не найдены.',
                      icon: Icons.videocam_rounded,
                      devices: widget.coordinator.cameraDevices,
                      selectedDeviceId:
                          widget.coordinator.selectedCameraDeviceId,
                      isSelecting: widget.coordinator.isSelectingMediaDevice,
                      onSelect: widget.coordinator.selectCameraDevice,
                    ),
                  ],
                  if (widget.coordinator.devicePickerErrorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      widget.coordinator.devicePickerErrorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({
    required this.title,
    required this.emptyText,
    required this.icon,
    required this.devices,
    required this.selectedDeviceId,
    required this.isSelecting,
    required this.onSelect,
  });

  final String title;
  final String emptyText;
  final IconData icon;
  final List<MediaDevice> devices;
  final String? selectedDeviceId;
  final bool isSelecting;
  final Future<void> Function(MediaDevice device) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        if (devices.isEmpty)
          Text(
            emptyText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...devices.map(
            (device) {
              final selected = device.deviceId == selectedDeviceId;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon),
                title: Text(_deviceLabel(device)),
                trailing: selected
                    ? Icon(
                        Icons.check_rounded,
                        color: theme.colorScheme.primary,
                      )
                    : null,
                onTap: isSelecting ? null : () => unawaited(onSelect(device)),
              );
            },
          ),
      ],
    );
  }

  String _deviceLabel(MediaDevice device) {
    final label = device.label.trim();
    if (label.isNotEmpty) {
      return label;
    }
    if (device.kind == 'audioinput') {
      return 'Микрофон';
    }
    if (device.kind == 'videoinput') {
      return 'Камера';
    }
    return 'Устройство';
  }
}
