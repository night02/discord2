import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/models.dart';
import '../application/veylor_controller.dart';
import 'veylor_theme.dart';
class WorkspaceDialogs {
  WorkspaceDialogs(this.context,this.app);final BuildContext context;final VeylorController app;
  Future<String?> prompt(String title,String hint,{int min=1,int max=50}) async {
    final text=TextEditingController(),form=GlobalKey<FormState>();
    final result=await showDialog<String>(context:context,builder:(ctx){
      void submit(){if(form.currentState!.validate())Navigator.pop(ctx,text.text.trim());}
      return AlertDialog(title:Text(title),content:SizedBox(width:360,child:Form(key:form,child:TextFormField(
        controller:text,autofocus:true,maxLength:max,onFieldSubmitted:(_)=>submit(),decoration:InputDecoration(labelText:hint),
        validator:(value)=>(value?.trim().length??0)<min?'Preencha este campo (mínimo $min).':null))),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),FilledButton(onPressed:submit,child:const Text('Continuar'))]);
    });
    WidgetsBinding.instance.addPostFrameCallback((_)=>text.dispose());return result;
  }
  Future<void> createCommunity() async {final name=await prompt('Crie seu servidor','Nome do servidor',min:2);if(name!=null && context.mounted)await app.createCommunity(name);}
  Future<void> join() async {final value=await prompt('Entre em um servidor','Código de convite',min:4,max:128);if(value!=null && context.mounted)await app.joinInvitation(value);}
  Future<void> newMessage() async {final name=await prompt('Nova conversa privada','Nome de usuário',min:3,max:24);if(name!=null && context.mounted)await app.startDirectMessage(name);}
  Future<void> createChannel(ChannelKind kind) async {final name=await prompt(kind==ChannelKind.voice?'Criar canal de voz':'Criar canal de texto','Nome do canal');if(name!=null && context.mounted)await app.createChannel(name,kind);}
  Future<bool> confirm(String title,String message,String action) async=>await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
    title:Text(title),content:Text(message),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(action))]))??false;
  Future<bool> deleteChannel(CommunityChannel channel) async {
    if(!await confirm('Excluir #'+channel.name+'?','As mensagens deste canal serão removidas. Esta ação não pode ser desfeita.','Excluir canal') || !context.mounted)return false;
    await app.deleteChannel(channel);return !app.channels.any((row)=>row.id==channel.id);
  }
  Future<void> manageMember(CommunityMember member,String action) async {
    if(action=='kick' && !await confirm('Remover '+member.username+'?','A pessoa poderá voltar com um novo convite.','Remover'))return;
    if(context.mounted)await app.manageMember(member,action);
  }
  Future<void> invite() async {
    final code=await app.createInvitation();if(code==null || !context.mounted)return;
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Convide sua galera'),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Envie este código para entrar no servidor. Ele é válido por 7 dias.',style:TextStyle(color:VeylorColors.muted,height:1.5)),
        const SizedBox(height:20),SelectableText(code,style:const TextStyle(fontSize:21,fontWeight:FontWeight.w700))]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Fechar')),FilledButton.icon(onPressed:() async {
        await Clipboard.setData(ClipboardData(text:code));if(ctx.mounted)ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content:Text('Convite copiado.')));
      },icon:const Icon(Icons.copy,size:18),label:const Text('Copiar convite'))]));
  }
  Future<void> configureAddress() async {
    final address=TextEditingController(text:app.api.baseUrl);
    final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Servidor Veylor'),
      content:SizedBox(width:440,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Use o endereço do seu servidor. Trocar de servidor exige um novo login.',style:TextStyle(color:VeylorColors.muted,height:1.5)),const SizedBox(height:16),
        TextField(controller:address,autofocus:true,keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'Endereço HTTPS',hintText:'https://api.exemplo.com'))])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,address.text),child:const Text('Salvar'))]));
    WidgetsBinding.instance.addPostFrameCallback((_)=>address.dispose());
    if(result==null || !context.mounted)return;
    try{await app.configureAddress(result);}catch(_){
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Endereço inválido. Use HTTPS; HTTP é permitido apenas no desenvolvimento local.')));
    }
  }
}
