import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

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
  bool connecting=true, connected=false, microphone=false, sharing=false;
  bool working=false;
  String? failure;

  @override
  void initState() {
    super.initState();
    room.addListener(_onRoomUpdate);
    unawaited(_connect());
  }

  void _onRoomUpdate() {
    if(mounted) setState(() {});
  }

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
    if(working||!connected)return;
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
    await participant.setMicrophoneEnabled(!microphone);
    if(mounted)setState(()=>microphone=!microphone);
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
    final track=await lk.LocalVideoTrack.createScreenShareTrack(
      lk.ScreenShareCaptureOptions(sourceId:source.id,maxFrameRate:15.0));
    try {
      await participant.publishVideoTrack(track);
    } catch (_) {
      await track.dispose();
      rethrow;
    }
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

  Widget _participantCard(lk.Participant participant,{bool self=false}) {
    lk.VideoTrack? visible;
    for(final publication in participant.videoTrackPublications) {
      if(publication.isScreenShare && publication.subscribed && !publication.muted &&
          publication.track is lk.VideoTrack) {
        visible=publication.track as lk.VideoTrack;
        break;
      }
    }
    return Container(
      decoration:BoxDecoration(
        color:const Color(0xFF24262D),
        borderRadius:BorderRadius.circular(14),
        border:Border.all(color:const Color(0xFF373A44))),
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
        if(self)const Padding(padding:EdgeInsets.only(top:4),
          child:Text('Sua câmera está desligada',style:TextStyle(fontSize:11,color:Colors.white60))),
      ])));
  }

  @override
  Widget build(BuildContext context) {
    final others=room.remoteParticipants.values.toList();
    final people=<lk.Participant>[
      if(room.localParticipant!=null)room.localParticipant!,
      ...others
    ];
    return Scaffold(
      appBar:AppBar(
        backgroundColor:const Color(0xFF202127),
        title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(widget.channelName,style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
          Text(connecting?'Conectando...':connected?'Canal de voz • ${people.length} participante(s)':'Desconectado',
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
          :LayoutBuilder(builder:(context,size){
            final columns=size.maxWidth>920?3:size.maxWidth>550?2:1;
            return GridView.builder(
              padding:const EdgeInsets.all(18),
              gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:columns,mainAxisSpacing:12,crossAxisSpacing:12,
                childAspectRatio:size.maxWidth<550?1.55:1.4),
              itemCount:people.length,
              itemBuilder:(ctx,i)=>_participantCard(people[i],
                self:people[i]==room.localParticipant),
            );
          })),
        Container(color:const Color(0xFF202127),padding:const EdgeInsets.all(13),
          child:Wrap(alignment:WrapAlignment.center,spacing:12,runSpacing:8,children:[
            FilledButton.tonalIcon(
              onPressed:connected&&!working?_toggleMic:null,
              icon:Icon(microphone?Icons.mic:Icons.mic_off),
              label:Text(microphone?'Silenciar':'Ativar microfone')),
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
