import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../client_stability.dart';
import 'models.dart';
enum RealtimeStatus {
  offline('Sem conexão'),connecting('Conectando'),reconnecting('Reconectando'),connected('Conectado');
  const RealtimeStatus(this.label);
  final String label;
}
abstract class RealtimeClient {
  void start({required String address,required String token,required void Function(Json) onEvent,required void Function(RealtimeStatus) onStatus});
  void stop();
}
class SocketRealtimeClient implements RealtimeClient {
  WebSocket? _socket;
  Timer? _retry;
  final _backoff=RetryBackoff();
  int _epoch=0;
  @override void start({required String address,required String token,required void Function(Json) onEvent,required void Function(RealtimeStatus) onStatus}) {
    stop();
    final epoch=_epoch;
    final url=Uri.parse(address).replace(scheme:address.startsWith('https:')?'wss':'ws',path:'/api/realtime',query:null,fragment:null);
    Future<void> connect() async {
      if(epoch!=_epoch)return;
      onStatus(_backoff.failures==0?RealtimeStatus.connecting:RealtimeStatus.reconnecting);
      try {
        final socket=await WebSocket.connect(url.toString(),headers:{HttpHeaders.authorizationHeader:'Bearer $token'}).timeout(const Duration(seconds:12));
        if(epoch!=_epoch){await socket.close();return;}
        _socket=socket; socket.pingInterval=const Duration(seconds:20);_backoff.reset();
        onStatus(RealtimeStatus.connected);
        socket.listen((data){
          if(epoch!=_epoch || data is! String)return;
          try{onEvent(asJson(jsonDecode(data)));}on FormatException{}
        },onError:(Object _){unawaited(socket.close());},onDone:(){
          if(epoch!=_epoch || !identical(_socket,socket))return;
          _socket=null;onStatus(RealtimeStatus.reconnecting);
          _retry=Timer(_backoff.nextDelay(),()=>unawaited(connect()));
        });
      }catch(_){
        if(epoch!=_epoch)return;
        onStatus(RealtimeStatus.reconnecting);
        _retry=Timer(_backoff.nextDelay(),()=>unawaited(connect()));
      }
    }
    unawaited(connect());
  }
  @override void stop(){
    _epoch++;_retry?.cancel();_retry=null;
    final socket=_socket;_socket=null;
    if(socket!=null)unawaited(socket.close());
    _backoff.reset();
  }
}
