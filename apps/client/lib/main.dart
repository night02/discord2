import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'client_stability.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_service.dart';
import 'windows_update_download.dart';
import 'update_health.dart';
import 'update_diagnostics.dart';
import 'voice_room.dart';
import 'discord_login.dart';
import 'api_endpoint.dart';

List<String> _startupArguments = const [];
void main(List<String> args) {
  _startupArguments = List<String>.unmodifiable(args);
  runApp(const VeylorApp());
}
const accent = Color(0xFF4BA9F4);
const surface = Color(0xFF232428);
const sidebar = Color(0xFF191A20);
const background = Color(0xFF303137);
const highlight = Color(0xFF373A44);
const muted = Color(0xFF9FA3B1);

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
    title:'Veylor',debugShowCheckedModeBanner:false,
    theme:ThemeData.dark(useMaterial3:true).copyWith(
      scaffoldBackgroundColor:background,
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
  final searchController=TextEditingController();
  final messageScroll=ScrollController();
  bool showMembers=false,searching=false;
  List<Map<String,dynamic>> memberPreview=[];
  Timer? polling,retrySocket;
  WebSocket? socket;
  final backoff=RetryBackoff();
  PendingMessage? pendingMessage;
  bool socketConnecting=false,refreshing=false,refreshAgain=false,sending=false;
  int socketEpoch=0;
  final storage=const FlutterSecureStorage();
  bool restoring=true,realtime=false,checkingUpdate=false,sessionMoved=false;
  String runningVersion = 'Veylor';
  String? nick,serverId,channelId,dmId,error;
  List<Map<String,dynamic>> dms=[];
  bool signup=false,busy=false;
  List<Map<String,dynamic>> servers=[],channels=[],messages=[];
  int cursor=0;
  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => runningVersion = 'V${info.version}');
    }).catchError((Object _) {});
    if (widget.sessionRestorationEnabled) {
      restoreSession();
    } else {
      restoring = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_reportAppReady());
      });
    }
  }
  Future<void> _reportAppReady() async {
    // A successful first frame + completed session restoration is the minimum
    // startup proof. Errors in diagnostics never block application startup.
    await StartupHandshake.signal(_startupArguments);
    await UpdateDiagnostics.add('app_startup_ready');
  }
  @override
  void dispose() {
    stopRealtime();
    user.dispose();password.dispose();message.dispose();searchController.dispose();messageScroll.dispose();super.dispose();
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(_reportAppReady());
            checkForUpdates(silent: true);
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
            : 'O Windows baixa apenas a Release oficial e valida SHA-256 antes '
              'de pedir sua confirmação. A Veylor é fechada para instalar e '
              'uma cópia da versão anterior permite reverter falhas. '
              'O instalador beta ainda não tem assinatura Authenticode.',
            style:const TextStyle(fontSize:12)),
        ]),
        actions:[
          TextButton(onPressed:()=>Navigator.of(dialogContext).pop(),
            child:const Text('Depois')),
          FilledButton(onPressed:() async {
            Navigator.of(dialogContext).pop();
            if (Platform.isWindows && update is WindowsUpdate &&
                update.downloadUrl.path.contains('/releases/tag/')) {
              await downloadWindowsUpdate(update);
            } else {
              final success=await launchUrl(update.downloadUrl,mode:LaunchMode.externalApplication);
              if(!success&&mounted)ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content:Text('Não foi possível abrir o GitHub.')));
            }
          },child:Text(Platform.isWindows && update.downloadUrl.path.contains('/releases/tag/')
              ? 'Baixar atualização' : 'Abrir download'))
        ]));
    }catch(e){
      if(!silent&&mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Falha ao verificar atualização: $e')));
    }finally{checkingUpdate=false;}
  }
  Future<void> downloadWindowsUpdate(WindowsUpdate update) async {
    if (!Platform.isWindows || !mounted) return;
    final downloader=VeylorWindowsDownloader();
    final progress=ValueNotifier<double>(0);
    bool cancelled=false;
    final downloadMessage = ValueNotifier<String>('Preparando download...');
    WindowsUpdatePackage? staged;
    final progressDialog=showDialog<void>(
      context:context, barrierDismissible:false,
      builder:(ctx)=>AlertDialog(
        title:const Text('Baixando instalador oficial'),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          ValueListenableBuilder<double>(valueListenable:progress,
            builder:(_,value,__)=>Column(children:[
              LinearProgressIndicator(value:value),
              const SizedBox(height:12),
              Text('${(value*100).toStringAsFixed(0)}% — verificaremos o SHA-256 antes de instalar.'),
              ValueListenableBuilder<String>(
                valueListenable: downloadMessage,
                builder: (_, message, __) => Text(message,
                  style: const TextStyle(fontSize: 12)),
              )
            ]))
        ]),
        actions:[TextButton(onPressed:() {
          cancelled = true;
          downloader.cancel();
        },child:const Text('Cancelar download'))],
      ));
    try {
      staged=await downloader.prepare(update,
        cancelled: () => cancelled,
        onRetry: (attempt) {
          downloadMessage.value = 'Reconectando... tentativa ${attempt + 1}/3';
        },
        onProgress: (received,total) {
          if (total > 0) progress.value = received / total;
        });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Atualização recusada: $e')));
      return;
    } finally {
      downloader.close();
      if (mounted) Navigator.of(context,rootNavigator:true).pop();
      await progressDialog;
      progress.dispose();
      downloadMessage.dispose();
    }
    final package=staged;
    if (!mounted || cancelled) {
      await package.discard();
      return;
    }
    final installer=package.installer;
    final current=(await PackageInfo.fromPlatform()).version;
    final approved=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('Instalar Veylor ${package.version}?'),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Versão atual: $current'),
        Text('Instalador: ${installer.path.split(Platform.pathSeparator).last}'),
        const SizedBox(height:8),
        Text('SHA-256 verificado: ${package.sha256.substring(0,16)}…',
          style:const TextStyle(fontSize:12)),
        const SizedBox(height:12),
        const Text('Ao confirmar, a Veylor será fechada e a instalação começará. '
          'O atualizador salva uma cópia dos arquivos anteriores e tenta '
          'restaurá-la se a instalação falhar. Sem certificado Windows, '
          'o sistema pode exibir um aviso de segurança.'),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Agora não')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Instalar e reiniciar'))
      ]));
    if(approved!=true){await package.discard();return;}
    await UpdateDiagnostics.add('install_confirmed');
    try {
      final currentExe=File(Platform.resolvedExecutable);
      if(currentExe.uri.pathSegments.last.toLowerCase()!='veylor.exe') {
        throw const FormatException('Atualizador só funciona no aplicativo Windows instalado.');
      }
      final helper=File('${currentExe.parent.path}${Platform.pathSeparator}veylor-updater.exe');
      if(!await helper.exists()) {
        throw const FileSystemException('Componente de atualização não encontrado');
      }
      if(!await File('${currentExe.parent.path}${Platform.pathSeparator}unins000.exe').exists()) {
        throw const FileSystemException('Instalação portátil detectada. Atualize manualmente usando o GitHub.');
      }
      final copy=await helper.copy('${package.directory.path}${Platform.pathSeparator}veylor-updater.exe');
      await Process.start(copy.path,[
        '--installer',installer.path,
        '--sha256',package.sha256,
        '--install-dir',currentExe.parent.path,
        '--parent-pid','$pid',
        '--target-version',package.version,
      ],mode:ProcessStartMode.detached);
      // The separate helper waits until this Windows process has fully exited.
      exit(0);
    } catch(e){
      await package.discard();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Instalação não iniciada: $e')));
    }
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
  Future<void> loginWithDiscord() async {
    if(busy)return;
    setState(() {busy=true;error=null;});
    bool cancelled=false;
    bool progressVisible=false;
    try {
      final start=await api.request('POST','/api/auth/discord/start');
      final authorization=DiscordLoginRequest.fromJson(start);
      final opened=await launchUrl(authorization.url,mode:LaunchMode.externalApplication);
      if(!opened)throw StateError('Não foi possível abrir o navegador para autenticar.');
      if(!mounted)return;
      progressVisible=true;
      final modal=showDialog<void>(
        context:context,barrierDismissible:false,
        builder:(ctx)=>PopScope(canPop:false,child:AlertDialog(
          title:const Text('Entrar com Discord'),
          content:const Column(mainAxisSize:MainAxisSize.min,children:[
            CircularProgressIndicator(),
            SizedBox(height:20),
            Text('Autorize a Veylor no navegador. Esta janela aguardará a confirmação.'),
          ]),
          actions:[TextButton(onPressed:(){
            cancelled=true;
            progressVisible=false;
            Navigator.of(ctx).pop();
          },child:const Text('Cancelar'))],
        )));
      for(var attempt=0;attempt<100&&!cancelled&&mounted;attempt++){
        await Future<void>.delayed(const Duration(seconds:2));
        if(cancelled||!mounted)break;
        final result=await api.request('POST','/api/auth/discord/poll',{
          'request_id':authorization.requestId,
          'poll_secret':authorization.pollSecret,
        });
        // Cancellation may happen while the network request is in flight.
        if(cancelled||!mounted)break;
        if(result['status']!='ready')continue;
        final token=result['token'],profile=result['user'];
        if(token is! String||!RegExp(r'^[a-f0-9]{64}
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
        _scrollToLatest();
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
    if(busy || api.token==null)return;
    setState(() {busy=true;error=null;});
    try {
      final response=await api.request('POST','/api/media/token',{'channel_id':c['id']});
      final access=MediaAccess.fromJson(response);
      if(!mounted)return;
      // Keep media navigation separate from chat state; never keep the global
      // busy flag set while a voice call is open.
      setState(()=>busy=false);
      _closeMobileNavigation();
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder:(_)=>VeylorVoiceRoom(
          channelName:c['name']?.toString()??'Voz',
          access:access,
        )));
    }catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text(e.toString().contains('LiveKit ainda não configurado')
          ?'O servidor de voz ainda precisa ser configurado pelo administrador.'
          :'Não foi possível entrar no canal de voz: $e')));
    }finally {
      if(mounted)setState(()=>busy=false);
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !messageScroll.hasClients) return;
      messageScroll.animateTo(messageScroll.position.maxScrollExtent,
        duration:const Duration(milliseconds:220),curve:Curves.easeOutCubic);
    });
  }

  void _closeMobileNavigation() {
    if (MediaQuery.sizeOf(context).width < 730 && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _selectDm(Map<String,dynamic> conversation) async {
    await perform(() async {
      dmId=conversation['id'] as String;
      cursor=0;messages=[];searchController.clear();
      await refresh();
      if(mounted) setState(() {});
      _closeMobileNavigation();
      _scrollToLatest();
    });
  }

  Future<void> _selectChannel(Map<String,dynamic> channel) async {
    await perform(() async {
      dmId=null;channelId=channel['id'] as String;
      cursor=0;messages=[];searchController.clear();
      await refresh();
      if(mounted) setState(() {});
      _closeMobileNavigation();
      _scrollToLatest();
    });
  }

  Future<void> _toggleMemberPanel() async {
    if (serverId==null) return;
    if (MediaQuery.sizeOf(context).width < 1100) {
      await manageMembers();
      return;
    }
    setState(() => showMembers=!showMembers);
    if(!showMembers) return;
    final requestedServer=serverId!;
    try {
      final result=await api.request('GET','/api/servers/$requestedServer/members');
      if(mounted&&serverId==requestedServer) {
        setState(()=>memberPreview=List<Map<String,dynamic>>.from(result['members'] as List));
      }
    } catch(e) {
      if(mounted) setState(()=>error='Não foi possível carregar membros: $e');
    }
  }

  Widget _brand({double size=48})=>ClipRRect(
    borderRadius:BorderRadius.circular(size*.26),
    child:Image.asset('assets/veylor_logo.png',width:size,height:size,fit:BoxFit.cover,
      filterQuality:FilterQuality.medium));

  Widget _serverRail() => Container(width:72,color:sidebar,child:Column(children:[
    const SizedBox(height:12),
    Tooltip(message:'Veylor',child:_brand(size:48)),
    Padding(padding:const EdgeInsets.symmetric(horizontal:18,vertical:12),
      child:Container(height:1,color:Colors.white12)),
    Expanded(child:ListView(padding:EdgeInsets.zero,children:[
      for(final server in servers)
        Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
          child:Tooltip(message:server['name']?.toString()??'Servidor',
            child:Material(color:serverId==server['id']?accent:surface,
              borderRadius:BorderRadius.circular(serverId==server['id']?16:24),
              clipBehavior:Clip.antiAlias,
              child:InkWell(
                key:ValueKey('server-${server['id']}'),
                onTap:()=>perform(() async {
                  dmId=null;serverId=server['id'] as String;
                  memberPreview=[];showMembers=false;
                  await loadChannels();_closeMobileNavigation();
                }),
                child:SizedBox(height:48,child:Center(
                  child:Text((server['name']?.toString().isNotEmpty??false)
                     ?server['name'].toString().substring(0,1).toUpperCase():'?',
                    style:const TextStyle(fontSize:20,fontWeight:FontWeight.w700)))))))),
      Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
        child:Tooltip(message:'Criar servidor',child:IconButton.filledTonal(
          onPressed:createServer,icon:const Icon(Icons.add,size:25)))),
      Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
        child:Tooltip(message:'Entrar com convite',child:IconButton.filledTonal(
          onPressed:joinInvite,icon:const Icon(Icons.login_rounded,size:22)))),
    ])),
  ]));

  Widget _sectionHeader(String title,VoidCallback? onAdd)=>Padding(
    padding:const EdgeInsets.fromLTRB(14,16,8,5),
    child:Row(children:[
      Expanded(child:Text(title,style:const TextStyle(color:muted,fontSize:11,
        fontWeight:FontWeight.w700,letterSpacing:.65))),
      if(onAdd!=null)IconButton(
        tooltip:'Adicionar $title',visualDensity:VisualDensity.compact,
        onPressed:onAdd,icon:const Icon(Icons.add,size:18,color:muted)),
    ]));

  Widget _navEntry({required String title,required IconData icon,
    required bool selected,required VoidCallback onTap,String? keyId})=>
    Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),
      child:Material(color:selected?highlight:Colors.transparent,
        borderRadius:BorderRadius.circular(7),
        child:InkWell(key:keyId==null?null:ValueKey(keyId),
          onTap:onTap,borderRadius:BorderRadius.circular(7),
          child:Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:10),
            child:Row(children:[
              Icon(icon,size:19,color:selected?Colors.white:muted),
              const SizedBox(width:12),
              Expanded(child:Text(title,maxLines:1,overflow:TextOverflow.ellipsis,
                style:TextStyle(color:selected?Colors.white:muted,
                  fontWeight:selected?FontWeight.w600:FontWeight.w500,fontSize:14))),
            ])))));

  Widget _channelRail()=>Expanded(child:Container(color:surface,child:Column(children:[
    SizedBox(height:62,child:Padding(padding:const EdgeInsets.symmetric(horizontal:14),
      child:Row(children:[
        Expanded(child:Text(servers.where((s)=>s['id']==serverId)
          .map((s)=>s['name']?.toString()??'Veylor').firstOrNull??'Veylor',
          maxLines:1,overflow:TextOverflow.ellipsis,
          style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700))),
        IconButton(onPressed:serverId==null?null:invite,tooltip:'Criar convite',
          icon:const Icon(Icons.person_add_alt_1_outlined,size:21))
      ]))),
    const Divider(height:1,color:Color(0xFF17181D)),
    Expanded(child:ListView(children:[
      _sectionHeader('MENSAGENS PRIVADAS',startDm),
      for(final d in dms)
        _navEntry(title:d['username']?.toString()??'Conversa',
          icon:Icons.person_outline_rounded,selected:dmId==d['id'],
          keyId:'dm-${d['id']}',onTap:()=>_selectDm(d)),
      _sectionHeader('CANAIS DE TEXTO',canManage?()=>createChannel('text'):null),
      for(final c in channels.where((c)=>c['type']=='text'))
        _navEntry(title:c['name']?.toString()??'canal',
          icon:Icons.tag_rounded,selected:dmId==null&&channelId==c['id'],
          keyId:'channel-${c['id']}',onTap:()=>_selectChannel(c)),
      _sectionHeader('CANAIS DE VOZ',canManage?()=>createChannel('voice'):null),
      for(final c in channels.where((c)=>c['type']=='voice'))
        _navEntry(title:c['name']?.toString()??'voz',
          icon:Icons.volume_up_outlined,selected:false,
          keyId:'voice-${c['id']}',onTap:()=>voice(c)),
      const SizedBox(height:20),
    ])),
    const Divider(height:1,color:Color(0xFF17181D)),
    _navEntry(title:'Membros do servidor',icon:Icons.group_outlined,
      selected:showMembers,onTap:_toggleMemberPanel),
    if(Platform.isAndroid||Platform.isWindows)
      _navEntry(title:'Verificar atualização',icon:Icons.system_update_alt_rounded,
        selected:false,onTap:()=>checkForUpdates()),
    if(Platform.isWindows)
      _navEntry(title:'Logs de atualização',icon:Icons.folder_open_outlined,
        selected:false,onTap:() async {
          try {
            final folder=UpdateDiagnostics.logDirectory;
            await folder.create(recursive:true);
            await Process.start('explorer.exe',[folder.path],
                mode:ProcessStartMode.detached);
          } catch (_) {
            if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:Text('Não foi possível abrir a pasta de logs.')));
          }
        }),
    Container(color:sidebar,padding:const EdgeInsets.symmetric(horizontal:6,vertical:6),
      child:Row(children:[
        CircleAvatar(radius:18,backgroundColor:accent,
          child:Text((nick??'V').substring(0,1).toUpperCase(),
            style:const TextStyle(fontWeight:FontWeight.w700,color:Colors.black))),
        const SizedBox(width:9),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(nick??'Conta',maxLines:1,overflow:TextOverflow.ellipsis,
            style:const TextStyle(fontWeight:FontWeight.w700,fontSize:13)),
          Text('$runningVersion • ${realtime?'Online':'Reconectando'}',
            style:TextStyle(fontSize:10,color:realtime?const Color(0xFF55D6A0):muted))
        ])),
        IconButton(tooltip:'Sair da conta',icon:const Icon(Icons.logout,size:19),
          onPressed:() async {
            stopRealtime();
            try{await api.request('POST','/api/logout');}catch(_){}
            api.token=null;pendingMessage=null;
            try{await storage.delete(key:'veylor_session');}catch(_){}
            if(mounted)setState((){
              nick=null;serverId=null;dmId=null;realtime=false;
              servers=[];channels=[];dms=[];messages=[];memberPreview=[];
            });
          })
      ])),
  ])));

  Widget rails()=>Row(children:[_serverRail(),_channelRail()]);

  Widget _memberPanel()=>Container(width:238,color:surface,child:Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Padding(padding:EdgeInsets.fromLTRB(20,24,16,12),
        child:Text('MEMBROS',style:TextStyle(color:muted,fontSize:12,
          fontWeight:FontWeight.w700,letterSpacing:1))),
      Expanded(child:ListView(children:[
        for(final person in memberPreview)
          ListTile(dense:true,leading:CircleAvatar(radius:15,
              backgroundColor:highlight,child:Text(
              (person['username']?.toString().isNotEmpty??false)
                ?person['username'].toString().substring(0,1).toUpperCase():'?')),
            title:Text(person['username']?.toString()??'Membro',
              maxLines:1,overflow:TextOverflow.ellipsis,
              style:const TextStyle(fontSize:13)),
            subtitle:Text(person['role']?.toString()??'membro',
              style:const TextStyle(fontSize:11,color:muted)))
      ])),
      TextButton.icon(onPressed:manageMembers,icon:const Icon(Icons.settings_outlined,size:17),
        label:const Text('Gerenciar membros'))
    ]));

  Widget chat() {
    final name=dmId!=null
      ?(dms.where((d)=>d['id']==dmId).map((d)=>d['username']?.toString()??'DM').firstOrNull??'DM')
      :(channels.where((c)=>c['id']==channelId).map((c)=>c['name']?.toString()??'geral').firstOrNull??'geral');
    final active=dmId!=null||channelId!=null;
    final query=searchController.text.trim().toLowerCase();
    final visible=query.isEmpty?messages:messages.where((m)=>
      (m['content']?.toString().toLowerCase().contains(query)??false)||
      (m['username']?.toString().toLowerCase().contains(query)??false)).toList();
    return Container(color:background,child:Column(children:[
      Container(height:62,padding:const EdgeInsets.symmetric(horizontal:12),
        child:Row(children:[
          if(MediaQuery.sizeOf(context).width<730)
            Builder(builder:(ctx)=>IconButton(onPressed:()=>Scaffold.of(ctx).openDrawer(),
              tooltip:'Abrir servidores e canais',icon:const Icon(Icons.menu))),
          Icon(dmId!=null?Icons.alternate_email:Icons.tag_rounded,
            color:muted,size:23),
          const SizedBox(width:10),
          Expanded(child:Text(name,maxLines:1,overflow:TextOverflow.ellipsis,
            style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700))),
          Tooltip(message:realtime?'Conectado em tempo real':'Reconectando',
            child:Icon(realtime?Icons.wifi:Icons.wifi_off,size:16,
              color:realtime?const Color(0xFF55D6A0):Colors.orangeAccent)),
          IconButton(tooltip:'Filtrar mensagens carregadas',
            onPressed:()=>setState((){
              searching=!searching;
              if(!searching)searchController.clear();
            }),icon:Icon(searching?Icons.search_off:Icons.search)),
          IconButton(tooltip:'Membros',onPressed:_toggleMemberPanel,
            icon:const Icon(Icons.people_alt_outlined)),
          IconButton(tooltip:'Atualizar mensagens',onPressed:refresh,
            icon:const Icon(Icons.refresh_rounded))
        ])),
      const Divider(height:1,color:Color(0xFF212226)),
      if(searching)Padding(padding:const EdgeInsets.fromLTRB(14,8,14,6),
        child:TextField(controller:searchController,autofocus:true,
          onChanged:(_)=>setState((){}),
          decoration:InputDecoration(isDense:true,prefixIcon:const Icon(Icons.search),
            hintText:'Filtrar mensagens já carregadas',
            suffixIcon:IconButton(onPressed:()=>setState(()=>searchController.clear()),
              icon:const Icon(Icons.close)),filled:true,fillColor:surface))),
      Expanded(child:!active
        ?Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.forum_outlined,size:48,color:muted),
            const SizedBox(height:14),
            const Text('Escolha um canal ou uma mensagem privada',
              style:TextStyle(fontSize:16,fontWeight:FontWeight.w600)),
            const SizedBox(height:8),
            TextButton.icon(onPressed:startDm,icon:const Icon(Icons.add),
              label:const Text('Iniciar conversa'))
          ]))
        :ListView.builder(controller:messageScroll,
          padding:const EdgeInsets.fromLTRB(22,16,24,10),
          itemCount:visible.length+1,itemBuilder:(ctx,i){
            if(i==0) return Padding(padding:const EdgeInsets.only(bottom:24,top:18),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                CircleAvatar(radius:27,backgroundColor:highlight,
                  child:Icon(dmId!=null?Icons.person:Icons.tag,
                    color:Colors.white,size:29)),
                const SizedBox(height:14),
                Text(dmId!=null?'Conversa com $name':'Bem-vindo a #$name',
                  style:const TextStyle(fontSize:25,fontWeight:FontWeight.w800)),
                const SizedBox(height:6),
                Text(dmId!=null?'Início da conversa privada.'
                  :'Este é o começo do canal #$name.',
                  style:const TextStyle(color:muted,fontSize:13)),
                const SizedBox(height:18),const Divider(color:Colors.white12),
                if(query.isNotEmpty&&visible.isEmpty)
                  const Padding(padding:EdgeInsets.all(18),
                    child:Text('Nenhuma mensagem carregada corresponde ao filtro.',
                      style:TextStyle(color:muted)))
              ]));
            final m=visible[i-1];
            final username=m['username']?.toString()??'Usuário';
            return Padding(padding:const EdgeInsets.symmetric(vertical:6),
              child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                CircleAvatar(radius:19,backgroundColor:highlight,
                  child:Text(username.isEmpty?'?':username.substring(0,1).toUpperCase(),
                    style:const TextStyle(fontWeight:FontWeight.w700,fontSize:15))),
                const SizedBox(width:12),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(username,style:const TextStyle(fontWeight:FontWeight.w700,fontSize:14)),
                  const SizedBox(height:3),
                  SelectableText(m['content']?.toString()??'',
                    style:const TextStyle(height:1.45,fontSize:14,color:Color(0xFFE3E4EA)))
                ]))
              ]));
          })),
      if(error!=null)Padding(padding:const EdgeInsets.symmetric(horizontal:18,vertical:5),
        child:Text(error!,style:const TextStyle(color:Colors.orangeAccent,fontSize:12))),
      if(active) Padding(padding:const EdgeInsets.fromLTRB(15,6,15,14),
        child:Container(decoration:BoxDecoration(color:highlight,
          borderRadius:BorderRadius.circular(11)),
          padding:const EdgeInsets.symmetric(horizontal:10),
          child:Row(children:[
            const Icon(Icons.chat_bubble_outline,color:muted,size:21),
            const SizedBox(width:9),
            Expanded(child:TextField(controller:message,maxLines:5,minLines:1,
              textInputAction:TextInputAction.send,onSubmitted:(_)=>send(),
              style:const TextStyle(fontSize:14),
              decoration:InputDecoration(filled:false,border:InputBorder.none,
                hintText:dmId!=null?'Mensagem para $name':'Mensagem em #$name'))),
            ValueListenableBuilder<TextEditingValue>(valueListenable:message,
              builder:(_,value,__)=>IconButton(
                tooltip:'Enviar mensagem',
                onPressed:busy||sending||value.text.trim().isEmpty?null:send,
                icon:const Icon(Icons.send_rounded,color:accent)))
          ])))
    ]));
  }

  Widget auth() => Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),
    child:Padding(padding:const EdgeInsets.all(24),child:Column(
      mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        _brand(size:70),
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
        const SizedBox(height:12),
        OutlinedButton.icon(
          onPressed:busy?null:loginWithDiscord,
          icon:const Icon(Icons.open_in_browser_rounded),
          label:const Padding(padding:EdgeInsets.all(11),
            child:Text('Continuar com Discord'))),
        const Padding(padding:EdgeInsets.symmetric(vertical:10),
          child:Text('O Discord abrirá no navegador. A Veylor solicita apenas sua identidade.',
            textAlign:TextAlign.center,style:TextStyle(color:muted,fontSize:11))),
        TextButton(onPressed:()=>setState(()=>signup=!signup),
          child:Text(signup?'Já tenho conta':'Criar conta')),
        if(error!=null)Text(error!,textAlign:TextAlign.center,
          style:const TextStyle(color:Colors.orangeAccent)),
        const SizedBox(height:12),
        Text('$runningVersion • Mensagens, comunidades e tempo real',textAlign:TextAlign.center)
      ]))));
  @override
  Widget build(BuildContext context){
    if(restoring)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(api.token==null)return Scaffold(body:auth());
    final mobile=MediaQuery.sizeOf(context).width<730;
    return Scaffold(
      drawer:mobile?Drawer(width:315,child:rails()):null,
      body:Row(children:[
        if(!mobile)SizedBox(width:315,child:rails()),
        Expanded(child:chat()),
        if(!mobile&&MediaQuery.sizeOf(context).width>=1100&&showMembers)
          _memberPanel(),
      ]));
  }
}
).hasMatch(token)||
            profile is! Map||profile['username'] is! String){
          throw const FormatException('Sessão Discord recebida é inválida.');
        }
        cancelled=true;
        if(mounted){
          Navigator.of(context,rootNavigator:true).pop();
          progressVisible=false;
        }
        await modal;
        api.token=token;
        nick=profile['username'] as String;
        await storage.write(key:'veylor_session',value:token);
        await loadServers();
        await loadDms();
        startRealtime();
        if(mounted)setState((){});
        return;
      }
      if(!cancelled)throw StateError('Tempo para entrar com Discord esgotado. Tente novamente.');
      await modal;
    }catch(e){
      if(mounted)setState((){
        error=e is ApiException && e.statusCode==503
          ?'Login Discord ainda não configurado no servidor.'
          :'Não foi possível entrar com Discord: $e';
      });
    }finally{
      if(progressVisible&&mounted)Navigator.of(context,rootNavigator:true).pop();
      if(mounted)setState(()=>busy=false);
    }
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
        _scrollToLatest();
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
    if(busy || api.token==null)return;
    setState(() {busy=true;error=null;});
    try {
      final response=await api.request('POST','/api/media/token',{'channel_id':c['id']});
      final access=MediaAccess.fromJson(response);
      if(!mounted)return;
      // Keep media navigation separate from chat state; never keep the global
      // busy flag set while a voice call is open.
      setState(()=>busy=false);
      _closeMobileNavigation();
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder:(_)=>VeylorVoiceRoom(
          channelName:c['name']?.toString()??'Voz',
          access:access,
        )));
    }catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text(e.toString().contains('LiveKit ainda não configurado')
          ?'O servidor de voz ainda precisa ser configurado pelo administrador.'
          :'Não foi possível entrar no canal de voz: $e')));
    }finally {
      if(mounted)setState(()=>busy=false);
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !messageScroll.hasClients) return;
      messageScroll.animateTo(messageScroll.position.maxScrollExtent,
        duration:const Duration(milliseconds:220),curve:Curves.easeOutCubic);
    });
  }

  void _closeMobileNavigation() {
    if (MediaQuery.sizeOf(context).width < 730 && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _selectDm(Map<String,dynamic> conversation) async {
    await perform(() async {
      dmId=conversation['id'] as String;
      cursor=0;messages=[];searchController.clear();
      await refresh();
      if(mounted) setState(() {});
      _closeMobileNavigation();
      _scrollToLatest();
    });
  }

  Future<void> _selectChannel(Map<String,dynamic> channel) async {
    await perform(() async {
      dmId=null;channelId=channel['id'] as String;
      cursor=0;messages=[];searchController.clear();
      await refresh();
      if(mounted) setState(() {});
      _closeMobileNavigation();
      _scrollToLatest();
    });
  }

  Future<void> _toggleMemberPanel() async {
    if (serverId==null) return;
    if (MediaQuery.sizeOf(context).width < 1100) {
      await manageMembers();
      return;
    }
    setState(() => showMembers=!showMembers);
    if(!showMembers) return;
    final requestedServer=serverId!;
    try {
      final result=await api.request('GET','/api/servers/$requestedServer/members');
      if(mounted&&serverId==requestedServer) {
        setState(()=>memberPreview=List<Map<String,dynamic>>.from(result['members'] as List));
      }
    } catch(e) {
      if(mounted) setState(()=>error='Não foi possível carregar membros: $e');
    }
  }

  Widget _brand({double size=48})=>ClipRRect(
    borderRadius:BorderRadius.circular(size*.26),
    child:Image.asset('assets/veylor_logo.png',width:size,height:size,fit:BoxFit.cover,
      filterQuality:FilterQuality.medium));

  Widget _serverRail() => Container(width:72,color:sidebar,child:Column(children:[
    const SizedBox(height:12),
    Tooltip(message:'Veylor',child:_brand(size:48)),
    Padding(padding:const EdgeInsets.symmetric(horizontal:18,vertical:12),
      child:Container(height:1,color:Colors.white12)),
    Expanded(child:ListView(padding:EdgeInsets.zero,children:[
      for(final server in servers)
        Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
          child:Tooltip(message:server['name']?.toString()??'Servidor',
            child:Material(color:serverId==server['id']?accent:surface,
              borderRadius:BorderRadius.circular(serverId==server['id']?16:24),
              clipBehavior:Clip.antiAlias,
              child:InkWell(
                key:ValueKey('server-${server['id']}'),
                onTap:()=>perform(() async {
                  dmId=null;serverId=server['id'] as String;
                  memberPreview=[];showMembers=false;
                  await loadChannels();_closeMobileNavigation();
                }),
                child:SizedBox(height:48,child:Center(
                  child:Text((server['name']?.toString().isNotEmpty??false)
                     ?server['name'].toString().substring(0,1).toUpperCase():'?',
                    style:const TextStyle(fontSize:20,fontWeight:FontWeight.w700)))))))),
      Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
        child:Tooltip(message:'Criar servidor',child:IconButton.filledTonal(
          onPressed:createServer,icon:const Icon(Icons.add,size:25)))),
      Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:5),
        child:Tooltip(message:'Entrar com convite',child:IconButton.filledTonal(
          onPressed:joinInvite,icon:const Icon(Icons.login_rounded,size:22)))),
    ])),
  ]));

  Widget _sectionHeader(String title,VoidCallback? onAdd)=>Padding(
    padding:const EdgeInsets.fromLTRB(14,16,8,5),
    child:Row(children:[
      Expanded(child:Text(title,style:const TextStyle(color:muted,fontSize:11,
        fontWeight:FontWeight.w700,letterSpacing:.65))),
      if(onAdd!=null)IconButton(
        tooltip:'Adicionar $title',visualDensity:VisualDensity.compact,
        onPressed:onAdd,icon:const Icon(Icons.add,size:18,color:muted)),
    ]));

  Widget _navEntry({required String title,required IconData icon,
    required bool selected,required VoidCallback onTap,String? keyId})=>
    Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),
      child:Material(color:selected?highlight:Colors.transparent,
        borderRadius:BorderRadius.circular(7),
        child:InkWell(key:keyId==null?null:ValueKey(keyId),
          onTap:onTap,borderRadius:BorderRadius.circular(7),
          child:Padding(padding:const EdgeInsets.symmetric(horizontal:10,vertical:10),
            child:Row(children:[
              Icon(icon,size:19,color:selected?Colors.white:muted),
              const SizedBox(width:12),
              Expanded(child:Text(title,maxLines:1,overflow:TextOverflow.ellipsis,
                style:TextStyle(color:selected?Colors.white:muted,
                  fontWeight:selected?FontWeight.w600:FontWeight.w500,fontSize:14))),
            ])))));

  Widget _channelRail()=>Expanded(child:Container(color:surface,child:Column(children:[
    SizedBox(height:62,child:Padding(padding:const EdgeInsets.symmetric(horizontal:14),
      child:Row(children:[
        Expanded(child:Text(servers.where((s)=>s['id']==serverId)
          .map((s)=>s['name']?.toString()??'Veylor').firstOrNull??'Veylor',
          maxLines:1,overflow:TextOverflow.ellipsis,
          style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700))),
        IconButton(onPressed:serverId==null?null:invite,tooltip:'Criar convite',
          icon:const Icon(Icons.person_add_alt_1_outlined,size:21))
      ]))),
    const Divider(height:1,color:Color(0xFF17181D)),
    Expanded(child:ListView(children:[
      _sectionHeader('MENSAGENS PRIVADAS',startDm),
      for(final d in dms)
        _navEntry(title:d['username']?.toString()??'Conversa',
          icon:Icons.person_outline_rounded,selected:dmId==d['id'],
          keyId:'dm-${d['id']}',onTap:()=>_selectDm(d)),
      _sectionHeader('CANAIS DE TEXTO',canManage?()=>createChannel('text'):null),
      for(final c in channels.where((c)=>c['type']=='text'))
        _navEntry(title:c['name']?.toString()??'canal',
          icon:Icons.tag_rounded,selected:dmId==null&&channelId==c['id'],
          keyId:'channel-${c['id']}',onTap:()=>_selectChannel(c)),
      _sectionHeader('CANAIS DE VOZ',canManage?()=>createChannel('voice'):null),
      for(final c in channels.where((c)=>c['type']=='voice'))
        _navEntry(title:c['name']?.toString()??'voz',
          icon:Icons.volume_up_outlined,selected:false,
          keyId:'voice-${c['id']}',onTap:()=>voice(c)),
      const SizedBox(height:20),
    ])),
    const Divider(height:1,color:Color(0xFF17181D)),
    _navEntry(title:'Membros do servidor',icon:Icons.group_outlined,
      selected:showMembers,onTap:_toggleMemberPanel),
    if(Platform.isAndroid||Platform.isWindows)
      _navEntry(title:'Verificar atualização',icon:Icons.system_update_alt_rounded,
        selected:false,onTap:()=>checkForUpdates()),
    if(Platform.isWindows)
      _navEntry(title:'Logs de atualização',icon:Icons.folder_open_outlined,
        selected:false,onTap:() async {
          try {
            final folder=UpdateDiagnostics.logDirectory;
            await folder.create(recursive:true);
            await Process.start('explorer.exe',[folder.path],
                mode:ProcessStartMode.detached);
          } catch (_) {
            if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:Text('Não foi possível abrir a pasta de logs.')));
          }
        }),
    Container(color:sidebar,padding:const EdgeInsets.symmetric(horizontal:6,vertical:6),
      child:Row(children:[
        CircleAvatar(radius:18,backgroundColor:accent,
          child:Text((nick??'V').substring(0,1).toUpperCase(),
            style:const TextStyle(fontWeight:FontWeight.w700,color:Colors.black))),
        const SizedBox(width:9),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(nick??'Conta',maxLines:1,overflow:TextOverflow.ellipsis,
            style:const TextStyle(fontWeight:FontWeight.w700,fontSize:13)),
          Text('$runningVersion • ${realtime?'Online':'Reconectando'}',
            style:TextStyle(fontSize:10,color:realtime?const Color(0xFF55D6A0):muted))
        ])),
        IconButton(tooltip:'Sair da conta',icon:const Icon(Icons.logout,size:19),
          onPressed:() async {
            stopRealtime();
            try{await api.request('POST','/api/logout');}catch(_){}
            api.token=null;pendingMessage=null;
            try{await storage.delete(key:'veylor_session');}catch(_){}
            if(mounted)setState((){
              nick=null;serverId=null;dmId=null;realtime=false;
              servers=[];channels=[];dms=[];messages=[];memberPreview=[];
            });
          })
      ])),
  ])));

  Widget rails()=>Row(children:[_serverRail(),_channelRail()]);

  Widget _memberPanel()=>Container(width:238,color:surface,child:Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Padding(padding:EdgeInsets.fromLTRB(20,24,16,12),
        child:Text('MEMBROS',style:TextStyle(color:muted,fontSize:12,
          fontWeight:FontWeight.w700,letterSpacing:1))),
      Expanded(child:ListView(children:[
        for(final person in memberPreview)
          ListTile(dense:true,leading:CircleAvatar(radius:15,
              backgroundColor:highlight,child:Text(
              (person['username']?.toString().isNotEmpty??false)
                ?person['username'].toString().substring(0,1).toUpperCase():'?')),
            title:Text(person['username']?.toString()??'Membro',
              maxLines:1,overflow:TextOverflow.ellipsis,
              style:const TextStyle(fontSize:13)),
            subtitle:Text(person['role']?.toString()??'membro',
              style:const TextStyle(fontSize:11,color:muted)))
      ])),
      TextButton.icon(onPressed:manageMembers,icon:const Icon(Icons.settings_outlined,size:17),
        label:const Text('Gerenciar membros'))
    ]));

  Widget chat() {
    final name=dmId!=null
      ?(dms.where((d)=>d['id']==dmId).map((d)=>d['username']?.toString()??'DM').firstOrNull??'DM')
      :(channels.where((c)=>c['id']==channelId).map((c)=>c['name']?.toString()??'geral').firstOrNull??'geral');
    final active=dmId!=null||channelId!=null;
    final query=searchController.text.trim().toLowerCase();
    final visible=query.isEmpty?messages:messages.where((m)=>
      (m['content']?.toString().toLowerCase().contains(query)??false)||
      (m['username']?.toString().toLowerCase().contains(query)??false)).toList();
    return Container(color:background,child:Column(children:[
      Container(height:62,padding:const EdgeInsets.symmetric(horizontal:12),
        child:Row(children:[
          if(MediaQuery.sizeOf(context).width<730)
            Builder(builder:(ctx)=>IconButton(onPressed:()=>Scaffold.of(ctx).openDrawer(),
              tooltip:'Abrir servidores e canais',icon:const Icon(Icons.menu))),
          Icon(dmId!=null?Icons.alternate_email:Icons.tag_rounded,
            color:muted,size:23),
          const SizedBox(width:10),
          Expanded(child:Text(name,maxLines:1,overflow:TextOverflow.ellipsis,
            style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700))),
          Tooltip(message:realtime?'Conectado em tempo real':'Reconectando',
            child:Icon(realtime?Icons.wifi:Icons.wifi_off,size:16,
              color:realtime?const Color(0xFF55D6A0):Colors.orangeAccent)),
          IconButton(tooltip:'Filtrar mensagens carregadas',
            onPressed:()=>setState((){
              searching=!searching;
              if(!searching)searchController.clear();
            }),icon:Icon(searching?Icons.search_off:Icons.search)),
          IconButton(tooltip:'Membros',onPressed:_toggleMemberPanel,
            icon:const Icon(Icons.people_alt_outlined)),
          IconButton(tooltip:'Atualizar mensagens',onPressed:refresh,
            icon:const Icon(Icons.refresh_rounded))
        ])),
      const Divider(height:1,color:Color(0xFF212226)),
      if(searching)Padding(padding:const EdgeInsets.fromLTRB(14,8,14,6),
        child:TextField(controller:searchController,autofocus:true,
          onChanged:(_)=>setState((){}),
          decoration:InputDecoration(isDense:true,prefixIcon:const Icon(Icons.search),
            hintText:'Filtrar mensagens já carregadas',
            suffixIcon:IconButton(onPressed:()=>setState(()=>searchController.clear()),
              icon:const Icon(Icons.close)),filled:true,fillColor:surface))),
      Expanded(child:!active
        ?Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.forum_outlined,size:48,color:muted),
            const SizedBox(height:14),
            const Text('Escolha um canal ou uma mensagem privada',
              style:TextStyle(fontSize:16,fontWeight:FontWeight.w600)),
            const SizedBox(height:8),
            TextButton.icon(onPressed:startDm,icon:const Icon(Icons.add),
              label:const Text('Iniciar conversa'))
          ]))
        :ListView.builder(controller:messageScroll,
          padding:const EdgeInsets.fromLTRB(22,16,24,10),
          itemCount:visible.length+1,itemBuilder:(ctx,i){
            if(i==0) return Padding(padding:const EdgeInsets.only(bottom:24,top:18),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                CircleAvatar(radius:27,backgroundColor:highlight,
                  child:Icon(dmId!=null?Icons.person:Icons.tag,
                    color:Colors.white,size:29)),
                const SizedBox(height:14),
                Text(dmId!=null?'Conversa com $name':'Bem-vindo a #$name',
                  style:const TextStyle(fontSize:25,fontWeight:FontWeight.w800)),
                const SizedBox(height:6),
                Text(dmId!=null?'Início da conversa privada.'
                  :'Este é o começo do canal #$name.',
                  style:const TextStyle(color:muted,fontSize:13)),
                const SizedBox(height:18),const Divider(color:Colors.white12),
                if(query.isNotEmpty&&visible.isEmpty)
                  const Padding(padding:EdgeInsets.all(18),
                    child:Text('Nenhuma mensagem carregada corresponde ao filtro.',
                      style:TextStyle(color:muted)))
              ]));
            final m=visible[i-1];
            final username=m['username']?.toString()??'Usuário';
            return Padding(padding:const EdgeInsets.symmetric(vertical:6),
              child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
                CircleAvatar(radius:19,backgroundColor:highlight,
                  child:Text(username.isEmpty?'?':username.substring(0,1).toUpperCase(),
                    style:const TextStyle(fontWeight:FontWeight.w700,fontSize:15))),
                const SizedBox(width:12),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(username,style:const TextStyle(fontWeight:FontWeight.w700,fontSize:14)),
                  const SizedBox(height:3),
                  SelectableText(m['content']?.toString()??'',
                    style:const TextStyle(height:1.45,fontSize:14,color:Color(0xFFE3E4EA)))
                ]))
              ]));
          })),
      if(error!=null)Padding(padding:const EdgeInsets.symmetric(horizontal:18,vertical:5),
        child:Text(error!,style:const TextStyle(color:Colors.orangeAccent,fontSize:12))),
      if(active) Padding(padding:const EdgeInsets.fromLTRB(15,6,15,14),
        child:Container(decoration:BoxDecoration(color:highlight,
          borderRadius:BorderRadius.circular(11)),
          padding:const EdgeInsets.symmetric(horizontal:10),
          child:Row(children:[
            const Icon(Icons.chat_bubble_outline,color:muted,size:21),
            const SizedBox(width:9),
            Expanded(child:TextField(controller:message,maxLines:5,minLines:1,
              textInputAction:TextInputAction.send,onSubmitted:(_)=>send(),
              style:const TextStyle(fontSize:14),
              decoration:InputDecoration(filled:false,border:InputBorder.none,
                hintText:dmId!=null?'Mensagem para $name':'Mensagem em #$name'))),
            ValueListenableBuilder<TextEditingValue>(valueListenable:message,
              builder:(_,value,__)=>IconButton(
                tooltip:'Enviar mensagem',
                onPressed:busy||sending||value.text.trim().isEmpty?null:send,
                icon:const Icon(Icons.send_rounded,color:accent)))
          ])))
    ]));
  }

  Widget auth() => Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),
    child:Padding(padding:const EdgeInsets.all(24),child:Column(
      mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        _brand(size:70),
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
        Text('$runningVersion • Mensagens, comunidades e tempo real',textAlign:TextAlign.center)
      ]))));
  @override
  Widget build(BuildContext context){
    if(restoring)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    if(api.token==null)return Scaffold(body:auth());
    final mobile=MediaQuery.sizeOf(context).width<730;
    return Scaffold(
      drawer:mobile?Drawer(width:315,child:rails()):null,
      body:Row(children:[
        if(!mobile)SizedBox(width:315,child:rails()),
        Expanded(child:chat()),
        if(!mobile&&MediaQuery.sizeOf(context).width>=1100&&showMembers)
          _memberPanel(),
      ]));
  }
}
