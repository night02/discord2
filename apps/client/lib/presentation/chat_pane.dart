import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/models.dart';
import '../application/veylor_controller.dart';
import 'veylor_theme.dart';
class ChatPane extends StatefulWidget {
  const ChatPane({super.key,required this.app,required this.onNewDm,required this.onCreate,required this.onJoin,required this.onMembers,required this.onCommunity,this.onOpenNavigation});
  final VeylorController app;final VoidCallback onNewDm,onCreate,onJoin,onMembers;final void Function(Community) onCommunity;final VoidCallback? onOpenNavigation;
  @override State<ChatPane> createState()=>_ChatPaneState();
}
class _ChatPaneState extends State<ChatPane> {
  final editor=TextEditingController(),search=TextEditingController(),scroll=ScrollController();
  Conversation? _draftTarget;String? _draftAccount;bool searching=false,_syncing=false,_hasNew=false;int _lastCount=0;
  @override void initState(){
    super.initState();_draftTarget=widget.app.conversation;_draftAccount=widget.app.account?.id;editor.text=widget.app.draft(_draftTarget);
    editor.addListener(_saveDraft);widget.app.addListener(_onAppChanged);
  }
  void _saveDraft(){
    if(!_syncing && widget.app.account?.id==_draftAccount && widget.app.phase==AppPhase.signedIn)widget.app.saveDraft(_draftTarget,editor.text);
  }
  void _restoreDraft(){
    final saved=widget.app.draft(_draftTarget);
    if(editor.text==saved)return;
    _syncing=true;editor.text=saved;_syncing=false;
  }
  void _onAppChanged(){
    if(!mounted)return;
    if(widget.app.account?.id!=_draftAccount || widget.app.phase!=AppPhase.signedIn){
      _draftTarget=null;_draftAccount=widget.app.account?.id;_syncing=true;editor.clear();_syncing=false;
    }
    if(_draftTarget!=widget.app.conversation){
      _draftTarget=widget.app.conversation;_restoreDraft();
      search.clear();_hasNew=false;_lastCount=widget.app.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_){if(mounted && scroll.hasClients)scroll.jumpTo(0);});
    }else{
      _restoreDraft();
      if(widget.app.messages.length>_lastCount){_hasNew=scroll.hasClients && scroll.offset>120;_lastCount=widget.app.messages.length;}
    }
    setState((){});
  }
  Future<void> send() async {
    final target=_draftTarget,text=editor.text,sent=await widget.app.send(editor.text);
    if(!mounted || !sent)return;
    if(_draftTarget==target && editor.text==text)editor.clear();
    if(_draftTarget==target)await _latest();
  }
  Future<void> _latest() async {
    if(mounted)setState(()=>_hasNew=false);
    if(scroll.hasClients)await scroll.animateTo(0,duration:const Duration(milliseconds:180),curve:Curves.easeOut);
  }
  @override void dispose(){
    widget.app.removeListener(_onAppChanged);editor.removeListener(_saveDraft);editor.dispose();search.dispose();scroll.dispose();super.dispose();
  }
  @override Widget build(BuildContext context){
    final app=widget.app,target=app.conversation,query=search.text.trim().toLowerCase();
    final rows=query.isEmpty?app.messages:app.messages.where((row)=>row.content.toLowerCase().contains(query) || row.username.toLowerCase().contains(query)).toList();
    return ColoredBox(color:VeylorColors.canvas,child:Column(children:[
      Container(height:52,padding:const EdgeInsets.symmetric(horizontal:12),decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:VeylorColors.divider))),child:Row(children:[
        if(widget.onOpenNavigation!=null)IconButton(key:const ValueKey('open-navigation'),tooltip:'Abrir servidores e canais',onPressed:widget.onOpenNavigation,icon:const Icon(Icons.menu)),
        Icon(target==null?Icons.forum_outlined:target.isDirect?Icons.alternate_email:Icons.tag,color:VeylorColors.muted,size:23),const SizedBox(width:10),
        Expanded(child:Text(target==null?'Conversas':app.conversationName,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w800))),
        if(target!=null)...[
          IconButton(tooltip:'Buscar nas mensagens carregadas',key:const ValueKey('search-messages'),onPressed:()=>setState((){searching=!searching;if(!searching)search.clear();}),icon:Icon(searching?Icons.search_off:Icons.search,size:21)),
          IconButton(tooltip:'Atualizar conversa',onPressed:app.loadingConversation?null:()=>app.refreshMessages(),icon:const Icon(Icons.refresh,size:21))
        ],
        if(!app.isHome)IconButton(tooltip:'Membros e cargos',onPressed:widget.onMembers,icon:const Icon(Icons.people_alt_outlined,size:21))
      ])),
      if(searching && target!=null)Padding(padding:const EdgeInsets.fromLTRB(16,10,16,6),child:TextField(key:const ValueKey('message-search'),controller:search,autofocus:true,onChanged:(_)=>setState((){}),
        decoration:const InputDecoration(isDense:true,hintText:'Buscar nas mensagens já carregadas',prefixIcon:Icon(Icons.search,size:19)))),
      if(app.loadingConversation && target!=null)const LinearProgressIndicator(minHeight:2),
      Expanded(child:target==null?_home():Stack(children:[
        ListView.builder(key:ValueKey(target.route),reverse:true,controller:scroll,padding:const EdgeInsets.fromLTRB(16,12,16,8),itemCount:rows.length+1,itemBuilder:(_,index){
          if(index==rows.length)return _welcome(target,query,rows.isEmpty);
          final position=rows.length-index-1,row=rows[position],previous=position>0?rows[position-1]:null;
          final compact=previous!=null && previous.username==row.username && previous.createdAt!=null && row.createdAt!=null &&
            row.createdAt!.difference(previous.createdAt!).inSeconds>=0 && row.createdAt!.difference(previous.createdAt!).inMinutes<5;
          return MessageRow(message:row,compact:compact);
        }),
        if(_hasNew)Positioned(top:8,left:16,right:16,child:FilledButton.icon(onPressed:_latest,icon:const Icon(Icons.arrow_downward,size:16),label:const Text('Novas mensagens · ir para o final')))
      ])),
      if(target!=null)_composer(app)
    ]));
  }
  Widget _welcome(Conversation target,String query,bool empty)=>Padding(padding:const EdgeInsets.fromLTRB(8,32,8,24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    CircleAvatar(radius:31,backgroundColor:VeylorColors.selected,child:Icon(target.isDirect?Icons.person:Icons.tag,size:34,color:VeylorColors.text)),
    const SizedBox(height:18),Text(target.isDirect?'Conversa com '+widget.app.conversationName:'Bem-vindo a #'+widget.app.conversationName,style:const TextStyle(fontSize:26,fontWeight:FontWeight.w800,height:1.2)),
    const SizedBox(height:9),Text(target.isDirect?'Um espaço para conversar diretamente.':'Este é o começo da conversa neste canal.',style:const TextStyle(fontSize:14,color:VeylorColors.muted)),
    if(empty && query.isNotEmpty)const Padding(padding:EdgeInsets.only(top:24),child:Text('Nenhuma mensagem carregada corresponde à busca.',style:TextStyle(color:VeylorColors.muted))),
    const SizedBox(height:16),const Divider()
  ]));
  Widget _composer(VeylorController app)=>Padding(padding:const EdgeInsets.fromLTRB(16,8,16,14),
    child:Container(decoration:BoxDecoration(color:VeylorColors.composer,borderRadius:BorderRadius.circular(8)),padding:const EdgeInsets.symmetric(horizontal:9),
      child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
        const Padding(padding:EdgeInsets.only(bottom:14,right:10,left:5),child:Icon(Icons.chat_bubble_outline,color:VeylorColors.muted,size:20)),
        Expanded(child:CallbackShortcuts(bindings:{const SingleActivator(LogicalKeyboardKey.enter):()=>unawaited(send())},
          child:TextField(key:const ValueKey('message-composer'),controller:editor,maxLength:4000,minLines:1,maxLines:5,textInputAction:TextInputAction.send,onSubmitted:(_)=>send(),style:const TextStyle(fontSize:14,height:1.45),
            decoration:InputDecoration(counterText:'',filled:false,border:InputBorder.none,focusedBorder:InputBorder.none,enabledBorder:InputBorder.none,
              contentPadding:const EdgeInsets.symmetric(vertical:14),hintText:app.conversation!.isDirect?'Mensagem para '+app.conversationName:'Mensagem em #'+app.conversationName)))),
        ValueListenableBuilder<TextEditingValue>(valueListenable:editor,builder:(_,value,__)=>Padding(padding:const EdgeInsets.only(bottom:5),child:IconButton(
          key:const ValueKey('send-message'),tooltip:'Enviar mensagem',onPressed:app.sending || value.text.trim().isEmpty?null:send,
          icon:app.sending?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.send_rounded,color:VeylorColors.accent,size:21))))
      ])));
  Widget _home()=>Center(child:SingleChildScrollView(padding:const EdgeInsets.all(28),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:620),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Icon(Icons.forum_outlined,size:48,color:VeylorColors.accent),const SizedBox(height:22),
      const Text('Junte sua galera.',style:TextStyle(fontSize:32,fontWeight:FontWeight.w900)),const SizedBox(height:10),
      const Text('Abra uma conversa privada ou encontre sua comunidade nos servidores.',style:TextStyle(fontSize:15,height:1.6,color:VeylorColors.muted)),const SizedBox(height:24),
      Wrap(spacing:10,runSpacing:10,children:[
        FilledButton.icon(onPressed:widget.onNewDm,icon:const Icon(Icons.add_comment_outlined,size:18),label:const Text('Nova conversa')),
        OutlinedButton.icon(onPressed:widget.onCreate,icon:const Icon(Icons.add,size:18),label:const Text('Criar servidor')),
        TextButton(onPressed:widget.onJoin,child:const Text('Entrar com convite'))]),
      if(widget.app.communities.isNotEmpty)...[
        const SizedBox(height:32),const Text('SEUS SERVIDORES',style:TextStyle(fontSize:11,color:VeylorColors.muted,fontWeight:FontWeight.w800,letterSpacing:.7)),const SizedBox(height:10),
        for(final server in widget.app.communities)Card(color:VeylorColors.navigation,child:ListTile(onTap:()=>widget.onCommunity(server),
          leading:InitialAvatar(name:server.name),title:Text(server.name),subtitle:Text(server.role.label,style:const TextStyle(fontSize:12)),trailing:const Icon(Icons.chevron_right,size:20)))
      ]
    ]))));
}
class MessageRow extends StatelessWidget {
  const MessageRow({super.key,required this.message,this.compact=false});final ChatMessage message;final bool compact;
  @override Widget build(BuildContext context){
    final date=message.createdAt?.toLocal();
    final time=date==null?'':date.hour.toString().padLeft(2,'0')+':'+date.minute.toString().padLeft(2,'0');
    return Padding(padding:EdgeInsets.only(top:compact?1:15,bottom:2),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      SizedBox(width:40,child:compact?Padding(padding:const EdgeInsets.only(top:4),child:Text(time,style:const TextStyle(fontSize:9,color:VeylorColors.muted),textAlign:TextAlign.center)):InitialAvatar(name:message.username)),
      const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        if(!compact)Padding(padding:const EdgeInsets.only(bottom:3),child:Wrap(crossAxisAlignment:WrapCrossAlignment.center,spacing:9,children:[
          Text(message.username,style:const TextStyle(fontSize:14,fontWeight:FontWeight.w700)),Text(time,style:const TextStyle(fontSize:10,color:VeylorColors.muted))])),
        SelectableText(message.content,style:const TextStyle(fontSize:14,height:1.45,color:Color(0xFFDBDEE1)))
      ]))
    ]));
  }
}
