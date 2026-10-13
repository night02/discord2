import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:livekit_noise_filter/livekit_noise_filter.dart';

import 'noise_profile.dart';
import 'media_gallery_layout.dart';

/// Only accepts short-lived credentials issued by the authenticated Veylor API.
/// Never logs, persists, displays or passes the token through a navigation URL.
class MediaAccess {
  const MediaAccess({required this.url, required this.token});
  final String url;
  final String token;

  static MediaAccess fromJson(Map<String,dynamic> result) {
    final rawUrl = result['url'];
    final token = result['token'];
    if (rawUrl is! String || token is! String || token.length < 48 ||
        token.length > 8192) {
      throw const FormatException('Credenciais de voz incompletas.');
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'wss' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasFragment || uri.hasPort ||
        uri.path != '' && uri.path != '/') {
      throw const FormatException('Servidor de voz precisa de WSS válido.');
    }
    return MediaAccess(url:uri.toString(), token:token);
  }
}

/// A real LiveKit room; microphone is OFF until explicitly enabled.
/// The page can stay open while the user speaks or watches a screen stream.
class VeylorVoiceRoom extends StatefulWidget {
  const VeylorVoiceRoom({
    super.key, required this.channelName, required this.access,
  });
  final String channelName;
  final MediaAccess access;
  @override
  State<VeylorVoiceRoom> createState()=>_VeylorVoiceRoomState();
}

class _VeylorVoiceRoomState extends State<VeylorVoiceRoom> {
  final lk.Room room = lk.Room(roomOptions:const lk.RoomOptions(
    adaptiveStream:true,dynacast:true,
  ));
  bool connecting=true, connected=false, microphone=false, camera=false, sharing=false;
  bool working=false, aiSupported=false;
  NoiseProfile noiseProfile=NoiseProfile.standard;
  LiveKitNoiseFilter? noiseFilter;
  String? failure;

  @override
  void initState() {
    super.initState();
    room.addListener(_onRoomUpdate);
    unawaited(_connect());
    unawaited(_checkAiSupport());
  }

  void _onRoomUpdate() {
    if(!mounted)return;
    setState(() {
      if(room.connectionState==lk.ConnectionState.disconnected && !connecting) {
        connected=false;
        microphone=false;
        camera=false;
        sharing=false;
        failure ??='A ligação foi encerrada. Saia e entre novamente no canal.';
      } else if(room.connectionState==lk.ConnectionState.connected && !connecting){
        connected=true;
      }
    });
  }

  Future<void> _checkAiSupport() async {
    if(!NoiseCapability.supportsAi(isAndroid:Platform.isAndroid,
        isIos:Platform.isIOS,isMacOs:Platform.isMacOS))return;
    try{
      final supported=await LiveKitNoiseFilter.isSupported();
      if(mounted)setState(()=>aiSupported=supported);
    }catch(_){
      // The optional processor is never enabled when unsupported.
      if(mounted)setState(()=>aiSupported=false);
    }
  }

  lk.AudioCaptureOptions _micOptions(NoiseProfile profile) =>
      lk.AudioCaptureOptions(
        echoCancellation:true,
        autoGainControl:true,
        highPassFilter:true,
        noiseSuppression:NoiseCapability.useNativeSuppression(profile),
        voiceIsolation:NoiseCapability.useNativeSuppression(profile),
        processor:profile==NoiseProfile.ai?noiseFilter:null,
      );

  Future<void> _chooseNoiseProfile(NoiseProfile selected) => _action(() async {
    if(selected==NoiseProfile.ai&&!aiSupported){
      throw StateError('Este dispositivo não possui filtro de IA compatível.');
    }
    if(selected==noiseProfile)return;
    final participant=room.localParticipant;
    if(participant==null)throw StateError('Participante indisponível');
    final previous=noiseProfile;
    if(selected==NoiseProfile.ai)noiseFilter ??= LiveKitNoiseFilter();
    // LiveKit reuses a muted publication on unmute; it DOES NOT rebuild its
    // processor. Unpublish the old microphone source to apply a new mode.
    // This is safe even with the mic muted and never starts it by accident.
    final existing=participant.getTrackPublicationBySource(lk.TrackSource.microphone);
    if(existing!=null)await participant.removePublishedTrack(existing.sid);
    if(microphone){
      try{
        await participant.setMicrophoneEnabled(true,
          audioCaptureOptions:_micOptions(selected));
      }catch(_){
        // Best-effort restore the previous capture mode to avoid losing voice.
        try{
          await participant.setMicrophoneEnabled(true,
            audioCaptureOptions:_micOptions(previous));
        }catch(_){if(mounted)setState(()=>microphone=false);}
        rethrow;
      }
    }
    if(mounted)setState(()=>noiseProfile=selected);
  });

  Future<void> _connect() async {
    try {
      await room.connect(widget.access.url, widget.access.token)
        .timeout(const Duration(seconds:30));
      // Privacy: do not access microphone/camera without a user action.
      if(mounted) setState(() {connecting=false;connected=true;});
    } catch (_) {
      if(mounted) setState(() {
        connecting=false;
        failure='Não foi possível entrar. Verifique conexão, servidor LiveKit e permissões.';
      });
    }
  }

  Future<void> _action(Future<void> Function() operation) async {
    if(working||!connected||room.connectionState!=lk.ConnectionState.connected)return;
    setState(()=>working=true);
    try {
      await operation();
      if(mounted)setState(()=>failure=null);
    } catch (_) {
      if(mounted)setState(()=>failure='A operação de mídia falhou. Verifique permissões ou tente novamente.');
    } finally {
      if(mounted)setState(()=>working=false);
    }
  }

  Future<void> _toggleMic()=>_action(() async {
    final participant=room.localParticipant;
    if(participant==null)throw StateError('Local participant not ready');
    if(!microphone&&noiseProfile==NoiseProfile.ai){
      if(!aiSupported)throw StateError('Filtro de IA não suportado neste dispositivo');
      noiseFilter ??= LiveKitNoiseFilter();
    }
    await participant.setMicrophoneEnabled(!microphone,
      audioCaptureOptions:_micOptions(noiseProfile));
    if(mounted)setState(()=>microphone=!microphone);
  });

  Future<void> _toggleCamera()=>_action(() async {
    final participant=room.localParticipant;
    if(participant==null)throw StateError('Participante indisponível');
    // No camera permission or publishing until the user clicks this button.
    await participant.setCameraEnabled(!camera,
      cameraCaptureOptions:const lk.CameraCaptureOptions(
        params:lk.VideoParametersPresets.h720_169,
        maxFrameRate:24.0,
      ));
    if(mounted)setState(()=>camera=!camera);
  });

  Future<void> _toggleShare()=>_action(() async {
    final participant=room.localParticipant;
    if(participant==null)throw StateError('Local participant not ready');
    if(sharing) {
      await participant.setScreenShareEnabled(false);
      if(mounted)setState(()=>sharing=false);
      return;
    }
    // A desktop user must actively choose exactly what they share.
    if(!Platform.isWindows&&!Platform.isMacOS) {
      throw UnsupportedError('Seleção de tela ainda indisponível neste sistema.');
    }
    final source=await showDialog<dynamic>(
      context:context,builder:(_)=>lk.ScreenSelectDialog());
    if(source==null || !mounted)return;
    final permitted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Iniciar transmissão de tela?'),
      content:const Text('Outras pessoas neste canal poderão ver a janela ou tela escolhida. '
          'Não compartilhe senhas, mensagens privadas ou informações pessoais. '
          'O compartilhamento não começa sem confirmação.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Compartilhar'))
      ],
    ));
    if(permitted!=true)return;
    // Use a managed screen-share source. This ensures 'stop sharing' unpublishes
    // and releases the SAME source that was started here.
    await participant.setScreenShareEnabled(true,
      screenShareCaptureOptions:lk.ScreenShareCaptureOptions(
        sourceId:source.id,
        maxFrameRate:15.0,
        params:lk.VideoParametersPresets.screenShareH1080FPS15,
      ));
    if(mounted)setState(()=>sharing=true);
  });

  Future<void> _leave() async {
    try {
      await room.disconnect().timeout(const Duration(seconds:5));
    } catch (_) {
      // UI can still close; teardown continues in dispose.
    }
    if(mounted)Navigator.of(context).pop();
  }

  Future<void> _cleanup() async {
    try { await room.disconnect(); } catch (_) {}
    try { await room.dispose(); } catch (_) {}
  }

  @override
  void dispose() {
    room.removeListener(_onRoomUpdate);
    unawaited(_cleanup());
    super.dispose();
  }

  /// Prefer someone else's active share, then our own. Muted and unsubscribed
  /// publications are ignored so a finished stream cannot block the gallery.
  ({lk.Participant participant, lk.VideoTrack track})? _activeScreenStage(
      List<lk.Participant> others) {
    final people=<lk.Participant>[
      ...others,
      if(room.localParticipant!=null)room.localParticipant!,
    ];
    for(final participant in people) {
      for(final publication in participant.videoTrackPublications) {
        if(!publication.isScreenShare || publication.muted ||
            publication.track is! lk.VideoTrack)continue;
        final isSelf=participant==room.localParticipant;
        if(!isSelf&&!publication.subscribed)continue;
        return (participant:participant,track:publication.track as lk.VideoTrack);
      }
    }
    return null;
  }

  Widget _screenStage(
      ({lk.Participant participant, lk.VideoTrack track}) active) {
    final self=active.participant==room.localParticipant;
    final who=self?'Sua transmissão':
      active.participant.name.isNotEmpty
      ?active.participant.name:'Participante';
    return Container(
      decoration:BoxDecoration(
        color:const Color(0xFF101216),
        borderRadius:BorderRadius.circular(16),
        border:Border.all(color:const Color(0xFF4C5261)),
      ),
      clipBehavior:Clip.antiAlias,
      child:Stack(fit:StackFit.expand,children:[
        // The SDK owns the subscribed video track and its adaptive lifecycle.
        lk.VideoTrackRenderer(active.track),
        Positioned(left:12,top:12,
          child:Container(
            padding:const EdgeInsets.symmetric(horizontal:10,vertical:6),
            decoration:BoxDecoration(color:const Color(0xD915171B),
              borderRadius:BorderRadius.circular(8)),
            child:Row(mainAxisSize:MainAxisSize.min,children:[
              const Icon(Icons.screen_share,size:15,color:Color(0xFF55D6A0)),
              const SizedBox(width:8),
              Text('AO VIVO • $who',
                style:const TextStyle(color:Colors.white,fontSize:12,
                  fontWeight:FontWeight.w600)),
            ]),
          )),
      ]),
    );
  }

  Widget _participantCard(lk.Participant participant,
      {bool self=false,bool screenOnStage=false}) {
    lk.VideoTrack? visible;
    final tracks=participant.videoTrackPublications.toList();
    // With a dedicated screen stage, use the camera for thumbnails. A stream
    // must never appear as a duplicated tiny share inside a participant tile.
    tracks.sort((a,b)=>(a.isScreenShare?1:0).compareTo(b.isScreenShare?1:0));
    for(final publication in tracks) {
      if(screenOnStage && publication.isScreenShare)continue;
      if(!publication.muted && publication.track is lk.VideoTrack &&
          (self || publication.subscribed)) {
        visible=publication.track as lk.VideoTrack;
        break;
      }
    }
    return Container(
      decoration:BoxDecoration(
        color:const Color(0xFF24262D),
        borderRadius:BorderRadius.circular(14),
        border:Border.all(color:participant.audioLevel>.1
          ?const Color(0xFF55D6A0):const Color(0xFF373A44),width:2)),
      clipBehavior:Clip.antiAlias,
      child:visible!=null?lk.VideoTrackRenderer(visible):
      Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
        CircleAvatar(radius:26,backgroundColor:const Color(0xFF3B83DD),
          child:Text(participant.name.isNotEmpty
              ?participant.name[0].toUpperCase():'?',
              style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold))),
        const SizedBox(height:10),
        Text(self?'Você':participant.name.isNotEmpty?participant.name:'Participante',
            maxLines:1,overflow:TextOverflow.ellipsis),
        if(self && !camera)const Padding(padding:EdgeInsets.only(top:4),
          child:Text('Sua câmera está desligada',style:TextStyle(
            fontSize:11,color:Colors.white60))),
      ])));
  }

  Widget _participantsGrid(List<lk.Participant> people,
      {required bool hasStage}) {
    return LayoutBuilder(builder:(context,size) {
      final columns=MediaGalleryLayout.columnsForWidth(
        size.maxWidth,watchingScreen:hasStage);
      return GridView.builder(
        padding:EdgeInsets.all(hasStage?10:18),
        gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:columns,
          mainAxisSpacing:10,crossAxisSpacing:10,
          childAspectRatio:hasStage?1.65:size.maxWidth<550?1.55:1.4),
        itemCount:people.length,
        itemBuilder:(ctx,i)=>_participantCard(people[i],
          self:people[i]==room.localParticipant,
          screenOnStage:hasStage),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final others=room.remoteParticipants.values.toList();
    final people=<lk.Participant>[
      if(room.localParticipant!=null)room.localParticipant!,
      ...others
    ];
    final screenStage=_activeScreenStage(others);
    return Scaffold(
      appBar:AppBar(
        backgroundColor:const Color(0xFF202127),
        title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(widget.channelName,style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
          Text(connecting?'Conectando...'
            :room.connectionState==lk.ConnectionState.reconnecting?'Reconectando áudio e vídeo...'
            :connected?'Canal de voz • ${people.length} participante(s)':'Desconectado',
            style:const TextStyle(fontSize:11,color:Colors.white60)),
        ]),
        actions:[IconButton(tooltip:'Sair do canal',onPressed:_leave,icon:const Icon(Icons.close))],
      ),
      body:Column(children:[
        if(failure!=null)MaterialBanner(
          content:Text(failure!),leading:const Icon(Icons.warning_amber_rounded),
          actions:[TextButton(onPressed:()=>setState(()=>failure=null),child:const Text('Fechar'))]),
        Expanded(child:connecting
          ?const Center(child:CircularProgressIndicator())
          :!connected?Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Text('Sala indisponível.'),
            const SizedBox(height:12),
            FilledButton(onPressed:_leave,child:const Text('Voltar'))
          ]))
          :people.isEmpty?const Center(child:Text('Aguardando participantes...'))
          :screenStage==null
            ?_participantsGrid(people,hasStage:false)
            :LayoutBuilder(builder:(context,size)=>Column(children:[
                Expanded(
                  flex:MediaGalleryLayout.stageFlexForWidth(size.maxWidth),
                  child:Padding(
                    padding:const EdgeInsets.fromLTRB(12,12,12,4),
                    child:_screenStage(screenStage),
                  ),
                ),
                Expanded(flex:4,
                  child:_participantsGrid(people,hasStage:true)),
              ]))),
        if(connected)Padding(
          padding:const EdgeInsets.symmetric(horizontal:16,vertical:4),
          child:Text(
            noiseProfile==NoiseProfile.ai
              ?'Supressão por IA no microfone (local)'
              :aiSupported
                ?'Supressão WebRTC ativa. IA disponível no menu Ruído.'
                :'Redução de ruído WebRTC. IA indisponível neste sistema.',
            textAlign:TextAlign.center,
            style:const TextStyle(fontSize:11,color:Colors.white70),
          )),
        Container(color:const Color(0xFF202127),padding:const EdgeInsets.all(13),
          child:Wrap(alignment:WrapAlignment.center,spacing:12,runSpacing:8,children:[
            FilledButton.tonalIcon(
              onPressed:connected&&!working?_toggleMic:null,
              icon:Icon(microphone?Icons.mic:Icons.mic_off),
              label:Text(microphone?'Silenciar':'Ativar microfone')),
            PopupMenuButton<NoiseProfile>(
              tooltip:'Redução de ruído do microfone',
              enabled:connected&&!working,
              onSelected:(mode)=>unawaited(_chooseNoiseProfile(mode)),
              itemBuilder:(ctx)=>[
                for(final mode in NoiseProfile.values)
                  PopupMenuItem<NoiseProfile>(
                    value:mode,
                    enabled:mode!=NoiseProfile.ai||aiSupported,
                    child:Row(children:[
                      Icon(mode==noiseProfile?Icons.radio_button_checked:
                        Icons.radio_button_unchecked,size:18),
                      const SizedBox(width:8),
                      Text(NoiseCapability.label(mode)),
                    ]),
                  ),
              ],
              child:Chip(avatar:const Icon(Icons.graphic_eq,size:18),
                label:Text('Ruído: ${NoiseCapability.label(noiseProfile)}')),
            ),
            FilledButton.tonalIcon(
              onPressed:connected&&!working?_toggleCamera:null,
              icon:Icon(camera?Icons.videocam:Icons.videocam_off),
              label:Text(camera?'Desligar câmera':'Ligar câmera')),
            if(Platform.isWindows||Platform.isMacOS)
              FilledButton.tonalIcon(
                onPressed:connected&&!working?_toggleShare:null,
                icon:Icon(sharing?Icons.stop_screen_share:Icons.screen_share),
                label:Text(sharing?'Parar transmissão':'Compartilhar tela')),
            FilledButton.icon(
              style:FilledButton.styleFrom(backgroundColor:const Color(0xFFCA4751)),
              onPressed:_leave,
              icon:const Icon(Icons.call_end),
              label:const Text('Desconectar'))
          ])),
      ]),
    );
  }
}
