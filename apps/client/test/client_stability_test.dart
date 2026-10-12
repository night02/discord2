import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/client_stability.dart';

void main(){
  test('backoff grows and caps at 30 seconds, resets after connection',(){
    final backoff=RetryBackoff();
    expect([for(var i=0;i<7;i++)backoff.nextDelay().inSeconds],[2,4,8,16,30,30,30]);
    expect(backoff.failures,7);
    backoff.reset();
    expect(backoff.nextDelay().inSeconds,2);
  });
  test('messages from polling and WebSocket merge by id in chronological order',(){
    final first=[
      <String,dynamic>{'id':2,'content':'B'},
      <String,dynamic>{'id':1,'content':'A'},
    ];
    final next=[
      <String,dynamic>{'id':2,'content':'B'},
      <String,dynamic>{'id':4,'content':'D'},
      <String,dynamic>{'id':3,'content':'C'},
    ];
    final merged=mergeMessagePages(first,next);
    expect(merged.map((m)=>m['id']),[1,2,3,4]);
    expect(mergeMessagePages(merged,next).length,4);
    expect(merged.map((m)=>m['content']),['A','B','C','D']);
  });
  test('pending message can be retried with same nonce only in same route and text',(){
    final nonce=createClientNonce();
    expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(nonce),isTrue);
    final pending=PendingMessage(route:'/api/dms/my-thread/messages',content:'hello',nonce:nonce);
    expect(pending.matches('/api/dms/my-thread/messages','hello'),isTrue);
    expect(pending.matches('/api/dms/another-thread/messages','hello'),isFalse);
    expect(pending.matches('/api/dms/my-thread/messages','modified'),isFalse);
    expect(createClientNonce(),isNot(nonce));
  });
}
