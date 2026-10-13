import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import '../call_media_gallery.dart';
import '../media/voice_session.dart';
import '../noise_profile.dart';
import 'veylor_theme.dart';
class CallPane extends StatelessWidget {
  const CallPane({super.key,required this.call,required this.onShare,required this.onLeave,required this.onDiagnostics,this.onOpenNavigation});
  final VoiceSession call;final VoidCallback onShare,onLeave,onDiagnostics;final VoidCallback? onOpenNavigation;
  @override Widget build(BuildContext context){
    final others=call.room.remoteParticipants.values.toList()..sort((a,b)=>a.joinedAt.compareTo(b.joinedAt));
    final people=<lk.Participant>[...others,if(call.room.localParticipant!=null)call.room.localParticipant!];
    final streams=<ScreenStageStream>[];
    for(final person in people){
      for(final pub in person.videoTrackPublications){
        final self=person==call.room.localParticipant;
        if(!pub.isScreenShare || pub.muted || pub.track is! lk.VideoTrack || !self && !pub.subscribed)continue;
        streams.add(ScreenStageStream(id:pub.sid,label:self?'Sua transmissão':person.name.isEmpty?'Participante':person.name,
          video:lk.VideoTrackRenderer(pub.track as lk.VideoTrack,key:ValueKey(pub.sid),fit:lk.VideoViewFit.contain)));
      }
    }
    return ColoredBox(color:VeylorColors.rail,child:Column(children:[
      SizedBox(height:52,child:Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Row(children:[
        if(onOpenNavigation!=null)IconButton(tooltip:'Abrir servidores e canais',onPressed:onOpenNavigation,icon:const Icon(Icons.menu)),
        const Icon(Icons.volume_up_outlined,color:VeylorColors.muted,size:22),const SizedBox(width:10),
        Expanded(child:Text(call.channelName,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w800))),
        Text(people.length.toString(),style:const TextStyle(color:VeylorColors.muted,fontSize:12)),const SizedBox(width:6),const Icon(Icons.people_outline,size:18,color:VeylorColors.muted)
      ]))),
      if(call.error!=null)Padding(padding:const EdgeInsets.all(12),child:Text(call.error!,textAlign:TextAlign.center,style:const TextStyle(color:VeylorColors.danger,fontSize:12))),
      Expanded(child:call.phase==CallPhase.connecting?const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[CircularProgressIndicator(),SizedBox(height:18),Text('Entrando na chamada…')])):
        call.phase==CallPhase.failed?const Center(child:Icon(Icons.cloud_off_outlined,size:60,color:VeylorColors.muted)):CallMediaGallery(streams:streams,participants:[for(final person in people)_participant(person)])),
      if(call.phase==CallPhase.reconnecting)const Padding(padding:EdgeInsets.all(8),child:Text('Reconectando a chamada…',style:TextStyle(color:VeylorColors.muted,fontSize:12))),
      if(call.sharing)Padding(padding:const EdgeInsets.fromLTRB(12,5,12,3),child:Text(call.sendingMetrics.hasVideo?
        'Enviando: '+call.sendingMetrics.width!.toInt().toString()+'×'+call.sendingMetrics.height!.toInt().toString()+' · '+call.sendingMetrics.fps!.toStringAsFixed(0)+' FPS medidos':
        'Perfil solicitado: '+call.profile.label+' · aguardando medição',textAlign:TextAlign.center,style:const TextStyle(fontSize:10,color:VeylorColors.success))),
      Container(padding:const EdgeInsets.symmetric(vertical:12,horizontal:8),color:const Color(0xFF17181C),child:Wrap(alignment:WrapAlignment.center,spacing:7,runSpacing:6,children:[
        _control(call.microphone?'Silenciar microfone':'Ativar microfone',call.microphone?Icons.mic:Icons.mic_off,call.controlsEnabled?()=>call.toggleMicrophone():null,active:call.microphone),
        _control(call.deafened?'Ativar áudio da chamada':'Desativar áudio da chamada',call.deafened?Icons.headset_off:Icons.headset,call.controlsEnabled?()=>call.toggleDeafen():null,active:!call.deafened),
        _control(call.camera?'Desligar câmera':'Ativar câmera',call.camera?Icons.videocam:Icons.videocam_off,call.controlsEnabled?()=>call.toggleCamera():null,active:call.camera),
        _control(call.sharing?'Parar transmissão':call.canShare?'Compartilhar tela':'Captura disponível no Windows e macOS',call.sharing?Icons.stop_screen_share:Icons.screen_share_outlined,
          call.controlsEnabled && call.canShare?onShare:null,active:call.sharing),
        PopupMenuButton<NoiseProfile>(tooltip:'Redução de ruído',enabled:call.controlsEnabled,onSelected:call.chooseNoise,icon:const Icon(Icons.tune,size:21),itemBuilder:(_)=>[
          for(final profile in NoiseProfile.values)PopupMenuItem(value:profile,enabled:profile!=NoiseProfile.ai || call.aiSupported,child:Row(children:[
            Icon(profile==call.noiseProfile?Icons.check_circle:Icons.circle_outlined,size:17),const SizedBox(width:8),Text(NoiseCapability.label(profile),style:const TextStyle(fontSize:13))]))]),
        _control('Qualidade da chamada',Icons.bar_chart,onDiagnostics),_control('Desconectar',Icons.call_end,onLeave,danger:true)
      ]))
    ]));
  }
  Widget _control(String label,IconData icon,VoidCallback? action,{bool active=false,bool danger=false})=>IconButton.filled(
    tooltip:label,onPressed:action,style:IconButton.styleFrom(backgroundColor:danger?const Color(0xFFDA373C):active?VeylorColors.selected:VeylorColors.navigation,
      foregroundColor:Colors.white,minimumSize:const Size(39,39),disabledBackgroundColor:VeylorColors.navigation),icon:Icon(icon,size:21));
  Widget _participant(lk.Participant person){
    final self=person==call.room.localParticipant;lk.VideoTrack? visible;
    for(final pub in person.videoTrackPublications){
      if(!pub.isScreenShare && !pub.muted && pub.track is lk.VideoTrack && (self || pub.subscribed)){visible=pub.track as lk.VideoTrack;break;}
    }
    return VoiceParticipantTile(key:ValueKey(person.identity),name:person.name.isEmpty?'Participante':person.name,self:self,speaking:person.audioLevel>.1,
      microphoneEnabled:person.isMicrophoneEnabled(),video:visible==null?null:lk.VideoTrackRenderer(visible));
  }
}
