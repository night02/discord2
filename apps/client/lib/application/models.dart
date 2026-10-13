typedef Json = Map<String,dynamic>;
Json asJson(Object? value) {
  if(value is Map) return Map<String,dynamic>.from(value);
  throw const FormatException('Resposta incompleta do servidor.');
}
List<Json> jsonRows(Json data,String key) {
  final rows=data[key];
  if(rows is! List) throw const FormatException('Lista incompleta do servidor.');
  return rows.map(asJson).toList(growable:false);
}
String requiredString(Json data,String key) {
  final value=data[key];
  if(value is! String || value.isEmpty) throw const FormatException('Resposta incompleta do servidor.');
  return value;
}
class Account {
  const Account({required this.id,required this.username});
  factory Account.fromJson(Json data)=>Account(id:requiredString(data,'id'),username:requiredString(data,'username'));
  final String id,username;
}
enum MemberRole {
  owner('Proprietário'),moderator('Moderador'),member('Membro');
  const MemberRole(this.label);
  final String label;
  static MemberRole parse(Object? value)=>switch(value){'owner'=>owner,'moderator'=>moderator,_=>member};
}
class Community {
  const Community({required this.id,required this.name,required this.role});
  factory Community.fromJson(Json data)=>Community(id:requiredString(data,'id'),name:requiredString(data,'name'),role:MemberRole.parse(data['role']));
  final String id,name;
  final MemberRole role;
  bool get canManage=>role!=MemberRole.member;
}
enum ChannelKind {text,voice}
class CommunityChannel {
  const CommunityChannel({required this.id,required this.name,required this.kind});
  factory CommunityChannel.fromJson(Json data)=>CommunityChannel(id:requiredString(data,'id'),name:requiredString(data,'name'),kind:data['type']=='voice'?ChannelKind.voice:ChannelKind.text);
  final String id,name;
  final ChannelKind kind;
}
class DirectThread {
  const DirectThread({required this.id,required this.username});
  factory DirectThread.fromJson(Json data)=>DirectThread(id:requiredString(data,'id'),username:requiredString(data,'username'));
  final String id,username;
}
class CommunityMember {
  const CommunityMember({required this.id,required this.username,required this.role});
  factory CommunityMember.fromJson(Json data)=>CommunityMember(id:requiredString(data,'id'),username:requiredString(data,'username'),role:MemberRole.parse(data['role']));
  final String id,username;
  final MemberRole role;
}
class Conversation {
  const Conversation.channel(this.id):isDirect=false;
  const Conversation.direct(this.id):isDirect=true;
  final String id;
  final bool isDirect;
  String get route=>'/api/'+(isDirect?'dms':'channels')+'/'+Uri.encodeComponent(id)+'/messages';
  @override bool operator==(Object other)=>other is Conversation && other.id==id && other.isDirect==isDirect;
  @override int get hashCode=>Object.hash(id,isDirect);
}
class ChatMessage {
  const ChatMessage({required this.id,required this.username,required this.content,this.createdAt});
  factory ChatMessage.fromJson(Json data) {
    final raw=data['id'],id=raw is int?raw:int.tryParse('$raw');
    if(id==null || id<0) throw const FormatException('Identificador de mensagem inválido.');
    return ChatMessage(id:id,username:requiredString(data,'username'),content:data['content'] is String?data['content'] as String:'',createdAt:DateTime.tryParse(data['created_at']?.toString()??''));
  }
  final int id;
  final String username,content;
  final DateTime? createdAt;
}
List<ChatMessage> mergeMessages(Iterable<ChatMessage> existing,Iterable<ChatMessage> arriving) {
  final rows={for(final row in existing) row.id:row};
  for(final row in arriving){rows[row.id]=row;}
  final ids=rows.keys.toList()..sort();
  return List.unmodifiable(ids.map((id)=>rows[id]!));
}
class IntegrationAvailability {
  const IntegrationAvailability({this.voice=false,this.discord=false});
  factory IntegrationAvailability.fromJson(Json data)=>IntegrationAvailability(voice:data['livekit'] is Map && (data['livekit'] as Map)['configured']==true,discord:data['discord'] is Map && (data['discord'] as Map)['configured']==true);
  final bool voice,discord;
}
