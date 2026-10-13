import 'package:veylor/api_client.dart';
import 'package:veylor/application/models.dart';
import 'package:veylor/application/realtime_client.dart';
import 'package:veylor/application/session_store.dart';
import 'package:veylor/application/veylor_controller.dart';
class MemorySessions implements SessionStore {
  String? address='http://127.0.0.1:9',token;int clears=0;
  @override Future<String?> readAddress() async=>address;
  @override Future<String?> readToken() async=>token;
  @override Future<void> save(String address,String token) async{this.address=address;this.token=token;}
  @override Future<void> clear() async{clears++;token=null;}
  @override Future<void> saveAddress(String address) async{this.address=address;}
}
class MemoryRealtime implements RealtimeClient {
  void Function(Json)? onEvent;void Function(RealtimeStatus)? onStatus;bool active=false;
  @override void start({required String address,required String token,required void Function(Json) onEvent,required void Function(RealtimeStatus) onStatus}){
    this.onEvent=onEvent;this.onStatus=onStatus;active=true;onStatus(RealtimeStatus.connected);
  }
  void emit(Json event)=>onEvent?.call(event);
  @override void stop(){active=false;onEvent=null;onStatus=null;}
}
class FixtureApi extends Api {
  FixtureApi():super('http://127.0.0.1:9');
  Future<Json> Function(String,String,Json?)? handler;
  final calls=<({String method,String route,Json? body})>[];
  final pages=<String,List<Json>>{};
  List<Json> communities=[
    {'id':'community-a','name':'Astronyx Lounge','role':'owner'},
    {'id':'community-b','name':'Comunidade de jogos','role':'member'}];
  List<Json> threads=[{'id':'thread-a','username':'Bruno'}];
  final channelSets=<String,List<Json>>{
    'community-a':[{'id':'channel-a','name':'geral','type':'text'},{'id':'channel-b','name':'jogos','type':'text'},{'id':'voice-a','name':'Sala da galera','type':'voice'}],
    'community-b':[{'id':'channel-c','name':'outro-servidor','type':'text'}]};
  Json get auth=>{'token':'a'*64,'user':{'id':'account-a','username':'Vinicius'}};
  @override Future<Json> request(String method,String route,[Json? body]) async {
    calls.add((method:method,route:route,body:body==null?null:Map.of(body)));
    if(handler!=null)return handler!(method,route,body);
    return response(method,route,body);
  }
  Json response(String method,String route,Json? body){
    final path=Uri.parse(route).path;
    if(path=='/api/me' || path=='/api/login' || path=='/api/register')return auth;
    if(path=='/api/servers')return {'servers':communities};
    if(path=='/api/dms')return {'threads':threads};
    if(path=='/api/integrations/status')return {'discord':{'configured':false},'livekit':{'configured':false}};
    if(path=='/api/media/token')return {'url':'wss://fixture.example.com','token':'x'*128};
    if(path.endsWith('/channels'))return {'channels':channelSets[path.split('/')[3]]??[]};
    if(path.endsWith('/members'))return {'members':[{'id':'account-a','username':'Vinicius','role':'owner'},{'id':'account-b','username':'Bruno','role':'member'}]};
    if(path.endsWith('/messages')){
      if(method=='POST')return {'message':message(901,body!['content'] as String)};
      final after=int.tryParse(Uri.parse(route).queryParameters['after']??'0')??0;
      return {'messages':(pages[path]??[]).where((row)=>(row['id'] as int)>after).take(100).toList()};
    }return {};
  }
  static Json message(int id,String content,{String username='Bruno'})=>{'id':id,'content':content,'username':username,'created_at':'2026-10-13T14:00:00Z'};
}
class WorkspaceFixture {
  WorkspaceFixture(){app=VeylorController(api:api,sessions:sessions,realtime:realtime,pollInterval:const Duration(days:1));}
  final api=FixtureApi(),sessions=MemorySessions(),realtime=MemoryRealtime();
  late final VeylorController app;
  Future<void> login()=>app.acceptSession(api.auth);
  Future<void> openCommunity() async{await login();await app.selectCommunity(app.communities.first);}
  void dispose()=>app.dispose();
}
