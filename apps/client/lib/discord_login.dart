/// Parses only a Discord-hosted OAuth URL created by the Veylor backend.
/// Login poll secret is kept in memory until claimed, never passed to the browser.
class DiscordLoginRequest {
  const DiscordLoginRequest({required this.url,required this.requestId,required this.pollSecret});
  final Uri url;
  final String requestId;
  final String pollSecret;

  static DiscordLoginRequest fromJson(Map<String,dynamic> body) {
    final raw=body['url'];
    final id=body['request_id'],proof=body['poll_secret'];
    final link=raw is String?Uri.tryParse(raw):null;
    if(link==null||link.scheme!='https'||link.host!='discord.com'||
        link.path!='/oauth2/authorize'||link.hasFragment||
        link.userInfo.isNotEmpty||link.hasPort||
        link.queryParameters['scope']!='identify'||
        link.queryParameters['response_type']!='code'||
        link.queryParameters['state']?.length!=64||
        id is! String||proof is! String||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(id)||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(proof)){
      throw const FormatException('Endereço OAuth Discord não confiável.');
    }
    return DiscordLoginRequest(url:link,requestId:id,pollSecret:proof);
  }
}
