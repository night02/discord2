import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:livekit_noise_filter/livekit_noise_filter.dart';
import '../noise_profile.dart';
import 'media_access.dart';
import 'share_profile.dart';
enum CallPhase{idle,connecting,connected,reconnecting,failed,leaving}
typedef VoiceSessionFactory=VoiceSession Function({required String channelId,required String channelName,required String communityId,required String communityName});
class VoiceSession extends ChangeNotifier {
  VoiceSession({required this.channelId,required this.channelName,required this.communityId,required this.communityName,lk.Room? room})
    :room=room??lk.Room(roomOptions:const lk.RoomOptions(adaptiveStream:true,dynacast:true,stopLocalTrackOnUnpublish:true));
  final String channelId,channelName,communityId,communityName;
  final lk.Room room;
  CallPhase phase=CallPhase.idle;
  bool working=false,aiSupported=false,deafened=false;
  bool _restoreMicrophone=false,_disposed=false,_sampling=false,_applyingDeafen=false;
  int _epoch=0;
  String? error;
  NoiseProfile noiseProfile=NoiseProfile.standard;
  ShareProfile profile=ShareProfile.balanced;
  StreamMetrics sendingMetrics=const StreamMetrics(),receivingMetrics=const StreamMetrics();
  LiveKitNoiseFilter? _noiseFilter;
  lk.LocalVideoTrack? _shareTrack;
  String? _shareSid,_sendSampleSid,_receiveSampleSid;
  final _senderMeter=BitrateMeter(),_receiverMeter=BitrateMeter();
  Timer? _statsTimer;
  Future<void>? _closeFuture;
  bool get connected=>phase==CallPhase.connected && room.connectionState==lk.ConnectionState.connected;
  bool get controlsEnabled=>connected && !working && !_disposed;
  bool get microphone=>room.localParticipant?.isMicrophoneEnabled()??false;
  bool get camera=>room.localParticipant?.isCameraEnabled()??false;
  bool get sharing=>room.localParticipant?.isScreenShareEnabled()??false;
  bool get canShare=>Platform.isWindows || Platform.isMacOS;
  void _emit(){if(!_disposed)notifyListeners();}
  Future<void> connect(MediaAccess access) async {
    if(_disposed || phase!=CallPhase.idle)return;
    final epoch=++_epoch;phase=CallPhase.connecting;room.addListener(_onRoomUpdate);_emit();
    unawaited(_checkNoiseSupport());
    try{
      await room.connect(access.url,access.token).timeout(const Duration(seconds:30));
      if(_disposed || epoch!=_epoch){await _closeRoom();return;}
      phase=CallPhase.connected;error=null;
      _statsTimer=Timer.periodic(const Duration(seconds:2),(_)=>unawaited(_sampleStats()));
    }catch(_){
      if(_disposed || epoch!=_epoch)return;
      phase=CallPhase.failed;error='Não foi possível entrar na chamada. Verifique a conexão e tente novamente.';
      await _closeRoom();
    }_emit();
  }
  void _onRoomUpdate(){
    if(_disposed || phase==CallPhase.leaving || phase==CallPhase.failed)return;
    switch(room.connectionState){
      case lk.ConnectionState.connected:
        phase=CallPhase.connected;if(deafened)unawaited(_applyDeafen());
      case lk.ConnectionState.reconnecting:phase=CallPhase.reconnecting;
      case lk.ConnectionState.disconnected:
        if(phase!=CallPhase.connecting){phase=CallPhase.failed;error='A ligação terminou. Entre novamente para reconectar.';}
      default:break;
    }_emit();
  }
  Future<void> _checkNoiseSupport() async {
    if(!NoiseCapability.supportsAi(isAndroid:Platform.isAndroid,isIos:Platform.isIOS,isMacOs:Platform.isMacOS))return;
    try{aiSupported=await LiveKitNoiseFilter.isSupported();_emit();}catch(_){}
  }
  lk.AudioCaptureOptions _micOptions(NoiseProfile mode)=>lk.AudioCaptureOptions(
    echoCancellation:true,autoGainControl:true,highPassFilter:true,
    noiseSuppression:NoiseCapability.useNativeSuppression(mode),voiceIsolation:NoiseCapability.useNativeSuppression(mode),
    processor:mode==NoiseProfile.ai?_noiseFilter:null);
  Future<bool> action(Future<void> Function() operation) async {
    if(!controlsEnabled)return false;
    final epoch=_epoch;working=true;error=null;_emit();
    try{await operation();return !_disposed && epoch==_epoch;}catch(_){
      if(!_disposed && epoch==_epoch)error='Não foi possível aplicar o controle. Confira as permissões e tente novamente.';
      return false;
    }finally{if(!_disposed && epoch==_epoch){working=false;_emit();}}
  }
  Future<bool> toggleMicrophone()=>action(() async {
    if(deafened){deafened=false;_restoreMicrophone=false;await _applyDeafen();}
    if(noiseProfile==NoiseProfile.ai)_noiseFilter??=LiveKitNoiseFilter();
    await room.localParticipant!.setMicrophoneEnabled(!microphone,audioCaptureOptions:_micOptions(noiseProfile));
  });
  Future<bool> toggleCamera()=>action(() async {await room.localParticipant!.setCameraEnabled(!camera);});
  Future<bool> toggleDeafen()=>action(() async {
    if(!deafened){
      _restoreMicrophone=microphone;if(microphone)await room.localParticipant!.setMicrophoneEnabled(false);deafened=true;
    }else{
      deafened=false;if(_restoreMicrophone)await room.localParticipant!.setMicrophoneEnabled(true,audioCaptureOptions:_micOptions(noiseProfile));
      _restoreMicrophone=false;
    }await _applyDeafen();
  });
  Future<void> _applyDeafen() async {
    if(_applyingDeafen || _disposed)return;_applyingDeafen=true;
    try{
      for(final participant in room.remoteParticipants.values){
        for(final publication in participant.audioTrackPublications){
          final track=publication.track;if(track==null)continue;
          if(deafened && track.mediaStreamTrack.enabled){await track.disable();}
          else if(!deafened && !track.mediaStreamTrack.enabled){await track.enable();}
        }
      }
    }catch(_){}finally{_applyingDeafen=false;}
  }
  Future<bool> chooseNoise(NoiseProfile next)=>action(() async {
    if(next==noiseProfile)return;
    if(next==NoiseProfile.ai && !aiSupported)throw StateError('Unsupported processor');
    final participant=room.localParticipant!,wasEnabled=microphone,previous=noiseProfile;
    if(next==NoiseProfile.ai)_noiseFilter??=LiveKitNoiseFilter();
    final old=participant.getTrackPublicationBySource(lk.TrackSource.microphone);
    if(old!=null)await participant.removePublishedTrack(old.sid);
    try{
      if(wasEnabled)await participant.setMicrophoneEnabled(true,audioCaptureOptions:_micOptions(next));
      noiseProfile=next;
    }catch(_){
      if(wasEnabled){try{await participant.setMicrophoneEnabled(true,audioCaptureOptions:_micOptions(previous));}catch(_){}}
      rethrow;
    }
  });
  Future<bool> startSharing(String sourceId,ShareProfile selected)=>action(() async {
    if(!canShare || sourceId.isEmpty || sharing)return;
    final participant=room.localParticipant!,epoch=_epoch;
    final track=await lk.LocalVideoTrack.createScreenShareTrack(lk.ScreenShareCaptureOptions(
      sourceId:sourceId,maxFrameRate:selected.fps.toDouble(),captureScreenAudio:false,
      params:lk.VideoParameters(dimensions:lk.VideoDimensions(selected.width,selected.height),
        encoding:lk.VideoEncoding(maxBitrate:selected.bitrate,maxFramerate:selected.fps))));
    if(_disposed || !connected){await track.stop();await track.dispose();return;}
    try{
      final publication=await participant.publishVideoTrack(track,publishOptions:lk.VideoPublishOptions(
        screenShareEncoding:lk.VideoEncoding(maxBitrate:selected.bitrate,maxFramerate:selected.fps),simulcast:true));
      if(_disposed || epoch!=_epoch || !connected){
        try{await participant.removePublishedTrack(publication.sid);}catch(_){}
        await track.stop();await track.dispose();return;
      }
      _shareTrack=track;_shareSid=publication.sid;profile=selected;_senderMeter.reset();sendingMetrics=const StreamMetrics();
    }catch(_){await track.stop();await track.dispose();rethrow;}
  });
  Future<bool> stopSharing()=>action(_stopSharing);
  Future<void> _stopSharing() async {
    final track=_shareTrack,sid=_shareSid;_shareTrack=null;_shareSid=null;
    if(sid!=null){try{await room.localParticipant?.removePublishedTrack(sid);}catch(_){}}
    else{await room.localParticipant?.setScreenShareEnabled(false);}
    if(track!=null){try{await track.stop();await track.dispose();}catch(_){}}
    sendingMetrics=const StreamMetrics();_senderMeter.reset();
  }
  Future<void> _sampleStats() async {
    if(_disposed || !connected || _sampling)return;_sampling=true;final epoch=_epoch;
    try{
      final local=room.localParticipant?.getTrackPublicationBySource(lk.TrackSource.screenShareVideo);
      if(local?.track is lk.LocalVideoTrack && !local!.muted){
        if(_sendSampleSid!=local.sid){_senderMeter.reset();_sendSampleSid=local.sid;}
        final rows=await (local.track as lk.LocalVideoTrack).getSenderStats();
        if(rows.isNotEmpty){
          rows.sort((a,b)=>(b.frameWidth??0).compareTo(a.frameWidth??0));final stats=rows.first;
          if(!_disposed && epoch==_epoch)sendingMetrics=StreamMetrics(
            width:stats.frameWidth,height:stats.frameHeight,fps:stats.framesPerSecond,
            bitsPerSecond:_senderMeter.sample(stats.bytesSent,DateTime.now().millisecondsSinceEpoch),
            roundTripMs:stats.roundTripTime==null?null:stats.roundTripTime!*1000,
            codec:stats.mimeType,limitation:stats.qualityLimitationReason);
        }
      }else{sendingMetrics=const StreamMetrics();_senderMeter.reset();}
      lk.RemoteTrackPublication? remote;
      for(final participant in room.remoteParticipants.values){
        for(final publication in participant.videoTrackPublications){
          if(publication.isScreenShare && !publication.muted && publication.subscribed && publication.track is lk.RemoteVideoTrack){
            remote=publication;break;
          }
        }if(remote!=null)break;
      }
      if(remote!=null){
        if(_receiveSampleSid!=remote.sid){_receiverMeter.reset();_receiveSampleSid=remote.sid;}
        final stats=await (remote.track as lk.RemoteVideoTrack).getReceiverStats();
        if(stats!=null && !_disposed && epoch==_epoch)receivingMetrics=StreamMetrics(
          width:stats.frameWidth,height:stats.frameHeight,fps:stats.framesPerSecond,
          bitsPerSecond:_receiverMeter.sample(stats.bytesReceived,DateTime.now().millisecondsSinceEpoch),codec:stats.mimeType);
      }else{receivingMetrics=const StreamMetrics();_receiverMeter.reset();}
      if(!_disposed && epoch==_epoch)_emit();
    }catch(_){}finally{_sampling=false;}
  }
  Future<void> leave() async {
    if(_disposed || phase==CallPhase.leaving)return;
    _epoch++;_statsTimer?.cancel();phase=CallPhase.leaving;_emit();
    await _closeRoom();phase=CallPhase.idle;_emit();
  }
  Future<void> _closeRoom()=>_closeFuture??=() async {
    _statsTimer?.cancel();room.removeListener(_onRoomUpdate);
    try{await _stopSharing();}catch(_){}
    if(room.connectionState!=lk.ConnectionState.disconnected){
      try{await room.disconnect().timeout(const Duration(seconds:6));}catch(_){}
    }
    try{await room.dispose();}catch(_){}
  }();
  @override void dispose(){
    if(_disposed)return;_disposed=true;_epoch++;_statsTimer?.cancel();unawaited(_closeRoom());super.dispose();
  }
}
