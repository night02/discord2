class MediaAccess {
  const MediaAccess({required this.url,required this.token});
  final String url,token;
  static MediaAccess fromJson(Map<String,dynamic> data){
    final url=data['url'],token=data['token'];
    if(url is! String || token is! String || token.length<48 || token.length>8192)throw const FormatException('Credenciais de voz incompletas.');
    final uri=Uri.tryParse(url);
    if(uri==null || uri.scheme!='wss' || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasFragment || uri.hasQuery || uri.hasPort || uri.path!='' && uri.path!='/')throw const FormatException('Servidor de voz precisa de WSS válido.');
    return MediaAccess(url:uri.toString(),token:token);
  }
}
