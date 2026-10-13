import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/api_client.dart';
import 'package:veylor/application/models.dart';
import 'package:veylor/application/veylor_controller.dart';
import 'support/workspace_fixture.dart';
void main(){
  test('restoration outage preserves saved session',() async {
    final f=WorkspaceFixture();addTearDown(f.dispose);f.sessions.token='a'*64;
    f.api.handler=(_,__,___) async=>throw const ApiException(503,'Offline');
    await f.app.bootstrap();expect(f.app.phase,AppPhase.unavailable);expect(f.sessions.token,'a'*64);expect(f.sessions.clears,0);
  });
  test('late restoration cannot resurrect a logged-out account',() async {
    final f=WorkspaceFixture();addTearDown(f.dispose);f.sessions.token='a'*64;
    final response=Completer<Json>(),reached=Completer<void>();
    f.api.handler=(_,route,__) async{if(route=='/api/me'){reached.complete();return response.future;}return {};};
    final restore=f.app.bootstrap();await reached.future;await f.app.logout();response.complete(f.api.auth);await restore;
    expect(f.app.phase,AppPhase.signedOut);expect(f.app.account,isNull);expect(f.sessions.token,isNull);expect(f.realtime.active,isFalse);
  });
  test('late server channels cannot replace current navigation',() async {
    final f=WorkspaceFixture();addTearDown(f.dispose);await f.login();final slow=Completer<Json>();
    f.api.handler=(method,route,body) async{if(route=='/api/servers/community-a/channels')return slow.future;return f.api.response(method,route,body);};
    final first=f.app.selectCommunity(f.app.communities[0]);await f.app.selectCommunity(f.app.communities[1]);
    slow.complete({'channels':f.api.channelSets['community-a']});await first;
    expect(f.app.selectedCommunityId,'community-b');expect(f.app.channels.single.id,'channel-c');expect(f.app.conversation,const Conversation.channel('channel-c'));
  });
  test('late messages update only their own conversation',() async {
    final f=WorkspaceFixture();addTearDown(f.dispose);await f.openCommunity();final slow=Completer<Json>();
    f.api.pages['/api/channels/channel-b/messages']=[FixtureApi.message(2,'canal B')];
    f.api.handler=(method,route,body) async{if(route.startsWith('/api/channels/channel-a/messages'))return slow.future;return f.api.response(method,route,body);};
    final first=f.app.refreshMessages();await f.app.selectChannel(f.app.channels[1]);
    slow.complete({'messages':[FixtureApi.message(1,'canal A')]});await first;expect(f.app.messages.single.content,'canal B');
    f.api.handler=null;await f.app.selectChannel(f.app.channels[0]);expect(f.app.messages.single.content,'canal A');
  });
  test('DM and channel with matching ids have independent messages and drafts',() async {
    final f=WorkspaceFixture();addTearDown(f.dispose);await f.openCommunity();
    f.api.pages['/api/channels/channel-a/messages']=[FixtureApi.message(1,'público')];
    f.api.pages['/api/dms/channel-a/messages']=[FixtureApi.message(1,'privado')];
    await f.app.refreshMessages();f.app.saveDraft(f.app.conversation,'rascunho público');
    await f.app.selectThread(const DirectThread(id:'channel-a',username:'Bruno'));f.app.saveDraft(f.app.conversation,'rascunho privado');
    expect(f.app.messages.single.content,'privado');expect(f.app.draft(const Conversation.channel('channel-a')),'rascunho público');
    expect(f.app.draft(const Conversation.direct('channel-a')),'rascunho privado');
    await f.app.selectCommunity(f.app.communities.first);expect(f.app.messages.single.content,'público');
  });
  test('ambiguous sends preserve nonce; other conversations have another nonce',() async {
    final f=WorkspaceFixture();addTearDown(f.dispose);await f.openCommunity();var fail=true;
    f.api.handler=(method,route,body) async{
      if(method=='POST' && route.endsWith('/messages') && fail){fail=false;throw const ApiException(0,'Timeout');}
      return f.api.response(method,route,body);
    };
    expect(await f.app.send('olá'),isFalse);await f.app.selectChannel(f.app.channels[1]);expect(await f.app.send('olá'),isTrue);
    await f.app.selectChannel(f.app.channels[0]);expect(await f.app.send('olá'),isTrue);
    final sends=f.api.calls.where((row)=>row.method=='POST' && row.route.endsWith('/messages')).toList();
    expect(sends[0].body!['client_nonce'],sends[2].body!['client_nonce']);expect(sends[0].body!['client_nonce'],isNot(sends[1].body!['client_nonce']));expect(f.app.messages.length,1);
  });
  test('catch-up consumes all pages without duplicates',() async {
    final f=WorkspaceFixture();addTearDown(f.dispose);
    f.api.pages['/api/channels/channel-a/messages']=List.generate(235,(i)=>FixtureApi.message(i+1,'Mensagem $i'));
    await f.openCommunity();expect(f.app.messages.length,235);expect(f.app.messages.last.id,235);
    await f.app.refreshMessages();expect(f.app.messages.length,235);
  });
  test('unread entry and account change clear private state',() async {
    final f=WorkspaceFixture();addTearDown(f.dispose);await f.openCommunity();f.app.saveDraft(f.app.conversation,'rascunho confidencial');
    f.realtime.emit({'type':'dm.message','thread_id':'thread-a'});expect(f.app.hasUnread(const Conversation.direct('thread-a')),isTrue);
    await f.app.selectThread(f.app.threads.first);expect(f.app.hasUnread(const Conversation.direct('thread-a')),isFalse);
    await f.app.logout();await f.app.acceptSession({'token':'b'*64,'user':{'id':'account-b','username':'Bruno'}});
    expect(f.app.messages,isEmpty);expect(f.app.conversation,isNull);expect(f.app.draft(const Conversation.channel('channel-a')),'');
  });
}
