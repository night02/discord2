import 'package:flutter/material.dart';
import '../application/models.dart';
import '../application/realtime_client.dart';
import '../application/veylor_controller.dart';
import '../media/voice_session.dart';
import 'veylor_theme.dart';
enum CommunityAction{invite,members,textChannel,voiceChannel}
class WorkspaceNavigation extends StatelessWidget {
  const WorkspaceNavigation({super.key,required this.app,required this.version,required this.onCommunity,required this.onChannel,
    required this.onThread,required this.onVoice,required this.onHome,required this.onCreate,required this.onJoin,
    required this.onNewDm,required this.onSettings,required this.onCommunityAction,required this.onDeleteChannel,
    required this.onShowCall,required this.onLeaveCall,this.call,this.showingCall=false});
  final VeylorController app;final String version;final VoiceSession? call;final bool showingCall;
  final void Function(Community) onCommunity;
  final void Function(CommunityChannel) onChannel,onVoice,onDeleteChannel;
  final void Function(DirectThread) onThread;
  final void Function(CommunityAction) onCommunityAction;
  final VoidCallback onHome,onCreate,onJoin,onNewDm,onSettings,onShowCall,onLeaveCall;
  @override Widget build(BuildContext context)=>Row(children:[
    Container(width:68,color:VeylorColors.rail,child:Column(children:[
      const SizedBox(height:10),_railButton('Mensagens',const BrandMark(size:46),app.isHome,onHome,const ValueKey('navigation-home')),
      const Padding(padding:EdgeInsets.fromLTRB(17,12,17,6),child:Divider(height:1)),
      Expanded(child:ListView(padding:const EdgeInsets.symmetric(vertical:6),children:[
        for(final server in app.communities)_railButton(server.name,Text(server.name.characters.take(2).toString().toUpperCase(),style:const TextStyle(fontSize:16,fontWeight:FontWeight.w800)),
          app.selectedCommunityId==server.id,()=>onCommunity(server),ValueKey('server-'+server.id)),
        _railButton('Criar servidor',const Icon(Icons.add,color:VeylorColors.success),false,onCreate,const ValueKey('create-community')),
        _railButton('Entrar com convite',const Icon(Icons.login_rounded,color:VeylorColors.success),false,onJoin,const ValueKey('join-community'))
      ]))
    ])),
    Expanded(child:ColoredBox(color:VeylorColors.navigation,child:Column(children:[
      Container(height:52,padding:const EdgeInsets.only(left:16,right:6),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:VeylorColors.divider))),
        child:Row(children:[
          Expanded(child:Text(app.selectedCommunity?.name??'Mensagens',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w800))),
          if(!app.isHome)PopupMenuButton<CommunityAction>(tooltip:'Opções do servidor',onSelected:onCommunityAction,icon:const Icon(Icons.keyboard_arrow_down,size:20),itemBuilder:(_)=>[
            if(app.selectedCommunity?.role==MemberRole.owner)const PopupMenuItem(value:CommunityAction.invite,child:Text('Convidar pessoas')),
            const PopupMenuItem(value:CommunityAction.members,child:Text('Membros e cargos')),
            if(app.selectedCommunity?.canManage??false)...[
              const PopupMenuItem(value:CommunityAction.textChannel,child:Text('Criar canal de texto')),
              const PopupMenuItem(value:CommunityAction.voiceChannel,child:Text('Criar canal de voz'))]
          ])
        ])),
      Expanded(child:ListView(padding:const EdgeInsets.symmetric(vertical:10),children:[
        if(app.isHome)...[
          _entry('Conversas',Icons.forum_outlined,app.conversation==null && !showingCall,onHome,key:const ValueKey('home-conversations')),
          _section('MENSAGENS PRIVADAS',onNewDm),
          for(final thread in app.threads)_entry(thread.username,Icons.person_outline,app.conversation==Conversation.direct(thread.id) && !showingCall,
            ()=>onThread(thread),key:ValueKey('dm-'+thread.id),unread:app.hasUnread(Conversation.direct(thread.id))),
          if(app.threads.isEmpty)const Padding(padding:EdgeInsets.fromLTRB(18,14,18,20),child:Text('Comece uma conversa pelo botão +.',style:TextStyle(fontSize:12,color:VeylorColors.muted,height:1.5)))
        ]else...[
          _section('CANAIS DE TEXTO',app.selectedCommunity!.canManage?()=>onCommunityAction(CommunityAction.textChannel):null),
          for(final channel in app.channels.where((row)=>row.kind==ChannelKind.text))_channelEntry(channel),
          _section('CANAIS DE VOZ',app.selectedCommunity!.canManage?()=>onCommunityAction(CommunityAction.voiceChannel):null),
          for(final channel in app.channels.where((row)=>row.kind==ChannelKind.voice))_channelEntry(channel),
          if(app.loadingConversation && app.channels.isEmpty)const Padding(padding:EdgeInsets.all(24),child:LinearProgressIndicator(minHeight:2))
        ]
      ])),
      if(call!=null)_callDock(),
      Container(color:const Color(0xFF232428),padding:const EdgeInsets.fromLTRB(8,8,3,8),child:Row(children:[
        InitialAvatar(name:app.account?.username??'?',radius:16),const SizedBox(width:8),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(app.account?.username??'Conta',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
          Text(app.connection.label,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:10,color:app.connection==RealtimeStatus.connected?VeylorColors.success:VeylorColors.muted))
        ])),
        IconButton(tooltip:call==null?'Entre em um canal de voz':call!.microphone?'Silenciar microfone':'Ativar microfone',
          onPressed:call?.controlsEnabled==true?()=>call!.toggleMicrophone():null,icon:Icon(call?.microphone==true?Icons.mic:Icons.mic_off,size:18)),
        IconButton(tooltip:call==null?'Entre em um canal de voz':call!.deafened?'Ativar áudio da chamada':'Desativar áudio da chamada',
          onPressed:call?.controlsEnabled==true?()=>call!.toggleDeafen():null,icon:Icon(call?.deafened==true?Icons.headset_off:Icons.headset,size:18)),
        IconButton(key:const ValueKey('open-settings'),tooltip:'Configurações',onPressed:onSettings,icon:const Icon(Icons.settings_outlined,size:18))
      ]))
    ])))
  ]);
  Widget _railButton(String name,Widget child,bool selected,VoidCallback action,Key key)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),
    child:Tooltip(message:name,child:Row(children:[
      Container(width:4,height:selected?32:0,decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(3))),
      const SizedBox(width:7),
      Expanded(child:Semantics(button:true,label:name,selected:selected,child:AnimatedContainer(duration:const Duration(milliseconds:150),
        height:46,margin:const EdgeInsets.only(right:11),decoration:BoxDecoration(color:selected?VeylorColors.accent:VeylorColors.canvas,borderRadius:BorderRadius.circular(selected?15:23)),
        child:Material(color:Colors.transparent,child:InkWell(key:key,onTap:action,borderRadius:BorderRadius.circular(15),child:Center(child:child))))))
    ])));
  Widget _section(String title,VoidCallback? add)=>Padding(padding:const EdgeInsets.fromLTRB(16,16,6,5),child:Row(children:[
    const Icon(Icons.keyboard_arrow_down,size:13,color:VeylorColors.muted),const SizedBox(width:3),
    Expanded(child:Text(title,style:const TextStyle(fontSize:10,fontWeight:FontWeight.w800,letterSpacing:.6,color:VeylorColors.muted))),
    if(add!=null)IconButton(tooltip:'Adicionar canal ou conversa',onPressed:add,visualDensity:VisualDensity.compact,icon:const Icon(Icons.add,size:17))
  ]));
  Widget _channelEntry(CommunityChannel channel){
    final voice=channel.kind==ChannelKind.voice;
    final selected=voice?showingCall && call?.channelId==channel.id:!showingCall && app.conversation==Conversation.channel(channel.id);
    return _entry(channel.name,voice?Icons.volume_up_outlined:Icons.tag,selected,()=>voice?onVoice(channel):onChannel(channel),
      key:ValueKey((voice?'voice-':'channel-')+channel.id),unread:!voice && app.hasUnread(Conversation.channel(channel.id)),
      trailing:app.selectedCommunity?.canManage==true?PopupMenuButton<String>(tooltip:'Opções do canal',padding:EdgeInsets.zero,icon:const Icon(Icons.more_horiz,size:17),
        onSelected:(_)=>onDeleteChannel(channel),itemBuilder:(_)=>[const PopupMenuItem(value:'delete',child:Text('Excluir canal'))]):null);
  }
  Widget _entry(String name,IconData icon,bool selected,VoidCallback action,{Key? key,bool unread=false,Widget? trailing})=>Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),
    child:Material(color:selected?VeylorColors.selected:Colors.transparent,borderRadius:BorderRadius.circular(5),
      child:InkWell(key:key,onTap:action,borderRadius:BorderRadius.circular(5),
        child:Padding(padding:EdgeInsets.fromLTRB(9,trailing==null?9:0,6,trailing==null?9:0),child:Row(children:[
          Icon(icon,size:20,color:selected || unread?VeylorColors.text:VeylorColors.muted),const SizedBox(width:9),
          Expanded(child:Text(name,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:14,color:selected || unread?VeylorColors.text:VeylorColors.muted,fontWeight:selected || unread?FontWeight.w600:FontWeight.w400))),
          if(unread)const Padding(padding:EdgeInsets.symmetric(horizontal:5),child:Icon(Icons.circle,size:7,color:VeylorColors.text)),
          if(trailing!=null)SizedBox(width:30,height:36,child:trailing)
        ])))));
  Widget _callDock()=>Container(key:const ValueKey('persistent-call-dock'),color:const Color(0xFF232428),padding:const EdgeInsets.fromLTRB(12,8,5,8),
    child:Row(children:[
      Expanded(child:InkWell(onTap:onShowCall,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          Icon(call!.connected?Icons.signal_cellular_alt:Icons.sync,size:16,color:call!.connected?VeylorColors.success:VeylorColors.muted),const SizedBox(width:5),
          Expanded(child:Text(call!.connected?'Voz conectada':call!.phase==CallPhase.failed?'Chamada encerrada':'Conectando voz',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)))
        ]),const SizedBox(height:3),
        Text(call!.channelName+' / '+call!.communityName,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:VeylorColors.muted)),
        if(call!.sharing)const Text('Você está transmitindo',style:TextStyle(fontSize:10,color:VeylorColors.success))
      ]))),
      IconButton(key:const ValueKey('leave-call-dock'),tooltip:'Desconectar da voz',onPressed:onLeaveCall,icon:const Icon(Icons.call_end,size:20,color:VeylorColors.danger))
    ]));
}
class MembersPanel extends StatelessWidget {
  const MembersPanel({super.key,required this.app,required this.onManage});final VeylorController app;final void Function(CommunityMember,String) onManage;
  @override Widget build(BuildContext context)=>ColoredBox(color:VeylorColors.navigation,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Padding(padding:const EdgeInsets.fromLTRB(18,23,12,16),child:Text('MEMBROS — '+app.members.length.toString(),style:const TextStyle(fontSize:11,fontWeight:FontWeight.w800,color:VeylorColors.muted,letterSpacing:.5))),
    Expanded(child:ListView(children:[
      for(final member in app.members)ListTile(dense:true,leading:InitialAvatar(name:member.username,radius:16),
        title:Text(member.username,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:13)),
        subtitle:Text(member.role.label,style:const TextStyle(fontSize:10,color:VeylorColors.muted)),
        trailing:member.role!=MemberRole.owner && app.selectedCommunity?.canManage==true && (app.selectedCommunity?.role==MemberRole.owner || member.role==MemberRole.member)?
          PopupMenuButton<String>(tooltip:'Gerenciar membro',onSelected:(action)=>onManage(member,action),itemBuilder:(_)=>[
            if(app.selectedCommunity?.role==MemberRole.owner)...[const PopupMenuItem(value:'moderator',child:Text('Tornar moderador')),const PopupMenuItem(value:'member',child:Text('Tornar membro'))],
            const PopupMenuItem(value:'kick',child:Text('Remover do servidor'))
          ]):null)
    ]))
  ]));
}
