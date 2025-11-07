import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/screens/primary_scaffold.dart';
import '../../../../core/utils/audio_utils.dart';
import '../../application/audio_controller.dart';

class AudioPage extends StatefulWidget {
  const AudioPage({super.key});

  static const String routeName = '/audio';

  @override
  State<AudioPage> createState() => _AudioPageState();
}

class _AudioPageState extends State<AudioPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioController>(
      builder: (context, controller, _) {
        return PrimaryScaffold(
          title: AppConstants.appTitle,
          actions: [
            if (controller.hasAudio && !controller.isProcessing)
              IconButton(
                tooltip: 'Share audio',
                icon: const Icon(Icons.share),
                onPressed: controller.shareCurrent,
              ),
          ],
          body: Column(
            children: [
              if (controller.isProcessing)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxWidth = constraints.maxWidth.clamp(360.0, 600.0);
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (controller.errorMessage != null)
                                _ErrorBanner(
                                  message: controller.errorMessage!,
                                  controller: controller,
                                ),
                              if (controller.errorMessage != null)
                                const SizedBox(height: 16),
                              if (!controller.hasAudio) ...[
                                _EmptyState(controller: controller),
                                const SizedBox(height: 24),
                              ],
                              if (controller.hasAudio) ...[
                                _PlaybackControls(controller: controller),
                                const SizedBox(height: 24),
                                _AudioControls(controller: controller),
                                const SizedBox(height: 24),
                              ],
                              _InputSection(controller: controller),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.controller});

  final String message;
  final AudioController? controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPermissionError =
        message.toLowerCase().contains('permission') ||
        message.toLowerCase().contains('microphone');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 20,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
          if (isPermissionError)
            TextButton(
              onPressed: () async {
                await openAppSettings();
              },
              child: Text(
                'Open Settings',
                style: TextStyle(
                  color: colorScheme.onErrorContainer,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});

  final AudioController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.music_note, size: 64, color: colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'No audio loaded',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Record or import audio to get started',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.controller});

  final AudioController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PositionSlider(controller: controller),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filled(
              onPressed: controller.canPlay ? controller.togglePlayback : null,
              iconSize: 32,
              icon: Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: controller.canPlay ? controller.stopPlayback : null,
              icon: const Icon(Icons.stop),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<PlaybackDirection>(
          segments: const [
            ButtonSegment(
              value: PlaybackDirection.forward,
              icon: Icon(Icons.play_arrow, size: 18),
              label: Text('Forward'),
            ),
            ButtonSegment(
              value: PlaybackDirection.reverse,
              icon: Icon(Icons.rotate_left, size: 18),
              label: Text('Reverse'),
            ),
          ],
          selected: {controller.direction},
          onSelectionChanged: (values) => controller.setDirection(values.first),
        ),
      ],
    );
  }
}

class _AudioControls extends StatelessWidget {
  const _AudioControls({required this.controller});

  final AudioController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TitledSlider(
              title: 'Speed',
              icon: Icons.speed,
              value: controller.speed,
              min: AppConstants.minSpeed,
              max: AppConstants.maxSpeed,
              onChanged: (value) => controller.setSpeed(value),
            ),
            const SizedBox(height: 16),
            _TitledSlider(
              title: 'Pitch',
              icon: Icons.tune,
              value: controller.pitch,
              min: AppConstants.minPitch,
              max: AppConstants.maxPitch,
              onChanged: (value) => controller.setPitch(value),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Loop', style: Theme.of(context).textTheme.titleSmall),
                Switch(
                  value: controller.isLooping,
                  onChanged: (value) => controller.toggleLoop(value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InputSection extends StatelessWidget {
  const _InputSection({required this.controller});

  final AudioController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Input',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: controller.isProcessing
                  ? null
                  : controller.isRecording
                  ? controller.stopRecording
                  : controller.startRecording,
              icon: Icon(controller.isRecording ? Icons.stop : Icons.mic),
              label: Text(controller.isRecording ? 'Stop Recording' : 'Record'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: (controller.isProcessing || controller.isPickingFile)
                  ? null
                  : controller.pickAudio,
              icon: const Icon(Icons.upload_file),
              label: const Text('Import File'),
            ),
            if (controller.hasAudio) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: controller.shareCurrent,
                icon: const Icon(Icons.share),
                label: const Text('Share Audio'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TitledSlider extends StatelessWidget {
  const _TitledSlider({
    required this.title,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: 20,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _PositionSlider extends StatelessWidget {
  const _PositionSlider({required this.controller});

  final AudioController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: controller.durationStream,
      builder: (context, snapshot) {
        final duration = snapshot.data ?? controller.duration ?? Duration.zero;
        if (duration == Duration.zero) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<Duration>(
          stream: controller.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final progress = position.inMilliseconds.clamp(
              0,
              duration.inMilliseconds,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: duration.inMilliseconds == 0
                      ? 0
                      : progress / duration.inMilliseconds,
                  min: 0,
                  max: 1,
                  onChanged: controller.canPlay
                      ? (value) => controller.seek(
                          Duration(
                            milliseconds: (value * duration.inMilliseconds)
                                .round(),
                          ),
                        )
                      : null,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AudioUtils.formatDuration(position),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      AudioUtils.formatDuration(duration),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
