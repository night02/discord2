import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:veylor/main.dart';
import 'package:veylor/media/media_access.dart';
import 'package:veylor/media/voice_session.dart';
import 'support/workspace_fixture.dart';
class FixtureRoom implements lk.Room {
  lk.ConnectionState state=lk.ConnectionState.disconnected;bool disposed=false;
  @override lk.ConnectionState get connectionState=>state;
  @override UnmodifiableMapView<String,lk.RemoteParticipant> get remoteParticipants=>UnmodifiableMapView({});
  @override lk.LocalParticipant? get localParticipant=>null;
  @override void addListener(VoidCallback listener){}
  @override void removeListener(VoidCallback listener){}
  @override Future<void> disconnect() async{state=lk.ConnectionState.disconnected;}
  @override Future<bool> dispose() async{disposed=true;return true;}
  @override dynamic noSuchMethod(Invocation invocation)=>throw UnsupportedError('Unexpected native room call');
}
class FakeVoiceSession extends VoiceSession {
  FakeVoiceSession({required super.channelId,required super.channelName,required super.communityId,required super.communityName}):super(room:FixtureRoom());
  int connects=0,leaves=0;bool muted=true;
  @override bool get connected=>phase==CallPhase.connected;
  @override bool get microphone=>!muted;
  @override Future<void> connect(MediaAccess access) async{connects++;(room as FixtureRoom).state=lk.ConnectionState.connected;phase=CallPhase.connected;notifyListeners();}
  @override Future<void> leave() async{leaves++;await super.leave();}
  @override Future<bool> toggleMicrophone() async{muted=!muted;notifyListeners();return true;}
}
void main(){
  for(final size in [const Size(320,568),const Size(390,844),const Size(640,360),const Size(1024,768),const Size(1440,900)]){
    testWidgets('workspace and navigation fit $size',(tester) async {
      tester.view.physicalSize=size;tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final f=WorkspaceFixture();f.api.pages['/api/channels/channel-a/messages']=[
        FixtureApi.message(1,'Bora testar a transmissão depois?',username:'Bruno'),
        FixtureApi.message(2,'Sim! A chamada fica aberta enquanto navegamos pelos canais.',username:'Vinicius')];
      await f.openCommunity();await tester.pumpWidget(VeylorApp(controller:f.app,sessionRestorationEnabled:false));await tester.pumpAndSettle();
      expect(tester.takeException(),isNull);expect(find.byKey(const ValueKey('message-composer')),findsOneWidget);
      if(size.width<760){await tester.tap(find.byKey(const ValueKey('open-navigation')));await tester.pumpAndSettle();expect(tester.takeException(),isNull);expect(find.byKey(const ValueKey('channel-channel-a')),findsOneWidget);}
      await tester.pumpWidget(const SizedBox.shrink());f.dispose();
    });
  }
  for(final size in [const Size(320,568),const Size(640,360),const Size(1440,900)]){
    testWidgets('login scrolls and Discord fits $size',(tester) async {
      tester.view.physicalSize=size;tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const VeylorApp(sessionRestorationEnabled:false));await tester.pumpAndSettle();
      expect(find.text('Continuar com Discord'),findsOneWidget);expect(tester.takeException(),isNull);
    });
  }
  testWidgets('draft survives navigation and confirmed send clears only its text',(tester) async {
    final f=WorkspaceFixture();await f.openCommunity();
    await tester.pumpWidget(VeylorApp(controller:f.app,sessionRestorationEnabled:false));await tester.pumpAndSettle();
    final composer=find.byKey(const ValueKey('message-composer'));await tester.enterText(composer,'Meu rascunho');
    await tester.tap(find.byKey(const ValueKey('channel-channel-b')));await tester.pumpAndSettle();
    expect(tester.widget<TextField>(composer).controller!.text,'');
    await tester.tap(find.byKey(const ValueKey('channel-channel-a')));await tester.pumpAndSettle();
    expect(tester.widget<TextField>(composer).controller!.text,'Meu rascunho');
    await tester.tap(find.byKey(const ValueKey('send-message')));await tester.pumpAndSettle();
    expect(find.text('Meu rascunho'),findsOneWidget);expect(tester.widget<TextField>(composer).controller!.text,'');
    await tester.pumpWidget(const SizedBox.shrink());f.dispose();
  });
  testWidgets('voice survives text navigation until explicit disconnect',(tester) async {
    final f=WorkspaceFixture();await f.openCommunity();FakeVoiceSession? voice;
    await tester.pumpWidget(VeylorApp(controller:f.app,sessionRestorationEnabled:false,
      voiceFactory:({required channelId,required channelName,required communityId,required communityName})=>voice=FakeVoiceSession(channelId:channelId,channelName:channelName,communityId:communityId,communityName:communityName)));
    await tester.pumpAndSettle();await tester.tap(find.byKey(const ValueKey('voice-voice-a')));await tester.pumpAndSettle();
    expect(voice!.connects,1);expect(find.byKey(const ValueKey('persistent-call-dock')),findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('channel-channel-b')));await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-composer')),findsOneWidget);expect(voice!.leaves,0);
    await tester.tap(find.byKey(const ValueKey('leave-call-dock')));await tester.pumpAndSettle();
    expect(voice!.leaves,1);expect((voice!.room as FixtureRoom).disposed,isTrue);expect(find.byKey(const ValueKey('persistent-call-dock')),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());f.dispose();
  });
}
