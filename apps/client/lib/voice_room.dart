import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:livekit_noise_filter/livekit_noise_filter.dart';

import 'noise_profile.dart';
import 'call_media_gallery.dart';

/// Only accepts short-lived credentials issued by the authenticated Veylor API.
/// Never logs, persists, displays or passes the token through a navigation URL.
class MediaAccess {
  const MediaAccess({required this.url, required this.token});
  final String url;
  final String token;

  static MediaAccess fromJson(Map<String, dynamic> result) {
    final rawUrl = result['url'];
    final token = result['token'];
    if (rawUrl is! String ||
        token is! String ||
        token.length < 48 ||
        token.length > 8192) {
      throw const FormatException('Credenciais de voz incompletas.');
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'wss' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasPort ||
        uri.path != '' && uri.path != '/') {
      throw const FormatException('Servidor de voz precisa de WSS válido.');
    }
    return MediaAccess(url: uri.toString(), token: token);
  }
}

/// A real LiveKit room; microphone is OFF until explicitly enabled.
/// The page can stay open while the user speaks or watches a screen stream.
class VeylorVoiceRoom extends StatefulWidget {
  const VeylorVoiceRoom({
    super.key,
    required this.channelName,
    required this.access,
  });
  final String channelName;
  final MediaAccess access;
  @override
  State<VeylorVoiceRoom> createState() => _VeylorVoiceRoomState();
}

class _VeylorVoiceRoomState extends State<VeylorVoiceRoom> {
  final lk.Room room = lk.Room(
    roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
  );
  bool connecting = true,
      connected = false,
      microphone = false,
      camera = false,
      sharing = false;
  bool working = false, aiSupported = false, leaving = false;
  NoiseProfile noiseProfile = NoiseProfile.standard;
  LiveKitNoiseFilter? noiseFilter;
  String? failure;

  bool get controlsEnabled =>
      connected &&
      !working &&
      !leaving &&
      room.connectionState == lk.ConnectionState.connected;

  void _syncLocalMedia() {
    if (room.connectionState == lk.ConnectionState.disconnected) {
      microphone = false;
      camera = false;
      sharing = false;
      return;
    }
    final participant = room.localParticipant;
    microphone = participant?.isMicrophoneEnabled() ?? false;
    camera = participant?.isCameraEnabled() ?? false;
    sharing = participant?.isScreenShareEnabled() ?? false;
  }

  @override
  void initState() {
    super.initState();
    room.addListener(_onRoomUpdate);
    unawaited(_connect());
    unawaited(_checkAiSupport());
  }

  void _onRoomUpdate() {
    if (!mounted) return;
    setState(() {
      if (room.connectionState == lk.ConnectionState.disconnected &&
          !connecting) {
        connected = false;
        microphone = false;
        camera = false;
        sharing = false;
        failure ??= 'A ligação foi encerrada. Saia e entre novamente no canal.';
      } else if (room.connectionState == lk.ConnectionState.connected &&
          !connecting) {
        connected = true;
        if (!working) _syncLocalMedia();
      }
    });
  }

  Future<void> _checkAiSupport() async {
    if (!NoiseCapability.supportsAi(
      isAndroid: Platform.isAndroid,
      isIos: Platform.isIOS,
      isMacOs: Platform.isMacOS,
    ))
      return;
    try {
      final supported = await LiveKitNoiseFilter.isSupported();
      if (mounted) setState(() => aiSupported = supported);
    } catch (_) {
      // The optional processor is never enabled when unsupported.
      if (mounted) setState(() => aiSupported = false);
    }
  }

  lk.AudioCaptureOptions _micOptions(NoiseProfile profile) =>
      lk.AudioCaptureOptions(
        echoCancellation: true,
        autoGainControl: true,
        highPassFilter: true,
        noiseSuppression: NoiseCapability.useNativeSuppression(profile),
        voiceIsolation: NoiseCapability.useNativeSuppression(profile),
        processor: profile == NoiseProfile.ai ? noiseFilter : null,
      );

  Future<void> _chooseNoiseProfile(NoiseProfile selected) => _action(() async {
    if (selected == NoiseProfile.ai && !aiSupported) {
      throw StateError('Este dispositivo não possui filtro de IA compatível.');
    }
    if (selected == noiseProfile) return;
    final participant = room.localParticipant;
    if (participant == null) throw StateError('Participante indisponível');
    final previous = noiseProfile;
    if (selected == NoiseProfile.ai) noiseFilter ??= LiveKitNoiseFilter();
    // LiveKit reuses a muted publication on unmute; it DOES NOT rebuild its
    // processor. Unpublish the old microphone source to apply a new mode.
    // This is safe even with the mic muted and never starts it by accident.
    final existing = participant.getTrackPublicationBySource(
      lk.TrackSource.microphone,
    );
    if (existing != null) await participant.removePublishedTrack(existing.sid);
    if (microphone) {
      try {
        await participant.setMicrophoneEnabled(
          true,
          audioCaptureOptions: _micOptions(selected),
        );
      } catch (_) {
        // Best-effort restore the previous capture mode to avoid losing voice.
        try {
          await participant.setMicrophoneEnabled(
            true,
            audioCaptureOptions: _micOptions(previous),
          );
        } catch (_) {
          if (mounted) setState(() => microphone = false);
        }
        rethrow;
      }
    }
    if (mounted) setState(() => noiseProfile = selected);
  });

  Future<void> _connect() async {
    try {
      await room
          .connect(widget.access.url, widget.access.token)
          .timeout(const Duration(seconds: 30));
      // Privacy: do not access microphone/camera without a user action.
      if (mounted)
        setState(() {
          connecting = false;
          connected = true;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          connecting = false;
          failure = 'Não foi possível entrar. Verifique conexão, servidor LiveKit e permissões.';
        });
    }
  }

  Future<void> _action(Future<void> Function() operation) async {
    if (!mounted || !controlsEnabled) return;
    setState(() => working = true);
    try {
      await operation();
      if (mounted) setState(() => failure = null);
    } catch (_) {
      if (mounted)
        setState(
          () => failure = 'A operação de mídia falhou. Verifique permissões ou tente novamente.',
        );
    } finally {
      if (mounted)
        setState(() {
          working = false;
          _syncLocalMedia();
        });
    }
  }

  Future<void> _toggleMic() => _action(() async {
    final participant = room.localParticipant;
    if (participant == null) throw StateError('Local participant not ready');
    if (!microphone && noiseProfile == NoiseProfile.ai) {
      if (!aiSupported)
        throw StateError('Filtro de IA não suportado neste dispositivo');
      noiseFilter ??= LiveKitNoiseFilter();
    }
    final enabled = !participant.isMicrophoneEnabled();
    await participant.setMicrophoneEnabled(
      enabled,
      audioCaptureOptions: _micOptions(noiseProfile),
    );
  });

  Future<void> _toggleCamera() => _action(() async {
    final participant = room.localParticipant;
    if (participant == null) throw StateError('Participante indisponível');
    // No camera permission or publishing until the user clicks this button.
    final enabled = !participant.isCameraEnabled();
    await participant.setCameraEnabled(
      enabled,
      cameraCaptureOptions: const lk.CameraCaptureOptions(
        params: lk.VideoParametersPresets.h720_169,
        maxFrameRate: 24.0,
      ),
    );
  });

  Future<void> _toggleShare() => _action(() async {
    final participant = room.localParticipant;
    if (participant == null) throw StateError('Local participant not ready');
    if (sharing) {
      await participant.setScreenShareEnabled(false);
      if (mounted) setState(() => sharing = false);
      return;
    }
    // A desktop user must actively choose exactly what they share.
    if (!Platform.isWindows && !Platform.isMacOS) {
      throw UnsupportedError(
        'Seleção de tela ainda indisponível neste sistema.',
      );
    }
    final source = await showDialog<dynamic>(
      context: context,
      builder: (_) => lk.ScreenSelectDialog(),
    );
    if (source == null ||
        !mounted ||
        leaving ||
        room.connectionState != lk.ConnectionState.connected)
      return;
    final permitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Iniciar transmissão de tela?'),
        content: const Text(
          'Outras pessoas neste canal poderão ver a janela ou tela escolhida. '
          'Não compartilhe senhas, mensagens privadas ou informações pessoais. '
          'O compartilhamento não começa sem confirmação.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Compartilhar'),
          ),
        ],
      ),
    );
    if (permitted != true ||
        !mounted ||
        leaving ||
        room.connectionState != lk.ConnectionState.connected)
      return;
    // Use a managed screen-share source. This ensures 'stop sharing' unpublishes
    // and releases the SAME source that was started here.
    await participant.setScreenShareEnabled(
      true,
      screenShareCaptureOptions: lk.ScreenShareCaptureOptions(
        sourceId: source.id,
        maxFrameRate: 15.0,
        params: lk.VideoParametersPresets.screenShareH1080FPS15,
      ),
    );
    if (mounted) setState(() => sharing = true);
  });

  Future<void> _leave() async {
    if (leaving) return;
    setState(() => leaving = true);
    try {
      await room.disconnect().timeout(const Duration(seconds: 5));
    } catch (_) {
      // UI can still close; teardown continues in dispose.
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cleanup() async {
    try {
      await room.disconnect();
    } catch (_) {}
    try {
      await room.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    room.removeListener(_onRoomUpdate);
    unawaited(_cleanup());
    super.dispose();
  }

  /// Prefer someone else's active share, then our own. Muted and unsubscribed
  /// publications are ignored so a finished stream cannot block the gallery.
  List<ScreenStageStream> _activeScreenStreams(List<lk.Participant> others) {
    final people = <lk.Participant>[
      ...others,
      if (room.localParticipant != null) room.localParticipant!,
    ];
    final streams = <ScreenStageStream>[];
    for (final participant in people) {
      for (final publication in participant.videoTrackPublications) {
        if (!publication.isScreenShare ||
            publication.muted ||
            publication.track is! lk.VideoTrack)
          continue;
        final isSelf = participant == room.localParticipant;
        if (!isSelf && !publication.subscribed) continue;
        final label = isSelf
            ? 'Sua transmissão'
            : participant.name.isNotEmpty
            ? participant.name
            : 'Participante';
        streams.add(
          ScreenStageStream(
            id: publication.sid,
            label: label,
            video: lk.VideoTrackRenderer(
              publication.track as lk.VideoTrack,
              key: ValueKey(publication.sid),
              fit: lk.VideoViewFit.contain,
            ),
          ),
        );
      }
    }
    return streams;
  }

  Widget _participantCard(lk.Participant participant, {bool self = false}) {
    lk.VideoTrack? visible;
    for (final publication in participant.videoTrackPublications) {
      if (publication.isScreenShare) continue;
      if (!publication.muted &&
          publication.track is lk.VideoTrack &&
          (self || publication.subscribed)) {
        visible = publication.track as lk.VideoTrack;
        break;
      }
    }
    return VoiceParticipantTile(
      key: ValueKey(participant.identity),
      name: participant.name,
      self: self,
      speaking: participant.audioLevel > .1,
      microphoneEnabled: participant.isMicrophoneEnabled(),
      video: visible == null ? null : lk.VideoTrackRenderer(visible),
    );
  }

  Widget _noiseMenu({required bool compact}) => PopupMenuButton<NoiseProfile>(
    tooltip: 'Redução de ruído do microfone',
    enabled: controlsEnabled,
    onSelected: (mode) => unawaited(_chooseNoiseProfile(mode)),
    itemBuilder: (_) => [
      for (final mode in NoiseProfile.values)
        PopupMenuItem<NoiseProfile>(
          value: mode,
          enabled: mode != NoiseProfile.ai || aiSupported,
          child: Row(
            children: [
              Icon(
                mode == noiseProfile
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(NoiseCapability.label(mode)),
            ],
          ),
        ),
    ],
    icon: compact ? const Icon(Icons.graphic_eq) : null,
    child: compact
        ? null
        : Chip(
            avatar: const Icon(Icons.graphic_eq, size: 18),
            label: Text('Ruído: ${NoiseCapability.label(noiseProfile)}'),
          ),
  );

  Widget _controls() => LayoutBuilder(
    builder: (context, size) {
      final canShare = Platform.isWindows || Platform.isMacOS;
      if (size.maxWidth < 550) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton.filledTonal(
              tooltip: microphone ? 'Silenciar' : 'Ativar microfone',
              onPressed: controlsEnabled ? _toggleMic : null,
              icon: Icon(microphone ? Icons.mic : Icons.mic_off),
            ),
            _noiseMenu(compact: true),
            IconButton.filledTonal(
              tooltip: camera ? 'Desligar câmera' : 'Ligar câmera',
              onPressed: controlsEnabled ? _toggleCamera : null,
              icon: Icon(camera ? Icons.videocam : Icons.videocam_off),
            ),
            if (canShare)
              IconButton.filledTonal(
                tooltip: sharing ? 'Parar transmissão' : 'Compartilhar tela',
                onPressed: controlsEnabled ? _toggleShare : null,
                icon: Icon(
                  sharing ? Icons.stop_screen_share : Icons.screen_share,
                ),
              ),
            IconButton.filled(
              tooltip: 'Desconectar',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFCA4751),
              ),
              onPressed: leaving ? null : _leave,
              icon: const Icon(Icons.call_end),
            ),
          ],
        );
      }
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.tonalIcon(
            onPressed: controlsEnabled ? _toggleMic : null,
            icon: Icon(microphone ? Icons.mic : Icons.mic_off),
            label: Text(microphone ? 'Silenciar' : 'Ativar microfone'),
          ),
          _noiseMenu(compact: false),
          FilledButton.tonalIcon(
            onPressed: controlsEnabled ? _toggleCamera : null,
            icon: Icon(camera ? Icons.videocam : Icons.videocam_off),
            label: Text(camera ? 'Desligar câmera' : 'Ligar câmera'),
          ),
          if (canShare)
            FilledButton.tonalIcon(
              onPressed: controlsEnabled ? _toggleShare : null,
              icon: Icon(
                sharing ? Icons.stop_screen_share : Icons.screen_share,
              ),
              label: Text(sharing ? 'Parar transmissão' : 'Compartilhar tela'),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFCA4751),
            ),
            onPressed: leaving ? null : _leave,
            icon: const Icon(Icons.call_end),
            label: const Text('Desconectar'),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final others = room.remoteParticipants.values.toList();
    final people = <lk.Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...others,
    ];
    final screenStreams = _activeScreenStreams(others);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF202127),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.channelName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              connecting
                  ? 'Conectando...'
                  : room.connectionState == lk.ConnectionState.reconnecting
                  ? 'Reconectando áudio e vídeo...'
                  : connected
                  ? 'Canal de voz • ${people.length} participante(s)'
                  : 'Desconectado',
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sair do canal',
            onPressed: leaving ? null : _leave,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (failure != null)
              MaterialBanner(
                content: Text(failure!),
                leading: const Icon(Icons.warning_amber_rounded),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => failure = null),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            Expanded(
              child: connecting
                  ? const Center(child: CircularProgressIndicator())
                  : !connected
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Sala indisponível.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _leave,
                            child: const Text('Voltar'),
                          ),
                        ],
                      ),
                    )
                  : people.isEmpty
                  ? const Center(child: Text('Aguardando participantes...'))
                  : CallMediaGallery(
                      streams: screenStreams,
                      participants: people
                          .map(
                            (participant) => _participantCard(
                              participant,
                              self: participant == room.localParticipant,
                            ),
                          )
                          .toList(),
                    ),
            ),
            if (connected)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  NoiseCapability.description(noiseProfile),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            Container(
              color: const Color(0xFF202127),
              padding: const EdgeInsets.all(10),
              child: _controls(),
            ),
          ],
        ),
      ),
    );
  }
}
