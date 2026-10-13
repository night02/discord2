import 'package:flutter/material.dart';
import '../application/veylor_controller.dart';
import '../media/share_profile.dart';
import '../media/voice_session.dart';
import 'veylor_theme.dart';
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key,required this.app,required this.version,required this.onConfigure,required this.onUpdate,required this.onLogout});
  final VeylorController app;final String version;final VoidCallback onConfigure,onUpdate,onLogout;
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('Configurações'),content:SizedBox(width:480,child:SingleChildScrollView(
    child:AnimatedBuilder(animation:app,builder:(context,_)=>Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      ListTile(contentPadding:EdgeInsets.zero,leading:InitialAvatar(name:app.account?.username??'?',radius:24),title:Text(app.account?.username??'Conta'),subtitle:Text(version,style:const TextStyle(color:VeylorColors.muted))),
      const Divider(),
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.sync),title:const Text('Mensagens em tempo real'),subtitle:Text(app.connection.label),trailing:TextButton(onPressed:app.reconnect,child:const Text('Reconectar'))),
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.volume_up_outlined),title:const Text('Voz e transmissão'),
        subtitle:Text(app.integrations==null?'Configuração ainda não verificada':app.integrations!.voice?'Servidor de mídia configurado':'Servidor de mídia pendente')),
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.forum_outlined),title:const Text('Login com Discord'),
        subtitle:Text(app.integrations==null?'Configuração ainda não verificada':app.integrations!.discord?'Configurado':'Configuração pendente')),
      TextButton.icon(onPressed:app.checkIntegrations,icon:const Icon(Icons.refresh,size:17),label:const Text('Verificar configuração')),
      const Divider(),
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.dns_outlined),title:const Text('Servidor do aplicativo'),subtitle:Text(Uri.parse(app.api.baseUrl).host),onTap:onConfigure,trailing:const Icon(Icons.chevron_right)),
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.system_update_alt),title:const Text('Verificar atualização'),onTap:onUpdate),
      ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.logout,color:VeylorColors.danger),title:const Text('Sair da conta',style:TextStyle(color:VeylorColors.danger)),onTap:onLogout)
    ])))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Fechar'))]);
}
class CallDiagnosticsDialog extends StatelessWidget {
  const CallDiagnosticsDialog({super.key,required this.call});final VoiceSession call;
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:call,builder:(context,_)=>AlertDialog(title:const Text('Qualidade da chamada'),
    content:SizedBox(width:460,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(call.channelName+' / '+call.communityName,style:const TextStyle(color:VeylorColors.muted)),const SizedBox(height:18),
      const Text('Sua transmissão',style:TextStyle(fontWeight:FontWeight.w700)),const SizedBox(height:7),
      Text(call.sharing?'Perfil solicitado: '+call.profile.label:'Você não está transmitindo.',style:const TextStyle(color:VeylorColors.muted,fontSize:12)),
      if(call.sharing)_metrics(call.sendingMetrics),const Divider(height:30),
      const Text('Primeira transmissão recebida',style:TextStyle(fontWeight:FontWeight.w700)),_metrics(call.receivingMetrics),const SizedBox(height:20),
      const Text('As medições vêm do WebRTC. Valores ausentes aguardam dados do dispositivo. A conexão e o equipamento podem reduzir a qualidade solicitada.',
        style:TextStyle(fontSize:12,color:VeylorColors.muted,height:1.5)),
      const SizedBox(height:12),const Text('Áudio do jogo: captura do sistema ainda não integrada no Windows.',style:TextStyle(fontSize:12,color:VeylorColors.muted))
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Fechar'))]));
  Widget _metrics(StreamMetrics value)=>Padding(padding:const EdgeInsets.only(top:8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(value.hasVideo?'Resolução: '+value.width!.toInt().toString()+'×'+value.height!.toInt().toString():'Resolução: aguardando medição',style:const TextStyle(fontSize:13)),
    Text(value.fps==null?'FPS: aguardando medição':'FPS: '+value.fps!.toStringAsFixed(1),style:const TextStyle(fontSize:13)),
    Text(value.bitsPerSecond==null?'Bitrate: aguardando medição':'Bitrate: '+(value.bitsPerSecond!/1000000).toStringAsFixed(2)+' Mbps',style:const TextStyle(fontSize:13)),
    if(value.roundTripMs!=null)Text('Latência de ida e volta: '+value.roundTripMs!.toStringAsFixed(0)+' ms',style:const TextStyle(fontSize:13)),
    if(value.codec!=null)Text('Codec: '+value.codec!,style:const TextStyle(fontSize:12)),
    if(value.limitation!=null && value.limitation!='none')Text(value.limitation=='cpu'?'Qualidade limitada pelo processamento.':
      value.limitation=='bandwidth'?'Qualidade limitada pela conexão.':'Qualidade ajustada pelo encoder.',style:const TextStyle(color:VeylorColors.muted,fontSize:12))
  ]));
}
