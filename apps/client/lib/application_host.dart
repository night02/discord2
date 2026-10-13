import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_client.dart';
import 'api_endpoint.dart';
import 'application/models.dart';
import 'application/session_store.dart';
import 'application/veylor_controller.dart';
import 'media/media_access.dart';
import 'media/share_profile.dart';
import 'media/voice_session.dart';
import 'presentation/auth_page.dart';
import 'presentation/call_pane.dart';
import 'presentation/chat_pane.dart';
import 'presentation/settings_dialog.dart';
import 'presentation/veylor_theme.dart';
import 'presentation/workspace_dialogs.dart';
import 'presentation/workspace_navigation.dart';
import 'update_diagnostics.dart';
import 'update_health.dart';
import 'updates/update_coordinator.dart';
class VeylorApp extends StatelessWidget {
  const VeylorApp({super.key,this.sessionRestorationEnabled=true,this.controller,this.startupArguments=const [],this.voiceFactory});
  final bool sessionRestorationEnabled;final VeylorController? controller;final List<String> startupArguments;final VoiceSessionFactory? voiceFactory;
  @override Widget build(BuildContext context)=>MaterialApp(title:'Veylor',debugShowCheckedModeBanner:false,theme:veylorTheme(),
    home:ApplicationHost(controller:controller,restoreSession:sessionRestorationEnabled,startupArguments:startupArguments,voiceFactory:voiceFactory));
}
class ApplicationHost extends StatefulWidget {
  const ApplicationHost({super.key,this.controller,required this.restoreSession,this.startupArguments=const [],this.voiceFactory});
  final VeylorController? controller;final bool restoreSession;final List<String> startupArguments;final VoiceSessionFactory? voiceFactory;
  @override State<ApplicationHost> createState()=>_ApplicationHostState();
}
class _ApplicationHostState extends State<ApplicationHost> {
  late final VeylorController app;final scaffold=GlobalKey<ScaffoldState>();VoiceSession? call;
  String version='V0.5.0 · Beta';String? _callAccount;
  bool showingCall=false,joiningCall=false,leavingCall=false,_checkingCallPermission=false;
  Timer? _callPermissionTimer;Future<void>? _closingCall;UpdateCoordinator? _updates;
  WorkspaceDialogs get dialogs=>WorkspaceDialogs(context,app);
  UpdateCoordinator get updates=>_updates??=UpdateCoordinator(context);
  @override void initState(){
    super.initState();
    app=widget.controller??VeylorController(api:Api(const String.fromEnvironment('VEYLOR_API_URL',defaultValue:newVeylorApi)),sessions:SecureSessionStore());
    app.addListener(_workspaceChanged);
    if(widget.controller==null)unawaited(app.bootstrap(restore:widget.restoreSession).then((_)=>_reportReady()));
    unawaited(PackageInfo.fromPlatform().then((info){if(mounted)setState(()=>version='V'+info.version+' · Beta');}).catchError((Object _){}));
  }
  Future<void> _reportReady() async {
    if(!widget.restoreSession)return;
    WidgetsBinding.instance.addPostFrameCallback((_){if(mounted){
      unawaited(StartupHandshake.signal(widget.startupArguments));unawaited(updates.checkForUpdates(silent:true));
    }});
    await UpdateDiagnostics.add('app_startup_ready');
  }
  void _workspaceChanged(){
    if(!mounted)return;
    if(call!=null && (app.phase!=AppPhase.signedIn || app.account?.id!=_callAccount || !app.communities.any((server)=>server.id==call!.communityId)))unawaited(_leaveCall());
  }
  void _voiceChanged(){if(mounted)setState((){});}
  void _closeDrawer()=>scaffold.currentState?.closeDrawer();
  void _openDrawer()=>scaffold.currentState?.openDrawer();
  void _home(){setState(()=>showingCall=false);app.openHome();_closeDrawer();}
  void _community(Community server){setState(()=>showingCall=false);_closeDrawer();unawaited(app.selectCommunity(server));}
  void _channel(CommunityChannel channel){setState(()=>showingCall=false);_closeDrawer();unawaited(app.selectChannel(channel));}
  void _thread(DirectThread thread){setState(()=>showingCall=false);_closeDrawer();unawaited(app.selectThread(thread));}
  Future<void> _discordLogin() async {
    var visible=true;
    final modal=showDialog<void>(context:context,barrierDismissible:false,builder:(ctx)=>PopScope(canPop:false,child:AlertDialog(
      title:const Text('Entrar com Discord'),content:const Column(mainAxisSize:MainAxisSize.min,children:[
        CircularProgressIndicator(),SizedBox(height:20),Text('Autorize a Veylor no navegador para continuar.')]),
      actions:[TextButton(onPressed:(){app.cancelDiscordLogin();visible=false;Navigator.pop(ctx);},child:const Text('Cancelar'))])));
    await app.loginDiscord((url)=>launchUrl(url,mode:LaunchMode.externalApplication));
    if(visible && mounted)Navigator.of(context,rootNavigator:true).pop();await modal;
  }
  Future<void> _joinVoice(CommunityChannel channel) async {
    final server=app.selectedCommunity,userId=app.account?.id;
    if(joiningCall || server==null || userId==null)return;
    if(call?.channelId==channel.id && call!.phase!=CallPhase.failed){setState(()=>showingCall=true);_closeDrawer();return;}
    joiningCall=true;
    try{
      if(_closingCall!=null)await _closingCall;
      if(!mounted || app.account?.id!=userId)return;
      if(call!=null){
        if(!await dialogs.confirm('Trocar de canal de voz?','Você sairá de '+call!.channelName+' e entrará em '+channel.name+'.','Trocar de canal'))return;
        await _leaveCall();
      }
      final result=await app.operation(()=>app.api.request('POST','/api/media/token',{'channel_id':channel.id}));
      if(result==null || !mounted || app.account?.id!=userId)return;
      final access=MediaAccess.fromJson(result);
      final session=(widget.voiceFactory??VoiceSession.new)(channelId:channel.id,channelName:channel.name,communityId:server.id,communityName:server.name);
      session.addListener(_voiceChanged);
      setState((){call=session;_callAccount=userId;showingCall=true;});_closeDrawer();
      _callPermissionTimer?.cancel();_callPermissionTimer=Timer.periodic(const Duration(seconds:30),(_)=>unawaited(_validateCallPermission()));
      await session.connect(access);
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Não foi possível preparar a chamada. Verifique o servidor de mídia.')));
    }finally{joiningCall=false;if(mounted)setState((){});}
  }
  Future<void> _validateCallPermission() async {
    final session=call;if(session==null || _checkingCallPermission || leavingCall)return;_checkingCallPermission=true;
    try{
      final result=await app.api.request('GET','/api/servers/'+session.communityId+'/channels');
      if(!mounted || !identical(call,session))return;
      if(!jsonRows(result,'channels').any((row)=>row['id']==session.channelId && row['type']=='voice'))await _leaveCall();
    }on ApiException catch(failure){
      if(mounted && identical(call,session) && [401,403,404].contains(failure.statusCode)){
        await _leaveCall();if(failure.statusCode==401)await app.logout();
      }
    }catch(_){}finally{_checkingCallPermission=false;}
  }
  Future<void> _leaveCall(){
    final pending=_closingCall;if(pending!=null)return pending;
    final previous=call;if(previous==null)return Future<void>.value();
    leavingCall=true;_callPermissionTimer?.cancel();previous.removeListener(_voiceChanged);
    if(mounted && identical(call,previous))setState((){call=null;showingCall=false;_callAccount=null;});
    return _closingCall=() async {
      try{await previous.leave().timeout(const Duration(seconds:8));}catch(_){}finally{
        previous.dispose();leavingCall=false;_closingCall=null;if(mounted)setState((){});
      }
    }();
  }
  Future<void> _share() async {
    final session=call;if(session==null || !session.controlsEnabled)return;
    if(session.sharing){await session.stopSharing();return;}if(!session.canShare)return;
    var profile=session.profile;
    final selected=await showDialog<ShareProfile>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setLocal)=>AlertDialog(
      title:const Text('Compartilhe sua tela'),content:SizedBox(width:390,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Escolha a qualidade e depois a janela ou tela. Todos os perfis estão liberados.',style:TextStyle(color:VeylorColors.muted,height:1.5)),const SizedBox(height:18),
        DropdownButtonFormField<ShareProfile>(initialValue:profile,isExpanded:true,decoration:const InputDecoration(labelText:'Qualidade solicitada'),
          items:[for(final item in ShareProfile.values)DropdownMenuItem(value:item,child:Text(item.label+(item.experimental?' · experimental':''),style:const TextStyle(fontSize:13)))],
          onChanged:(value)=>setLocal(()=>profile=value??profile)),
        const SizedBox(height:16),const Text('FPS e resolução dependem da conexão e do equipamento. O áudio do jogo no Windows ainda não acompanha a tela.',style:TextStyle(fontSize:12,color:VeylorColors.muted,height:1.5))
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,profile),child:const Text('Escolher tela'))])));
    if(selected==null || !mounted || !identical(session,call) || !session.controlsEnabled)return;
    final source=await showDialog<dynamic>(context:context,builder:(_)=>lk.ScreenSelectDialog());
    if(source==null || !mounted || !identical(session,call) || !session.controlsEnabled)return;
    await session.startSharing(source.id as String,selected);
  }
  Future<void> _members() async {
    if(app.selectedCommunity==null)return;
    if(MediaQuery.sizeOf(context).width>=1160){app.toggleMembers();return;}
    await app.refreshMembers();if(!mounted)return;
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Membros e cargos'),
      content:SizedBox(width:390,height:340,child:AnimatedBuilder(animation:app,builder:(_,__)=>MembersPanel(app:app,onManage:(member,action)=>dialogs.manageMember(member,action)))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Fechar'))]));
  }
  void _communityAction(CommunityAction action){
    switch(action){
      case CommunityAction.invite:unawaited(dialogs.invite());
      case CommunityAction.members:unawaited(_members());
      case CommunityAction.textChannel:unawaited(dialogs.createChannel(ChannelKind.text));
      case CommunityAction.voiceChannel:unawaited(dialogs.createChannel(ChannelKind.voice));
    }
  }
  Future<void> _deleteChannel(CommunityChannel channel) async {if(await dialogs.deleteChannel(channel) && call?.channelId==channel.id)await _leaveCall();}
  Future<void> _settings() async {
    await showDialog<void>(context:context,builder:(ctx)=>SettingsDialog(app:app,version:version,
      onConfigure:(){Navigator.pop(ctx);unawaited(dialogs.configureAddress());},
      onUpdate:(){Navigator.pop(ctx);unawaited(updates.checkForUpdates());},onLogout:(){Navigator.pop(ctx);unawaited(app.logout());}));
  }
  void _diagnostics(){
    final session=call;if(session!=null)unawaited(showDialog<void>(context:context,builder:(_)=>CallDiagnosticsDialog(call:session)));
  }
  Widget _navigation()=>WorkspaceNavigation(app:app,version:version,call:call,showingCall:showingCall,
    onHome:_home,onCommunity:_community,onChannel:_channel,onThread:_thread,onVoice:(channel)=>unawaited(_joinVoice(channel)),
    onCreate:()=>unawaited(dialogs.createCommunity()),onJoin:()=>unawaited(dialogs.join()),onNewDm:()=>unawaited(dialogs.newMessage()),
    onSettings:()=>unawaited(_settings()),onCommunityAction:_communityAction,onDeleteChannel:(channel)=>unawaited(_deleteChannel(channel)),
    onShowCall:(){setState(()=>showingCall=true);_closeDrawer();},onLeaveCall:()=>unawaited(_leaveCall()));
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:app,builder:(context,_){
    if(app.phase==AppPhase.restoring)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(app.phase==AppPhase.unavailable)return Scaffold(body:RecoveryPage(app:app,onConfigure:()=>unawaited(dialogs.configureAddress())));
    if(app.phase!=AppPhase.signedIn)return Scaffold(body:AuthPage(app:app,version:version,onConfigure:()=>unawaited(dialogs.configureAddress()),
      onDiscord:()=>unawaited(_discordLogin()),onUpdate:()=>unawaited(updates.checkForUpdates())));
    final size=MediaQuery.sizeOf(context),mobile=size.width<760;
    final chat=ChatPane(app:app,onOpenNavigation:mobile?_openDrawer:null,onNewDm:()=>unawaited(dialogs.newMessage()),onCreate:()=>unawaited(dialogs.createCommunity()),
      onJoin:()=>unawaited(dialogs.join()),onMembers:()=>unawaited(_members()),onCommunity:_community);
    return Scaffold(key:scaffold,drawer:mobile?Drawer(width:size.width<348?size.width-24:324,child:SafeArea(child:_navigation())):null,
      body:SafeArea(child:Row(children:[
        if(!mobile)SizedBox(width:308,child:_navigation()),
        Expanded(child:Column(children:[
          if(app.error!=null)ErrorNotice(message:app.error!,onDismiss:app.dismissError),
          Expanded(child:showingCall && call!=null?CallPane(call:call!,onShare:()=>unawaited(_share()),onLeave:()=>unawaited(_leaveCall()),onDiagnostics:_diagnostics,onOpenNavigation:mobile?_openDrawer:null):chat)
        ])),
        if(!mobile && size.width>=1160 && app.showMembers && !showingCall)SizedBox(width:236,child:MembersPanel(app:app,onManage:(member,action)=>dialogs.manageMember(member,action)))
      ])));
  });
  @override void dispose(){
    _callPermissionTimer?.cancel();call?.removeListener(_voiceChanged);call?.dispose();app.removeListener(_workspaceChanged);
    if(widget.controller==null)app.dispose();super.dispose();
  }
}
