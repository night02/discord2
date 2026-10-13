import 'package:flutter/material.dart';
import '../application/veylor_controller.dart';
import 'veylor_theme.dart';
class AuthPage extends StatefulWidget {
  const AuthPage({super.key,required this.app,required this.version,required this.onConfigure,required this.onDiscord,required this.onUpdate});
  final VeylorController app;final String version;final VoidCallback onConfigure,onDiscord,onUpdate;
  @override State<AuthPage> createState()=>_AuthPageState();
}
class _AuthPageState extends State<AuthPage> {
  final username=TextEditingController(),password=TextEditingController();final form=GlobalKey<FormState>();
  bool register=false,obscure=true;
  @override void dispose(){username.dispose();password.dispose();super.dispose();}
  Future<void> submit() async {
    if(!form.currentState!.validate())return;
    final accepted=await widget.app.authenticate(username.text,password.text,register:register);
    if(accepted && mounted)password.clear();
  }
  @override Widget build(BuildContext context)=>LayoutBuilder(builder:(context,size){
    final app=widget.app,wide=size.maxWidth>=1050;
    final card=Container(width:440,padding:const EdgeInsets.all(28),
      decoration:BoxDecoration(color:VeylorColors.navigation,borderRadius:BorderRadius.circular(14),boxShadow:const[BoxShadow(color:Colors.black26,blurRadius:32,offset:Offset(0,14))]),
      child:Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Center(child:BrandMark(size:64)),const SizedBox(height:20),
        Text(register?'Crie sua conta':'Bem-vindo ao Veylor',textAlign:TextAlign.center,style:const TextStyle(fontSize:25,fontWeight:FontWeight.w800)),
        const SizedBox(height:8),Text(register?'Seu próximo encontro começa aqui.':'Bom ter você por aqui de novo.',textAlign:TextAlign.center,style:const TextStyle(color:VeylorColors.muted)),
        const SizedBox(height:25),
        TextFormField(key:const ValueKey('login-username'),controller:username,enabled:!app.busy,autofillHints:const[AutofillHints.username],textInputAction:TextInputAction.next,
          decoration:const InputDecoration(labelText:'Usuário',prefixIcon:Icon(Icons.person_outline)),
          validator:(value)=>value==null || !RegExp(r'^[a-zA-Z0-9_]{3,24}$').hasMatch(value.trim())?'Use de 3 a 24 letras, números ou _.':null),
        const SizedBox(height:14),
        TextFormField(key:const ValueKey('login-password'),controller:password,enabled:!app.busy,obscureText:obscure,
          autofillHints:[register?AutofillHints.newPassword:AutofillHints.password],textInputAction:TextInputAction.done,onFieldSubmitted:(_)=>submit(),
          decoration:InputDecoration(labelText:'Senha',prefixIcon:const Icon(Icons.lock_outline),
            suffixIcon:IconButton(tooltip:obscure?'Mostrar senha':'Ocultar senha',onPressed:()=>setState(()=>obscure=!obscure),icon:Icon(obscure?Icons.visibility_outlined:Icons.visibility_off_outlined,size:20))),
          validator:(value)=>value==null || value.isEmpty?'Informe sua senha.':register && (value.length<10 || value.length>128)?'Use de 10 a 128 caracteres.':null),
        const SizedBox(height:22),
        FilledButton(key:const ValueKey('login-submit'),onPressed:app.busy?null:submit,
          child:app.busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):Text(register?'Criar conta':'Entrar')),
        TextButton(onPressed:app.busy?null:()=>setState((){register=!register;form.currentState?.reset();}),child:Text(register?'Já tenho uma conta':'Criar uma conta')),
        const Row(children:[Expanded(child:Divider()),Padding(padding:EdgeInsets.symmetric(horizontal:12),child:Text('ou',style:TextStyle(color:VeylorColors.muted,fontSize:12))),Expanded(child:Divider())]),
        const SizedBox(height:10),
        OutlinedButton.icon(onPressed:app.busy?null:widget.onDiscord,icon:const Icon(Icons.forum_outlined,size:18),label:const Text('Continuar com Discord')),
        if(app.error!=null)Padding(padding:const EdgeInsets.only(top:14),child:ErrorNotice(message:app.error!,onDismiss:app.dismissError)),
        if(app.sessionMoved)const Padding(padding:EdgeInsets.only(top:12),child:Text('Seu servidor foi atualizado. Entre com uma conta desse servidor.',textAlign:TextAlign.center,style:TextStyle(fontSize:12,color:VeylorColors.muted))),
        const SizedBox(height:18),
        TextButton.icon(onPressed:app.busy?null:widget.onConfigure,icon:const Icon(Icons.dns_outlined,size:15),
          label:Text('Servidor: '+Uri.parse(app.api.baseUrl).host,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11))),
        TextButton(onPressed:widget.onUpdate,child:Text(widget.version+' · Verificar atualização',style:const TextStyle(fontSize:11,color:VeylorColors.muted)))
      ])));
    return DecoratedBox(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF101E2B),Color(0xFF1E1F22),Color(0xFF19243B)])),
      child:Center(child:SingleChildScrollView(padding:EdgeInsets.all(size.maxWidth<500?16:32),child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        if(wide)const Padding(padding:EdgeInsets.only(right:72),child:SizedBox(width:350,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('VEYLOR',style:TextStyle(fontSize:14,fontWeight:FontWeight.w800,letterSpacing:5,color:VeylorColors.accent)),
          SizedBox(height:25),Text('Sua comunidade.\nSua conversa.\nSua tela.',style:TextStyle(fontSize:49,fontWeight:FontWeight.w900,height:1.12)),
          SizedBox(height:24),Text('Encontre sua galera, entre na chamada e compartilhe o momento.',style:TextStyle(fontSize:17,color:VeylorColors.muted,height:1.6)),
          SizedBox(height:28),Wrap(spacing:8,runSpacing:8,children:[Chip(label:Text('Comunidades')),Chip(label:Text('Voz e vídeo')),Chip(label:Text('Sua tela'))])
        ]))),
        Flexible(child:card)
      ]))));
  });
}
class RecoveryPage extends StatelessWidget {
  const RecoveryPage({super.key,required this.app,required this.onConfigure});final VeylorController app;final VoidCallback onConfigure;
  @override Widget build(BuildContext context)=>Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:440),
    child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.cloud_off_outlined,size:56,color:VeylorColors.muted),const SizedBox(height:20),
      const Text('Não conseguimos conectar',style:TextStyle(fontSize:25,fontWeight:FontWeight.w800),textAlign:TextAlign.center),
      const SizedBox(height:12),Text(app.error??'O servidor não respondeu.',textAlign:TextAlign.center,style:const TextStyle(color:VeylorColors.muted)),
      const SizedBox(height:24),FilledButton.icon(onPressed:()=>app.bootstrap(),icon:const Icon(Icons.refresh),label:const Text('Tentar reconectar')),
      TextButton(onPressed:onConfigure,child:const Text('Configurar servidor')),TextButton(onPressed:app.showLogin,child:const Text('Entrar com outra conta'))
    ]))));
}
