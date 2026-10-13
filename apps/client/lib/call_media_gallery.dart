import 'package:flutter/material.dart';

import 'media_gallery_layout.dart';

/// Contains presentation data only; room credentials never enter the gallery.
class ScreenStageStream {
  const ScreenStageStream({
    required this.id,
    required this.label,
    required this.video,
  });
  final String id;
  final String label;
  final Widget video;
}

/// Streams arrive remote-first. Automatic choice follows that order until
/// the viewer explicitly chooses a stream. Ended streams cannot stay pinned.
class MediaStageSelection {
  String? preferredId;
  bool expanded = false;

  String? activeId(Iterable<String> available) {
    final ids = available.toList();
    if (ids.contains(preferredId)) return preferredId;
    return ids.isEmpty ? null : ids.first;
  }

  void reconcile(Iterable<String> available) {
    final ids = available.toSet();
    if (!ids.contains(preferredId)) preferredId = null;
    if (ids.isEmpty) expanded = false;
  }
}

/// Enlarges the stage inside the call, leaving the call's controls outside
/// this widget. It never publishes, mutes or subscribes to a media track.
class CallMediaGallery extends StatefulWidget {
  const CallMediaGallery({
    super.key,
    required this.streams,
    required this.participants,
  });
  final List<ScreenStageStream> streams;
  final List<Widget> participants;

  @override
  State<CallMediaGallery> createState() => _CallMediaGalleryState();
}

class _CallMediaGalleryState extends State<CallMediaGallery> {
  final selection = MediaStageSelection();

  @override
  void didUpdateWidget(covariant CallMediaGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    selection.reconcile(widget.streams.map((stream) => stream.id));
  }

  Widget _grid(double width, {required bool hasStage}) => GridView.builder(
    key: const ValueKey('call-participants'),
    padding: EdgeInsets.all(hasStage ? 10 : 18),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: MediaGalleryLayout.columnsForWidth(
        width,
        watchingScreen: hasStage,
      ),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: hasStage
          ? 1.65
          : width < 550
          ? 1.55
          : 1.4,
    ),
    itemCount: widget.participants.length,
    itemBuilder: (_, index) => widget.participants[index],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final activeId = selection.activeId(
        widget.streams.map((stream) => stream.id),
      );
      if (activeId == null) return _grid(size.maxWidth, hasStage: false);
      final active = widget.streams.firstWhere(
        (stream) => stream.id == activeId,
      );
      final showGrid = !selection.expanded && size.maxHeight >= 220;
      return Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(
                  Icons.screen_share,
                  size: 18,
                  color: Color(0xFF55D6A0),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: widget.streams.length > 1
                      ? PopupMenuButton<String>(
                          key: const ValueKey('stream-selector'),
                          tooltip: 'Escolher transmissão',
                          initialValue: activeId,
                          onSelected: (id) =>
                              setState(() => selection.preferredId = id),
                          itemBuilder: (_) => widget.streams
                              .map(
                                (stream) => PopupMenuItem<String>(
                                  value: stream.id,
                                  child: Row(
                                    children: [
                                      Icon(
                                        stream.id == activeId
                                            ? Icons.check
                                            : Icons.screen_share,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          stream.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'AO VIVO • ${active.label}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.expand_more, size: 18),
                              ],
                            ),
                          ),
                        )
                      : Text(
                          'AO VIVO • ${active.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                IconButton(
                  key: const ValueKey('expand-stage'),
                  tooltip: selection.expanded
                      ? 'Mostrar participantes'
                      : 'Ampliar transmissão',
                  onPressed: () =>
                      setState(() => selection.expanded = !selection.expanded),
                  icon: Icon(
                    selection.expanded
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          Expanded(
            flex: showGrid
                ? MediaGalleryLayout.stageFlexForWidth(size.maxWidth)
                : 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Container(
                key: const ValueKey('screen-stage'),
                decoration: BoxDecoration(
                  color: const Color(0xFF101216),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF4C5261)),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox.expand(child: active.video),
              ),
            ),
          ),
          if (showGrid)
            Expanded(flex: 4, child: _grid(size.maxWidth, hasStage: true)),
        ],
      );
    },
  );
}

/// The identity and microphone state stay visible even when video is present.
class VoiceParticipantTile extends StatelessWidget {
  const VoiceParticipantTile({
    super.key,
    required this.name,
    required this.microphoneEnabled,
    this.self = false,
    this.speaking = false,
    this.video,
  });
  final String name;
  final bool microphoneEnabled;
  final bool self;
  final bool speaking;
  final Widget? video;

  @override
  Widget build(BuildContext context) {
    final label = self
        ? 'Você'
        : name.isEmpty
        ? 'Participante'
        : name;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF24262D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: speaking ? const Color(0xFF55D6A0) : const Color(0xFF373A44),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child:
                video ??
                Center(
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF3B83DD),
                    child: Text(
                      name.isEmpty
                          ? '?'
                          : String.fromCharCode(name.runes.first).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
          ),
          Container(
            color: const Color(0xE6191A20),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Icon(
                  microphoneEnabled ? Icons.mic : Icons.mic_off,
                  size: 14,
                  semanticLabel: microphoneEnabled
                      ? 'Microfone ligado'
                      : 'Microfone desligado',
                  color: microphoneEnabled
                      ? Colors.white70
                      : const Color(0xFFFF8A92),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (speaking)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.graphic_eq,
                      size: 14,
                      color: Color(0xFF55D6A0),
                      semanticLabel: 'Falando',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
