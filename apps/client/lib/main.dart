import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'client_stability.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_service.dart';
import 'api_endpoint.dart';

void main() => runApp(const VeylorApp());
const accent = Color(0xFF7565EE);
const surface = Color(0xFF202127);
const sidebar = Color(0xFF15161B);

class Api {
  Api(this.baseUrl);
  String baseUrl;
  String? token;
  Future<Map<String,dynamic>> request(String method, String route, [Map<String,dynamic>? body]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, Uri.parse(baseUrl + route));
      req.headers.contentType = ContentType.json;
      if(token != null) req.headers.set('Authorization','Bearer ' + token!);
      if(body != null) req.write(jsonEncode(body));
      final response = await req.close().timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(
        await utf8.decoder.bind(response).join().timeout(const Duration(seconds:15))
      ) as Map<String,dynamic>;
      if(response.statusCode >= 400) {
        throw ApiException(response.statusCode, (decoded['error'] ?? 'Erro HTTP').toString());
      }
      return decoded;
    } finally {
      client.close(force:true);
    }
  }
}
class ApiException implements Exception {
  const ApiException(this.statusCode,this.message);
  final int statusCode;
  final String message;
  @override
  String toString()=>message;
}

class VeylorApp extends StatelessWidget {
  const VeylorApp({super.key, this.sessionRestorationEnabled=true});
  final bool sessionRestorationEnabled;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title:'Veylor 2.0',debugShowCheckedModeBanner:false,
    theme:ThemeData.dark(useMaterial3:true).copyWith(
      scaffoldBackgroundColor:const Color(0xFF292B34),
      colorScheme:const ColorScheme.dark(primary:accent,surface:surface),
      inputDecorationTheme:InputDecorationTheme(
        filled:true,fillColor:sidebar,
        border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:BorderSide.none))),
    home:Home(sessionRestorationEnabled:sessionRestorationEnabled));
}
class Home extends StatefulWidget {
  const Home({super.key, this.sessionRestorationEnabled=true});
  final bool sessionRestorationEnabled;
  @override
  State<Home> createState()=>_HomeState();
}
class _HomeState extends State<Home> {
  final api=Api(const String.fromEnvironment('VEYLOR_API_URL',defaultValue:'https://veylor-postgres-staging.onrender.com'));
  final user=TextEditingController(),password=TextEditingController(),message=TextEditingController();
  Timer? polling,retrySocket;
  WebSocket? socket;
  final backoff=RetryBackoff();
  PendingMessage? pendingMessage;
  bool socketConnecting=false,refreshing=false,refreshAgain=false,sending=false;
  int socketEpoch=0;
  final storage=const FlutterSecureStorage();
  bool restoring=true,realtime=false,checkingUpdate=false,sessionMoved=false;
  String? nick,serverId,channelId,dmId,error;
  List<Map<String,dynamic>> dms=[];
  bool signup=false,busy=false;
  List<Map<String,dynamic>> servers=[],channels=[],messages=[];
  int cursor=0;
  @override
  void initState(){super.initState();if(widget.sessionRestorationEnabled){restoreSession();}else{restoring=false;}}
  @override
  void dispose() {
    stopRealtime();
    user.dispose();password.dispose();message.dispose();super.dispose();
  }
  Future<void> restoreSession() async {
    try {
      final savedAddress=await storage.read(key:'veylor_api_url').timeout(const Duration(seconds:6));
      final selection=selectStartupServer(savedAddress,defaultAddress:api.baseUrl);
      api.baseUrl=selection.address;
      final saved=await storage.read(key:'veylor_session').timeout(const Duration(seconds:6));
      if(selection.clearOldSession){
        sessionMoved=selection.movedFromLegacy && saved!=null && saved.isNotEmpty;
        await storage.delete(key:'veylor_session');
        await storage.write(key:'veylor_api_url',value:selection.address);
      }
      if(!selection.clearOldSession&&saved!=null&&saved.isNotEmpty){
        api.token=saved;
        final profile=await api.request('GET','/api/me');
        nick=(profile['user'] as Map<String,dynamic>)['username'] as String;
        await loadServers();await loadDms();startRealtime();
      }
    }on ApiException catch(e){
      api.token=null;
      if(e.statusCode==401){
        try{await storage.delete(key:'veylor_session');}catch(_){}
      }else{
        error='Servidor indisponível. Sua sessão foi preservada; tente reconectar.';
      }
    }catch(_){
      api.token=null;
      error='Sem conexão. Sua sessão foi preservada; tente reconectar.';
    }finally{
      if(mounted){
        setState(()=>restoring=false);
        if(Platform.isAndroid||Platform.isWindows){
          WidgetsBinding.instance.addPostFrameCallback((_){
            if(mounted)checkForUpdates(silent:true);
          });
        }
      }
    }
  }
  Future<void> checkForUpdates({bool silent=false}) async {
    if((!Platform.isAndroid&&!Platform.isWindows) || checkingUpdate)return;
    checkingUpdate=true;
    try {
      final isAndroid=Platform.isAndroid;
      // Never send bearer sessions or use untrusted custom servers for updates.
      final updatesApi=Api(newVeylorApi);
      final response=await updatesApi.request('GET',
          isAndroid?'/api/updates/android':'/api/updates/windows');
      final AppUpdateInfo update=isAndroid
          ? AndroidUpdate.fromJson(response) : WindowsUpdate.fromJson(response);
      final installed=await PackageInfo.fromPlatform();
      final currentBuild=int.tryParse(installed.buildNumber)??0;
      if(!mounted)return;
      if(!update.isNewerThan(currentBuild)){
        if(!silent)ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content:Text('Você está usando a versão mais recente deste canal beta.')));
        return;
      }
      await showDialog<void>(context:context,builder:(dialogContext)=>AlertDialog(
        title:Text('Veylor ${update.version} disponível'),
        content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Nova compilação ${update.build}. Atual: ${installed.version} (${installed.buildNumber}).'),
          const SizedBox(height:12),Text(update.notes),
          const SizedBox(height:12),
          Text(Platform.isAndroid
            ? 'O download exige acesso ao GitHub privado. APKs de teste podem ter '
              'assinaturas diferentes e exigir reinstalação.'
            : 'O instalador abre a página oficial do GitHub privado. A instalação '
              'é manual, não executamos arquivos remotamente. O Windows pode '
              'mostrar um alerta por falta de assinatura digital.',
            style:const TextStyle(fontSize:12)),
        ]),
        actions:[
          TextButton(onPressed:()=>Navigator.of(dialogContext).pop(),
            child:const Text('Depois')),
          FilledButton(onPressed:() async {
            Navigator.of(dialogContext).pop();
            final success=await launchUrl(update.downloadUrl,mode:LaunchMode.externalApplication);
            if(!success&&mounted)ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content:Text('Não foi possível abrir o GitHub.')));
          },child:const Text('Abrir download'))
        ]));
    }catch(e){
      if(!silent&&mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Falha ao verificar atualização: $e')));
    }finally{checkingUpdate=false;}
  }
  Future<void> configureBackend() async {
    final controller=TextEditingController(text:api.baseUrl);
    final address=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Servidor Veylor'),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Informe o endereço HTTPS do servidor. HTTP só é permitido localmente.'),
        const SizedBox(height:12),
        TextField(controller:controller,autofocus:true,keyboardType:TextInputType.url,
          decoration:const InputDecoration(labelText:'URL da API',hintText:'https://api.exemplo.com')),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text),child:const Text('Salvar'))
      ]));
    controller.dispose();
    if(address==null)return;
    try {
      final normalized=validateApiEndpoint(address);
      if(normalized!=api.baseUrl){
        stopRealtime();
        pendingMessage=null;
        api.token=null;
        await storage.delete(key:'veylor_session');
        await storage.write(key:'veylor_api_url',value:normalized);
        if(mounted)setState(() {api.baseUrl=normalized;error=null;});
      }
    }catch(e){if(mounted)setState(()=>error=e.toString());}
  }
  void stopRealtime(){
    socketEpoch++;
    polling?.cancel();
    retrySocket?.cancel();
    socket?.close();
    socket=null;
    socketConnecting=false;
    backoff.reset();
  }
  void scheduleReconnect(int epoch){
    if(!mounted||epoch!=socketEpoch||api.token==null)return;
    retrySocket?.cancel();
    retrySocket=Timer(backoff.nextDelay(),connectSocket);
  }
  void startRealtime(){
    stopRealtime();
    if(api.token==null)return;
    // Polling is a fallback if WebSocket events are lost during sleep/outage.
    polling=Timer.periodic(const Duration(seconds:30),(_){
      refresh();
      loadDms().catchError((Object _){});
    });
    connectSocket();
  }
  Future<void> connectSocket() async {
    final token=api.token,epoch=socketEpoch;
    if(token==null||socket!=null||socketConnecting||!mounted)return;
    socketConnecting=true;
    try{
      final url=Uri.parse(api.baseUrl);
      final wsUrl=url.replace(scheme:url.scheme=='https'?'wss':'ws',
        path:'/api/realtime',query:null,fragment:null);
      final ws=await WebSocket.connect(wsUrl.toString(),
        headers:{HttpHeaders.authorizationHeader:'Bearer $token'})
        .timeout(const Duration(seconds:12));
      ws.pingInterval=const Duration(seconds:20);
      if(!mounted||epoch!=socketEpoch||api.token!=token){
        await ws.close();
        return;
      }
      socket=ws;
      backoff.reset();
      retrySocket?.cancel();
      setState(()=>realtime=true);
      ws.listen((data){
        try {
          final event=jsonDecode(data as String) as Map<String,dynamic>;
          final type=event['type'];
          if(type=='connected'){
            refresh(); // Recover messages missed while this client was offline.
            loadDms().catchError((Object _){});
          }
          if(type=='channel.message'&&event['channel_id']==channelId&&dmId==null)refresh();
          if(type=='dm.message'&&event['thread_id']==dmId)refresh();
          if(type=='dm.updated'||type=='dm.message')loadDms().catchError((Object _){});
          if(type=='server.updated'||type=='server.removed')loadServers().catchError((Object _){});
        }catch(_){}
      },onError:(Object _){
        ws.close();
      },onDone:(){
        if(!identical(socket,ws))return;
        socket=null;
        if(mounted)setState(()=>realtime=false);
        scheduleReconnect(epoch);
      },cancelOnError:false);
    }catch(_){
      if(epoch==socketEpoch){
        if(mounted)setState(()=>realtime=false);
        scheduleReconnect(epoch);
      }
    }finally{
      if(epoch==socketEpoch)socketConnecting=false;
    }
  }
  Future<void> loadDms() async {
    if(api.token==null)return;
    final data=await api.request('GET','/api/dms');
    if(mounted)setState(()=>dms=List<Map<String,dynamic>>.from(data['threads'] as List));
  }
  Future<void> startDm() async {
    final username=await prompt('Nova mensagem privada','Nome do usuário');
    if(username==null||username.isEmpty)return;
    await perform(() async {
      final data=await api.request('POST','/api/dms',{'username':username});
      dmId=(data['thread'] as Map<String,dynamic>)['id'] as String;
      cursor=0;messages=[];
      await loadDms();await refresh();
      if(mounted&&MediaQuery.sizeOf(context).width<730)Navigator.pop(context);
    });
  }
  Future<void> createChannel(String type) async {
    if(serverId==null)return;
    final name=await prompt('Criar canal '+(type=='voice'?'de voz':'de texto'),'Nome do canal');
    if(name==null||name.isEmpty)return;
    await perform(() async {
      await api.request('POST','/api/servers/'+serverId!+'/channels',{'name':name,'type':type});
      await loadChannels();
    });
  }
  bool get canManage => servers.any((s)=>s['id']==serverId&&
    (s['role']=='owner'||s['role']=='moderator'));
  bool get isOwner => servers.any((s)=>s['id']==serverId&&s['role']=='owner');
  Future<void> manageMembers() async {
    if(serverId==null)return;
    await perform(() async {
      final selectedServer=serverId!;
      final result=await api.request('GET','/api/servers/'+selectedServer+'/members');
      if(!mounted)return;
      final members=List<Map<String,dynamic>>.from(result['members'] as List);
      await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Membros e cargos'),
        content:SizedBox(width:440,height:340,child:ListView(children:[
          for(final m in members) ListTile(
            title:Text(m['username'] as String),
            subtitle:Text(m['role'] as String),
            trailing:m['role']=='owner'?null:PopupMenuButton<String>(
              tooltip:'Gerenciar membro',
              onSelected:(action) async {
                Navigator.pop(ctx);
                await perform(() async {
                  final endpoint='/api/servers/'+selectedServer+'/members/'+(m['id'] as String);
                  if(action=='kick')await api.request('DELETE',endpoint);
                  else await api.request('PATCH',endpoint,{'role':action});
                  await loadServers();
                });
              },
              itemBuilder:(_)=>[
                if(isOwner)const PopupMenuItem(value:'moderator',child:Text('Tornar moderador')),
                if(isOwner)const PopupMenuItem(value:'member',child:Text('Tornar membro')),
                if(canManage)const PopupMenuItem(value:'kick',child:Text('Remover do servidor'))
              ]))
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Fechar'))]));
    });
  }

  Future<void> perform(Future<void> Function() task) async {
    setState(() {busy=true;error=null;});
    try {await task();} catch(e) {if(mounted)setState(()=>error=e.toString().replaceFirst('Exception: ',''));}
    finally {if(mounted)setState(()=>busy=false);}
  }
  Future<void> authenticate()=>perform(() async {
    api.baseUrl=validateApiEndpoint(api.baseUrl);
    final data=await api.request('POST',signup?'/api/register':'/api/login',
      {'username':user.text.trim(),'password':password.text});
    api.token=data['token'] as String;
    nick=(data['user'] as Map<String,dynamic>)['username'] as String;
    password.clear();
    await storage.write(key:'veylor_session',value:api.token);
    await loadServers();await loadDms();startRealtime();
  });
  Future<void> loadServers() async {
    final r=await api.request('GET','/api/servers');
    servers=List<Map<String,dynamic>>.from(r['servers'] as List);
    if(!servers.any((s)=>s['id']==serverId))serverId=servers.isEmpty?null:servers.first['id'] as String;
    await loadChannels();
  }
  Future<void> loadChannels() async {
    final previousChannel=channelId;
    channels=[];
    if(serverId!=null){
      final r=await api.request('GET','/api/servers/'+serverId!+'/channels');
      channels=List<Map<String,dynamic>>.from(r['channels'] as List);
    }
    if(!channels.any((c)=>c['id']==channelId&&c['type']=='text')){
      channelId=null;
      for(final c in channels){if(c['type']=='text'){channelId=c['id'] as String;break;}}
    }
    // Preserve currently displayed messages when membership/channel metadata changes.
    if(dmId==null&&(messages.isEmpty||previousChannel!=channelId)) {
      cursor=0;messages=[];
      await refresh();
    }
    if(mounted)setState((){});
  }
  Future<void> refresh() async {
    if(refreshing){refreshAgain=true;return;}
    refreshing=true;
    try{
      do{
        refreshAgain=false;
        final id=dmId??channelId,isDm=dmId!=null;
        if(id==null||api.token==null)break;
        try{
          // Fetch every page, not only the first 100 messages after an outage.
          for(var pages=0;pages<50;pages++){
            final route=isDm?'/api/dms/$id/messages':'/api/channels/$id/messages';
            final result=await api.request('GET','$route?after=$cursor');
            if(!mounted||api.token==null||id!=(isDm?dmId:channelId))break;
            final rows=List<Map<String,dynamic>>.from(result['messages'] as List);
            if(rows.isEmpty)break;
            setState((){
              messages=mergeMessagePages(messages,rows);
              cursor=messages.last['id'] as int;
            });
            if(rows.length<100)break;
          }
        }catch(e){if(mounted)setState(()=>error=e.toString());}
      }while(refreshAgain&&mounted);
    }finally{refreshing=false;}
  }
  Future<void> send() async {
    if(sending)return;
    final text=message.text.trim();
    if(text.isEmpty||(dmId==null&&channelId==null))return;
    final route=dmId!=null?'/api/dms/'+dmId!+'/messages':'/api/channels/'+channelId!+'/messages';
    final previous=pendingMessage;
    final pending=previous!=null&&previous.matches(route,text)
      ?previous:PendingMessage(route:route,content:text,nonce:createClientNonce());
    pendingMessage=pending;
    sending=true;
    try{
      await perform(() async {
        await api.request('POST',route,{'content':text,'client_nonce':pending.nonce});
        // Never delete anything typed while a slow request was in flight.
        if(message.text.trim()==text)message.clear();
        if(identical(pendingMessage,pending))pendingMessage=null;
        await refresh();
      });
    }finally{sending=false;}
  }
  Future<String?> prompt(String title,String hint) async {
    final controller=TextEditingController();
    final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(title),content:TextField(controller:controller,autofocus:true,
        decoration:InputDecoration(hintText:hint)),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text.trim()),child:const Text('OK'))]));
    controller.dispose();return result;
  }
  Future<void> createServer() async {
    final name=await prompt('Criar servidor','Nome');
    if(name==null||name.isEmpty)return;
    await perform(() async {
      final r=await api.request('POST','/api/servers',{'name':name});
      serverId=(r['server'] as Map<String,dynamic>)['id'] as String;
      await loadServers();
    });
  }
  Future<void> joinInvite() async {
    final code=await prompt('Entrar no servidor','Código de convite');
    if(code==null||code.isEmpty)return;
    await perform(() async {
      final r=await api.request('POST','/api/invites/'+Uri.encodeComponent(code)+'/join');
      serverId=r['server_id'] as String;
      await loadServers();
    });
  }
  Future<void> invite() async {
    if(serverId==null)return;
    await perform(() async {
      final r=await api.request('POST','/api/servers/'+serverId!+'/invites');
      if(!mounted)return;
      await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Convite válido por 7 dias'),
        content:SelectableText(r['code'] as String),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Fechar'))]));
    });
  }
  Future<void> voice(Map<String,dynamic> c) async {
    await perform(() async {
      await api.request('POST','/api/media/token',{'channel_id':c['id']});
      if(!mounted)return;
      await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Mídia ainda não ativada'),
        content:const Text('O backend autorizou o canal. O cliente de voz e vídeo LiveKit será integrado na próxima versão.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Entendi'))]));
    });
  }
  Widget rails() => Row(children:[
    Container(width:70,color:sidebar,child:Column(children:[
      const Padding(padding:EdgeInsets.all(12),child:Icon(Icons.bubble_chart,color:accent,size:34)),
      Expanded(child:ListView(children:[
        for(final s in servers) Padding(padding:const EdgeInsets.all(6),
          child:Tooltip(message:s['name'] as String,child:InkWell(
            onTap:()=>perform(() async {dmId=null;serverId=s['id'] as String;await loadChannels();}),
            child:Container(height:50,alignment:Alignment.center,
              decoration:BoxDecoration(color:serverId==s['id']?accent:surface,
                borderRadius:BorderRadius.circular(17)),
              child:Text((s['name'] as String).substring(0,1).toUpperCase(),
                style:const TextStyle(fontSize:21,fontWeight:FontWeight.bold)))))),
        IconButton(tooltip:'Criar servidor',onPressed:createServer,icon:const Icon(Icons.add_circle_outline)),
        IconButton(tooltip:'Entrar com convite',onPressed:joinInvite,icon:const Icon(Icons.login)),
      ]))])),
    Expanded(child:Container(color:surface,child:Column(children:[
      ListTile(title:Text(servers.where((s)=>s['id']==serverId).map((s)=>s['name'] as String)
        .firstOrNull??'Veylor',maxLines:1,overflow:TextOverflow.ellipsis),
        trailing:IconButton(tooltip:'Convite',onPressed:invite,icon:const Icon(Icons.person_add))),
      const Divider(height:1),
      ListTile(title:const Text('MENSAGENS PRIVADAS',style:TextStyle(fontSize:11,color:Colors.white54)),
        trailing:IconButton(icon:const Icon(Icons.add,size:19),tooltip:'Nova DM',onPressed:startDm)),
      for(final d in dms)
        ListTile(dense:true,leading:const Icon(Icons.person_outline,size:19),
          title:Text(d['username'] as String),selected:dmId==d['id'],
          onTap:()=>perform(() async {
            dmId=d['id'] as String;cursor=0;messages=[];await refresh();
            if(mounted&&MediaQuery.sizeOf(context).width<730)Navigator.pop(context);
          })),
      ListTile(title:const Text('CANAIS DE TEXTO',style:TextStyle(fontSize:11,color:Colors.white54)),
        trailing:canManage?IconButton(icon:const Icon(Icons.add,size:19),tooltip:'Criar texto',
          onPressed:()=>createChannel('text')):null),
      for(final c in channels.where((c)=>c['type']=='text'))
        ListTile(dense:true,leading:const Icon(Icons.tag,size:18),title:Text(c['name'] as String),
          selected:channelId==c['id'],
          onTap:()=>perform(() async {
            dmId=null;channelId=c['id'] as String;cursor=0;messages=[];await refresh();
            if(mounted&&MediaQuery.sizeOf(context).width<730)Navigator.pop(context);
          })),
      ListTile(title:const Text('CANAIS DE VOZ',style:TextStyle(fontSize:11,color:Colors.white54)),
        trailing:canManage?IconButton(icon:const Icon(Icons.add,size:19),tooltip:'Criar voz',
          onPressed:()=>createChannel('voice')):null),
      for(final c in channels.where((c)=>c['type']=='voice'))
        ListTile(dense:true,leading:const Icon(Icons.volume_up_outlined,size:18),
          title:Text(c['name'] as String),onTap:()=>voice(c)),
      const Spacer(),
      if(Platform.isAndroid||Platform.isWindows)ListTile(
        leading:const Icon(Icons.system_update_alt),
        title:const Text('Verificar atualização'),
        onTap:()=>checkForUpdates()),
      ListTile(leading:const Icon(Icons.groups_2_outlined),title:const Text('Membros'),onTap:manageMembers),
      Container(color:sidebar,child:ListTile(
        leading:const CircleAvatar(backgroundColor:accent,child:Icon(Icons.person)),
        title:Text(nick??'Conta'),subtitle:Text(realtime?'V0.3.3 • Online':'V0.3.3 • Reconectando'),
        trailing:IconButton(tooltip:'Sair',icon:const Icon(Icons.logout),onPressed:() async {
          stopRealtime();
          try{await api.request('POST','/api/logout');}catch(_){}
          api.token=null;pendingMessage=null;
          try{await storage.delete(key:'veylor_session');}catch(_){}
          if(mounted)setState((){nick=null;serverId=null;dmId=null;realtime=false;servers=[];channels=[];dms=[];messages=[];});
        })))
    ])))
  ]);
  Widget chat() {
    final name=dmId!=null?(dms.where((d)=>d['id']==dmId).map((d)=>d['username'] as String).firstOrNull??'DM'):
      (channels.where((c)=>c['id']==channelId).map((c)=>c['name'] as String).firstOrNull??'geral');
    return Column(children:[
      SizedBox(height:58,child:Row(children:[
        if(MediaQuery.sizeOf(context).width<730)
          Builder(builder:(ctx)=>IconButton(onPressed:()=>Scaffold.of(ctx).openDrawer(),
            icon:const Icon(Icons.menu))),
        const SizedBox(width:15),Icon(dmId!=null?Icons.person_outline:Icons.tag,color:Colors.white54),
        const SizedBox(width:8),Text(name,style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
        const SizedBox(width:10),Icon(realtime?Icons.wifi:Icons.wifi_off,size:15,color:realtime?Colors.greenAccent:Colors.orangeAccent),
        const Spacer(),IconButton(tooltip:'Atualizar',onPressed:refresh,icon:const Icon(Icons.refresh))
      ])),
      const Divider(height:1),
      Expanded(child:ListView.builder(padding:const EdgeInsets.all(20),
        itemCount:messages.length+1,itemBuilder:(ctx,i){
          if(i==0)return Padding(padding:const EdgeInsets.only(bottom:22),
            child:Text('Bem-vindo '+(dmId!=null?'à conversa com ':'a #')+name,style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)));
          final m=messages[i-1];
          return Padding(padding:const EdgeInsets.symmetric(vertical:9),child:Row(
            crossAxisAlignment:CrossAxisAlignment.start,children:[
              CircleAvatar(radius:18,backgroundColor:accent,
                child:Text((m['username'] as String)[0].toUpperCase())),
              const SizedBox(width:12),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(m['username'] as String,style:const TextStyle(fontWeight:FontWeight.bold)),
                const SizedBox(height:3),SelectableText(m['content'] as String)
              ]))
            ]));
        })),
      if(error!=null)Text(error!,style:const TextStyle(color:Colors.orangeAccent)),
      Padding(padding:const EdgeInsets.all(14),child:Row(children:[
        Expanded(child:TextField(controller:message,maxLines:4,minLines:1,
          onSubmitted:(_)=>send(),decoration:InputDecoration(hintText:dmId!=null?'Mensagem para '+name:'Mensagem em #'+name))),
        const SizedBox(width:8),
        IconButton.filled(onPressed:busy?null:send,icon:const Icon(Icons.send))
      ]))
    ]);
  }
  Widget auth() => Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),
    child:Padding(padding:const EdgeInsets.all(24),child:Column(
      mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Icon(Icons.bubble_chart_rounded,color:accent,size:65),
        const SizedBox(height:20),
        Text(signup?'Criar conta Veylor':'Bem-vindo ao Veylor',
          textAlign:TextAlign.center,style:const TextStyle(fontSize:27,fontWeight:FontWeight.bold)),
        const SizedBox(height:14),
        if(error!=null&&error!.startsWith('Sem conexão')||
            error!=null&&error!.startsWith('Servidor indisponível'))
          TextButton.icon(onPressed:restoreSession,
            icon:const Icon(Icons.refresh),label:const Text('Tentar reconectar')),
        TextButton.icon(
          onPressed:busy?null:configureBackend,
          icon:const Icon(Icons.dns_outlined,size:17),
          label:Text('Servidor: ${api.baseUrl}',overflow:TextOverflow.ellipsis,maxLines:1)),
        if(Platform.isAndroid||Platform.isWindows)TextButton.icon(
          onPressed:()=>checkForUpdates(),icon:const Icon(Icons.system_update_alt,size:18),
          label:const Text('Verificar atualização do app')),
        const SizedBox(height:10),
        if(sessionMoved)const Padding(
          padding:EdgeInsets.only(bottom:10),
          child:Text('Mudamos para um banco novo e seguro. Crie uma conta para começar. '
            'O login anterior não foi transferido.',
            textAlign:TextAlign.center,style:TextStyle(color:Colors.amberAccent,fontSize:12))),
        TextField(controller:user,decoration:const InputDecoration(labelText:'Usuário')),
        const SizedBox(height:14),
        TextField(controller:password,obscureText:true,
          onSubmitted:(_)=>authenticate(),decoration:const InputDecoration(labelText:'Senha')),
        const SizedBox(height:20),
        FilledButton(onPressed:busy?null:authenticate,
          child:Padding(padding:const EdgeInsets.all(12),child:Text(signup?'Cadastrar':'Entrar'))),
        TextButton(onPressed:()=>setState(()=>signup=!signup),
          child:Text(signup?'Já tenho conta':'Criar conta')),
        if(error!=null)Text(error!,textAlign:TextAlign.center,
          style:const TextStyle(color:Colors.orangeAccent)),
        const SizedBox(height:12),
        const Text('Veylor V0.3.3 • PostgreSQL, DMs e tempo real',textAlign:TextAlign.center)
      ]))));
  @override
  Widget build(BuildContext context){
    if(restoring)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(api.token==null)return Scaffold(body:auth());
    final mobile=MediaQuery.sizeOf(context).width<730;
    return Scaffold(
      drawer:mobile?Drawer(width:335,child:rails()):null,
      body:Row(children:[if(!mobile)SizedBox(width:315,child:rails()),Expanded(child:chat())]));
  }
}
