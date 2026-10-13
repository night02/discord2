import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api_client.dart';
import '../api_endpoint.dart';
import '../client_stability.dart';
import '../discord_login.dart';
import 'models.dart';
import 'realtime_client.dart';
import 'session_store.dart';
enum AppPhase{restoring,signedOut,unavailable,signedIn}
class VeylorController extends ChangeNotifier {
  VeylorController({required this.api,required this.sessions,RealtimeClient? realtime,this.pollInterval=const Duration(seconds:30)}):realtime=realtime??SocketRealtimeClient();
  final Api api;
  final SessionStore sessions;
  final RealtimeClient realtime;
  final Duration pollInterval;
  AppPhase phase=AppPhase.restoring;
  Account? account;
  List<Community> communities=const [];
  List<CommunityChannel> channels=const [];
  List<DirectThread> threads=const [];
  List<CommunityMember> members=const [];
  IntegrationAvailability? integrations;
  String? selectedCommunityId,error;
  Conversation? conversation;
  RealtimeStatus connection=RealtimeStatus.offline;
  bool busy=false,loadingConversation=false,showMembers=false,sessionMoved=false;
  final _timelines=<Conversation,List<ChatMessage>>{};
  final _fetches=<Conversation,Object>{};
  final _dirty=<Conversation>{},_sending=<Conversation>{},_unread=<Conversation>{};
  final _pending=<Conversation,PendingMessage>{};
  final _drafts=<Conversation,String>{};
  Timer? _poll;
  bool _disposed=false;
  int _sessionEpoch=0,_navigationEpoch=0,_indexEpoch=0,_membersEpoch=0,_oauthEpoch=0,_threadEpoch=0;
  Community? get selectedCommunity=>communities.where((row)=>row.id==selectedCommunityId).firstOrNull;
  bool get isHome=>selectedCommunityId==null;
  List<ChatMessage> get messages=>_timelines[conversation]??const [];
  bool get sending=>_sending.contains(conversation);
  String get conversationName {
    final target=conversation;if(target==null)return 'Mensagens';
    return target.isDirect?threads.where((row)=>row.id==target.id).firstOrNull?.username??'Conversa privada':channels.where((row)=>row.id==target.id).firstOrNull?.name??'canal';
  }
  String draft(Conversation? target)=>_drafts[target]??'';
  void saveDraft(Conversation? target,String text){
    if(target==null)return;
    if(text.isEmpty){_drafts.remove(target);}else{_drafts[target]=text;}
  }
  bool hasUnread(Conversation target)=>_unread.contains(target);
  bool _current(int epoch)=>!_disposed && epoch==_sessionEpoch;
  void _emit(){if(!_disposed)notifyListeners();}
  void dismissError(){error=null;_emit();}
  Future<void> bootstrap({bool restore=true}) async {
    final epoch=++_sessionEpoch;_stopRealtime();phase=AppPhase.restoring;error=null;_emit();
    if(!restore){phase=AppPhase.signedOut;_emit();return;}
    try {
      final address=await sessions.readAddress();
      final selection=selectStartupServer(address,defaultAddress:api.baseUrl);
      final token=await sessions.readToken();
      if(!_current(epoch))return;
      api.baseUrl=selection.address;
      if(selection.clearOldSession){
        sessionMoved=selection.movedFromLegacy && token!=null;
        await sessions.clear();await sessions.saveAddress(selection.address);
        if(!_current(epoch))return;api.token=null;
      }else{api.token=token;}
      if(api.token==null || api.token!.isEmpty){phase=AppPhase.signedOut;}else{
        final result=await api.request('GET','/api/me');
        if(!_current(epoch))return;
        account=Account.fromJson(asJson(result['user']));
        phase=AppPhase.signedIn;await _hydrate(epoch);
      }
    }catch(failure){
      if(!_current(epoch))return;
      if(failure is ApiException && failure.statusCode==401){
        api.token=null;
        try{await sessions.clear();}catch(_){}
        if(!_current(epoch))return;
        phase=AppPhase.signedOut;error='Sua sessão expirou. Entre novamente.';
      }else{phase=AppPhase.unavailable;error='Não foi possível conectar. Sua sessão foi preservada.';}
    }
    if(_current(epoch))_emit();
  }
  Future<void> _hydrate(int epoch) async {
    await Future.wait([reloadCommunities(),reloadThreads(),checkIntegrations()]);
    if(_current(epoch))_startRealtime(epoch);
  }
  Future<bool> authenticate(String username,String password,{bool register=false}) async {
    if(busy)return false;
    final epoch=++_sessionEpoch;busy=true;error=null;_emit();
    try{
      api.baseUrl=validateApiEndpoint(api.baseUrl);api.token=null;
      final result=await api.request('POST',register?'/api/register':'/api/login',{'username':username.trim(),'password':password});
      await acceptSession(result,epoch:epoch);
      return _current(epoch) && phase==AppPhase.signedIn;
    }catch(failure){
      if(_current(epoch)){phase=AppPhase.signedOut;error=_friendly(failure);}return false;
    }finally{if(_current(epoch)){busy=false;_emit();}}
  }
  Future<void> acceptSession(Json result,{int? epoch}) async {
    final generation=epoch??++_sessionEpoch;if(!_current(generation))return;
    final token=requiredString(result,'token');
    if(!RegExp(r'^[a-f0-9]{64}$').hasMatch(token))throw const FormatException('Sessão recebida é inválida.');
    final user=Account.fromJson(asJson(result['user']));
    _stopRealtime();_resetWorkspace();api.token=token;account=user;
    try{await sessions.save(api.baseUrl,token);}catch(_){
      if(_current(generation))error='Você entrou, mas não foi possível salvar a sessão neste aparelho.';
    }
    if(!_current(generation))return;
    phase=AppPhase.signedIn;await _hydrate(generation);
    if(_current(generation))_emit();
  }
  Future<bool> loginDiscord(Future<bool> Function(Uri) openBrowser) async {
    if(busy)return false;
    busy=true;error=null;final oauth=++_oauthEpoch,epoch=_sessionEpoch;_emit();
    try{
      final request=DiscordLoginRequest.fromJson(await api.request('POST','/api/auth/discord/start'));
      if(!_current(epoch) || oauth!=_oauthEpoch)return false;
      if(!await openBrowser(request.url))throw StateError('Não foi possível abrir o navegador.');
      for(var attempt=0;attempt<100;attempt++){
        await Future<void>.delayed(const Duration(seconds:2));
        if(!_current(epoch) || oauth!=_oauthEpoch)return false;
        final response=await api.request('POST','/api/auth/discord/poll',{'request_id':request.requestId,'poll_secret':request.pollSecret});
        if(!_current(epoch) || oauth!=_oauthEpoch)return false;
        if(response['status']=='ready'){await acceptSession(response,epoch:epoch);return _current(epoch) && phase==AppPhase.signedIn;}
      }
      throw StateError('Tempo para autorizar esgotado. Tente novamente.');
    }catch(failure){
      if(_current(epoch) && oauth==_oauthEpoch)error=failure is ApiException && failure.statusCode==503?'Login Discord ainda não configurado no servidor.':_friendly(failure);
      return false;
    }finally{if(!_disposed && oauth==_oauthEpoch){busy=false;_emit();}}
  }
  void cancelDiscordLogin(){
    _oauthEpoch++;_sessionEpoch++;_stopRealtime();
    if(api.token!=null && phase!=AppPhase.signedIn){
      api.token=null;account=null;_resetWorkspace();
      unawaited(sessions.clear().catchError((Object _){}));
    }
    busy=false;_emit();
  }
  Future<void> configureAddress(String input) async {
    final address=validateApiEndpoint(input);if(address==api.baseUrl)return;
    await logout();api.baseUrl=address;await sessions.saveAddress(address);_emit();
  }
  Future<void> logout() async {
    final oldToken=api.token,oldAddress=api.baseUrl;
    _sessionEpoch++;_navigationEpoch++;_membersEpoch++;_oauthEpoch++;_stopRealtime();
    api.token=null;account=null;_resetWorkspace();busy=false;error=null;phase=AppPhase.signedOut;_emit();
    if(oldToken!=null){
      final previous=Api(oldAddress)..token=oldToken;
      unawaited(previous.request('POST','/api/logout').then<void>((_){},onError:(Object _){}));
    }
    try{await sessions.clear();}catch(_){
      if(!_disposed){error='A sessão terminou, mas o armazenamento local não respondeu.';_emit();}
    }
  }
  void _resetWorkspace(){
    _navigationEpoch++;_membersEpoch++;
    communities=const [];channels=const [];threads=const [];members=const [];
    integrations=null;selectedCommunityId=null;conversation=null;showMembers=false;loadingConversation=false;
    _timelines.clear();_fetches.clear();_dirty.clear();_pending.clear();_sending.clear();_drafts.clear();_unread.clear();
  }
  void showLogin(){
    _sessionEpoch++;_stopRealtime();api.token=null;account=null;_resetWorkspace();
    phase=AppPhase.signedOut;error=null;busy=false;_emit();
  }
  Future<T?> operation<T>(Future<T> Function() task) async {
    if(busy || phase!=AppPhase.signedIn)return null;
    final epoch=_sessionEpoch;busy=true;error=null;_emit();
    try{final result=await task();return _current(epoch)?result:null;}catch(failure){
      if(_current(epoch))await _handleFailure(failure);return null;
    }finally{if(_current(epoch)){busy=false;_emit();}}
  }
  Future<void> reloadCommunities() async {
    if(api.token==null)return;final epoch=_sessionEpoch,index=++_indexEpoch;
    try{
      final result=await api.request('GET','/api/servers');
      if(!_current(epoch) || index!=_indexEpoch)return;
      communities=List.unmodifiable(jsonRows(result,'servers').map(Community.fromJson));
      if(selectedCommunityId!=null && selectedCommunity==null){openHome();}
      else if(selectedCommunityId!=null){await _loadChannels(selectedCommunityId!,_navigationEpoch,epoch);}
      _emit();
    }catch(failure){if(_current(epoch) && index==_indexEpoch)await _handleFailure(failure);}
  }
  Future<void> reloadThreads() async {
    if(api.token==null)return;final epoch=_sessionEpoch,index=++_threadEpoch;
    try{
      final result=await api.request('GET','/api/dms');
      if(!_current(epoch) || index!=_threadEpoch)return;
      threads=List.unmodifiable(jsonRows(result,'threads').map(DirectThread.fromJson));_emit();
    }catch(failure){if(_current(epoch) && index==_threadEpoch)await _handleFailure(failure);}
  }
  Future<void> checkIntegrations() async {
    if(api.token==null)return;final epoch=_sessionEpoch;
    try{
      final result=await api.request('GET','/api/integrations/status');
      if(!_current(epoch))return;integrations=IntegrationAvailability.fromJson(result);_emit();
    }catch(_){}
  }
  void openHome(){
    _navigationEpoch++;selectedCommunityId=null;channels=const [];members=const [];
    conversation=null;showMembers=false;loadingConversation=false;_emit();
  }
  Future<void> selectCommunity(Community community) async {
    final navigation=++_navigationEpoch,epoch=_sessionEpoch;
    selectedCommunityId=community.id;conversation=null;channels=const [];members=const [];
    showMembers=false;loadingConversation=true;error=null;_emit();
    await _loadChannels(community.id,navigation,epoch);
    if(_current(epoch) && navigation==_navigationEpoch){loadingConversation=false;_emit();}
  }
  Future<void> _loadChannels(String id,int navigation,int epoch) async {
    try{
      final result=await api.request('GET','/api/servers/$id/channels');
      if(!_current(epoch) || navigation!=_navigationEpoch || selectedCommunityId!=id)return;
      channels=List.unmodifiable(jsonRows(result,'channels').map(CommunityChannel.fromJson));
      if(conversation==null || !conversation!.isDirect && !channels.any((row)=>row.id==conversation!.id)){
        final first=channels.where((row)=>row.kind==ChannelKind.text).firstOrNull;
        conversation=first==null?null:Conversation.channel(first.id);
      }
      _emit();await refreshMessages();
    }catch(failure){if(_current(epoch) && navigation==_navigationEpoch)await _handleFailure(failure);}
  }
  Future<void> selectChannel(CommunityChannel channel) async {
    if(channel.kind!=ChannelKind.text || !channels.any((row)=>row.id==channel.id))return;
    _navigationEpoch++;conversation=Conversation.channel(channel.id);_unread.remove(conversation);error=null;_emit();
    await refreshMessages();
  }
  Future<void> selectThread(DirectThread thread) async {
    _navigationEpoch++;selectedCommunityId=null;channels=const [];members=const [];showMembers=false;
    conversation=Conversation.direct(thread.id);_unread.remove(conversation);error=null;_emit();await refreshMessages();
  }
  Future<void> refreshMessages({Conversation? target}) async {
    final selected=target??conversation;if(selected==null || api.token==null)return;
    if(_fetches.containsKey(selected)){_dirty.add(selected);return;}
    final epoch=_sessionEpoch,flight=Object();_fetches[selected]=flight;
    if(selected==conversation)loadingConversation=true;_emit();
    try{
      do{
        _dirty.remove(selected);
        for(var page=0;page<50;page++){
          final cached=_timelines[selected]??const <ChatMessage>[];
          final cursor=cached.isEmpty?0:cached.last.id;
          final result=await api.request('GET',selected.route+'?after=$cursor');
          if(!_current(epoch))return;
          final arriving=jsonRows(result,'messages').map(ChatMessage.fromJson).toList();
          if(arriving.isEmpty)break;
          final merged=mergeMessages(_timelines[selected]??const [],arriving);
          _timelines[selected]=merged;_emit();
          if(arriving.length<100 || merged.last.id<=cursor)break;
        }
      }while(_current(epoch) && _dirty.contains(selected));
    }catch(failure){if(_current(epoch) && selected==conversation)await _handleFailure(failure);}
    finally{
      if(identical(_fetches[selected],flight)){
        _fetches.remove(selected);if(selected==conversation)loadingConversation=false;_emit();
      }
    }
  }
  Future<bool> send(String input) async {
    final target=conversation,content=input.trim();
    if(target==null || content.isEmpty || api.token==null || _sending.contains(target))return false;
    if(content.length>4000){error='A mensagem deve ter até 4000 caracteres.';_emit();return false;}
    final epoch=_sessionEpoch,previous=_pending[target];
    final pending=previous!=null && previous.matches(target.route,content)?previous:PendingMessage(route:target.route,content:content,nonce:createClientNonce());
    _pending[target]=pending;_sending.add(target);error=null;_emit();
    try{
      final result=await api.request('POST',target.route,{'content':content,'client_nonce':pending.nonce});
      if(!_current(epoch))return false;
      final confirmed=ChatMessage.fromJson(asJson(result['message']));
      _timelines[target]=mergeMessages(_timelines[target]??const [],[confirmed]);
      if(identical(_pending[target],pending))_pending.remove(target);
      if(draft(target).trim()==content)_drafts.remove(target);
      _emit();return true;
    }catch(failure){if(_current(epoch))await _handleFailure(failure);return false;}
    finally{if(_current(epoch)){_sending.remove(target);_emit();}}
  }
  Future<void> refreshMembers() async {
    final id=selectedCommunityId;if(id==null || api.token==null)return;
    final epoch=_sessionEpoch,request=++_membersEpoch;
    try{
      final result=await api.request('GET','/api/servers/$id/members');
      if(!_current(epoch) || id!=selectedCommunityId || request!=_membersEpoch)return;
      members=List.unmodifiable(jsonRows(result,'members').map(CommunityMember.fromJson));_emit();
    }catch(failure){if(_current(epoch) && id==selectedCommunityId)await _handleFailure(failure);}
  }
  void toggleMembers(){if(selectedCommunityId==null)return;showMembers=!showMembers;_emit();if(showMembers)unawaited(refreshMembers());}
  Future<void> createCommunity(String name) async {
    final result=await operation(()=>api.request('POST','/api/servers',{'name':name.trim()}));
    if(result==null || phase!=AppPhase.signedIn)return;
    final id=requiredString(asJson(result['server']),'id');await reloadCommunities();
    final server=communities.where((row)=>row.id==id).firstOrNull;if(server!=null)await selectCommunity(server);
  }
  Future<void> joinInvitation(String input) async {
    var code=input.trim();final uri=Uri.tryParse(code);
    if(uri!=null && uri.hasScheme)code=uri.pathSegments.lastOrNull??'';
    if(!RegExp(r'^[a-zA-Z0-9_-]{4,128}$').hasMatch(code)){error='Cole um código de convite Veylor válido.';_emit();return;}
    final result=await operation(()=>api.request('POST','/api/invites/$code/join'));
    if(result==null || phase!=AppPhase.signedIn)return;
    await reloadCommunities();final server=communities.where((row)=>row.id==result['server_id']).firstOrNull;
    if(server!=null)await selectCommunity(server);
  }
  Future<String?> createInvitation() async {
    final id=selectedCommunityId;if(id==null)return null;
    final result=await operation(()=>api.request('POST','/api/servers/$id/invites'));
    return result==null?null:requiredString(result,'code');
  }
  Future<void> createChannel(String name,ChannelKind kind) async {
    final id=selectedCommunityId;if(id==null)return;
    await operation(()=>api.request('POST','/api/servers/$id/channels',{'name':name.trim(),'type':kind.name}));
    if(selectedCommunityId==id)await _loadChannels(id,_navigationEpoch,_sessionEpoch);
  }
  Future<void> deleteChannel(CommunityChannel channel) async {
    final id=selectedCommunityId;if(id==null)return;
    await operation(()=>api.request('DELETE','/api/servers/$id/channels/'+channel.id));
    if(selectedCommunityId==id)await _loadChannels(id,_navigationEpoch,_sessionEpoch);
  }
  Future<void> startDirectMessage(String username) async {
    final result=await operation(()=>api.request('POST','/api/dms',{'username':username.trim()}));
    if(result==null || phase!=AppPhase.signedIn)return;
    final thread=DirectThread.fromJson(asJson(result['thread']));
    await reloadThreads();await selectThread(thread);
  }
  Future<void> manageMember(CommunityMember member,String action) async {
    final id=selectedCommunityId;if(id==null)return;
    await operation(()=>api.request(action=='kick'?'DELETE':'PATCH','/api/servers/$id/members/'+member.id,action=='kick'?null:{'role':action}));
    await refreshMembers();
  }
  void reconnect(){
    if(api.token==null){unawaited(bootstrap());}
    else{_startRealtime(_sessionEpoch);unawaited(refreshMessages());unawaited(checkIntegrations());}
  }
  void _startRealtime(int epoch){
    _stopRealtime();final token=api.token;if(token==null || !_current(epoch))return;
    realtime.start(address:api.baseUrl,token:token,onEvent:(event){if(_current(epoch))_onEvent(event);},
      onStatus:(status){if(!_current(epoch))return;connection=status;_emit();});
    _poll=Timer.periodic(pollInterval,(_){if(!_current(epoch))return;unawaited(refreshMessages());unawaited(reloadThreads());});
  }
  void _onEvent(Json event){
    final type=event['type'];
    if(type=='connected'){unawaited(refreshMessages());unawaited(reloadThreads());unawaited(reloadCommunities());}
    if(type=='channel.message' || type=='dm.message'){
      final id=event[type=='dm.message'?'thread_id':'channel_id'];
      if(id is String){
        final target=type=='dm.message'?Conversation.direct(id):Conversation.channel(id);
        if(target==conversation){unawaited(refreshMessages(target:target));}else{_unread.add(target);_emit();}
      }
    }
    if(type=='dm.updated' || type=='dm.message')unawaited(reloadThreads());
    if(type=='server.updated' || type=='server.removed'){unawaited(reloadCommunities());if(showMembers)unawaited(refreshMembers());}
  }
  Future<void> _handleFailure(Object failure) async {
    if(failure is ApiException && failure.statusCode==401 && phase==AppPhase.signedIn){
      final next=_sessionEpoch+1;await logout();if(!_current(next))return;error='Sua sessão expirou. Entre novamente.';
    }else{error=_friendly(failure);}_emit();
  }
  String _friendly(Object failure){
    if(failure is ApiException)return failure.message;
    if(failure is FormatException)return failure.message;
    return 'Não foi possível concluir. Verifique a conexão e tente novamente.';
  }
  void _stopRealtime(){_poll?.cancel();_poll=null;realtime.stop();connection=RealtimeStatus.offline;}
  @override void dispose(){_disposed=true;_sessionEpoch++;_oauthEpoch++;_stopRealtime();super.dispose();}
}
