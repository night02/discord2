import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/discord_login.dart';

void main() {
  final state='a' * 64;
  final id='b' * 64;
  final secret='c' * 64;
  Map<String,dynamic> auth() => {
    'url':'https://discord.com/oauth2/authorize?scope=identify&response_type=code&state=$state&client_id=123456789012345678',
    'request_id':id,
    'poll_secret':secret
  };
  test('accepts Discord authorization only with app-held poll secret',(){
    final request=DiscordLoginRequest.fromJson(auth());
    expect(request.url.host,'discord.com');
    expect(request.url.queryParameters['scope'],'identify');
    expect(request.requestId,id);
    expect(request.pollSecret,secret);
    expect(request.url.toString().contains(secret),false);
  });
  test('refuses forged OAuth URLs and invalid handoff secrets',(){
    for(final bad in <String>[
      'https://evil.test/oauth2/authorize?scope=identify&response_type=code&state=$state',
      'https://discord.com.evil.test/oauth2/authorize?scope=identify&response_type=code&state=$state',
      'http://discord.com/oauth2/authorize?scope=identify&response_type=code&state=$state',
      'https://discord.com/channels/@me?scope=identify&response_type=code&state=$state',
      'https://discord.com/oauth2/authorize?scope=identify%20guilds&response_type=code&state=$state',
      'https://discord.com/oauth2/authorize?scope=identify&response_type=token&state=$state',
    ]) {
      expect(()=>DiscordLoginRequest.fromJson({...auth(),'url':bad}),
        throwsFormatException,reason:bad);
    }
    expect(()=>DiscordLoginRequest.fromJson({...auth(),'poll_secret':'weak'}),throwsFormatException);
    expect(()=>DiscordLoginRequest.fromJson({...auth(),'request_id':'bad'}),throwsFormatException);
  });
}
