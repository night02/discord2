import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api_client.dart';
import '../api_endpoint.dart';
import '../update_service.dart';
import '../windows_update_download.dart';
import '../update_diagnostics.dart';
class UpdateCoordinator {
  UpdateCoordinator(this.context);
  final BuildContext context;
  bool checkingUpdate=false;
  Future<void> checkForUpdates({bool silent=false}) async {
    if((!Platform.isAndroid&&!Platform.isWindows) || checkingUpdate)return;
    checkingUpdate=true;
    try {
      final isAndroid=Platform.isAndroid;
      // Never send bearer sessions or use untrusted custom servers for updates.
      final updatesApi=Api(newVeylorApi);
      final response=await updatesApi.request('GET',
          isAndroid?'/api/updates/android':'/api/updates/windows');
      final AppUpdateInfo update=isAndroid
          ? AndroidUpdate.fromJson(response) : WindowsUpdate.fromJson(response);
      final installed=await PackageInfo.fromPlatform();
      final currentBuild=int.tryParse(installed.buildNumber)??0;
      if(!context.mounted)return;
      if(!update.isNewerThan(currentBuild)){
        if(!silent)ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content:Text('Você está usando a versão mais recente deste canal beta.')));
        return;
      }
      await showDialog<void>(context:context,builder:(dialogContext)=>AlertDialog(
        title:Text('Veylor ${update.version} disponível'),
        content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Nova compilação ${update.build}. Atual: ${installed.version} (${installed.buildNumber}).'),
          const SizedBox(height:12),Text(update.notes),
          const SizedBox(height:12),
          Text(Platform.isAndroid
            ? 'O download abre a página oficial do GitHub. APKs de teste podem ter '
              'assinaturas diferentes e exigir reinstalação.'
            : 'O Windows baixa apenas a Release oficial e valida SHA-256 antes '
              'de pedir sua confirmação. A Veylor é fechada para instalar e '
              'uma cópia da versão anterior permite reverter falhas. '
              'O instalador beta ainda não tem assinatura Authenticode.',
            style:const TextStyle(fontSize:12)),
        ]),
        actions:[
          TextButton(onPressed:()=>Navigator.of(dialogContext).pop(),
            child:const Text('Depois')),
          FilledButton(onPressed:() async {
            Navigator.of(dialogContext).pop();
            if (Platform.isWindows && update is WindowsUpdate &&
                update.downloadUrl.path.contains('/releases/tag/')) {
              await downloadWindowsUpdate(update);
            } else {
              final success=await launchUrl(update.downloadUrl,mode:LaunchMode.externalApplication);
              if(!success&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content:Text('Não foi possível abrir o GitHub.')));
            }
          },child:Text(Platform.isWindows && update.downloadUrl.path.contains('/releases/tag/')
              ? 'Baixar atualização' : 'Abrir download'))
        ]));
    }catch(e){
      if(!silent&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Falha ao verificar atualização: $e')));
    }finally{checkingUpdate=false;}
  }
  Future<void> downloadWindowsUpdate(WindowsUpdate update) async {
    if (!Platform.isWindows || !context.mounted) return;
    final downloader=VeylorWindowsDownloader();
    final progress=ValueNotifier<double>(0);
    bool cancelled=false;
    final downloadMessage = ValueNotifier<String>('Preparando download...');
    WindowsUpdatePackage? staged;
    final progressDialog=showDialog<void>(
      context:context, barrierDismissible:false,
      builder:(ctx)=>AlertDialog(
        title:const Text('Baixando instalador oficial'),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          ValueListenableBuilder<double>(valueListenable:progress,
            builder:(_,value,__)=>Column(children:[
              LinearProgressIndicator(value:value),
              const SizedBox(height:12),
              Text('${(value*100).toStringAsFixed(0)}% — verificaremos o SHA-256 antes de instalar.'),
              ValueListenableBuilder<String>(
                valueListenable: downloadMessage,
                builder: (_, message, __) => Text(message,
                  style: const TextStyle(fontSize: 12)),
              )
            ]))
        ]),
        actions:[TextButton(onPressed:() {
          cancelled = true;
          downloader.cancel();
        },child:const Text('Cancelar download'))],
      ));
    try {
      staged=await downloader.prepare(update,
        cancelled: () => cancelled,
        onRetry: (attempt) {
          downloadMessage.value = 'Reconectando... tentativa ${attempt + 1}/3';
        },
        onProgress: (received,total) {
          if (total > 0) progress.value = received / total;
        });
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Atualização recusada: $e')));
      return;
    } finally {
      downloader.close();
      if (context.mounted) Navigator.of(context,rootNavigator:true).pop();
      await progressDialog;
      progress.dispose();
      downloadMessage.dispose();
    }
    final package=staged;
    if (!context.mounted || cancelled) {
      await package.discard();
      return;
    }
    final installer=package.installer;
    final current=(await PackageInfo.fromPlatform()).version;
    final approved=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('Instalar Veylor ${package.version}?'),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Versão atual: $current'),
        Text('Instalador: ${installer.path.split(Platform.pathSeparator).last}'),
        const SizedBox(height:8),
        Text('SHA-256 verificado: ${package.sha256.substring(0,16)}…',
          style:const TextStyle(fontSize:12)),
        const SizedBox(height:12),
        const Text('Ao confirmar, a Veylor será fechada e a instalação começará. '
          'O atualizador salva uma cópia dos arquivos anteriores e tenta '
          'restaurá-la se a instalação falhar. Sem certificado Windows, '
          'o sistema pode exibir um aviso de segurança.'),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Agora não')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Instalar e reiniciar'))
      ]));
    if(approved!=true){await package.discard();return;}
    await UpdateDiagnostics.add('install_confirmed');
    try {
      final currentExe=File(Platform.resolvedExecutable);
      if(currentExe.uri.pathSegments.last.toLowerCase()!='veylor.exe') {
        throw const FormatException('Atualizador só funciona no aplicativo Windows instalado.');
      }
      final helper=File('${currentExe.parent.path}${Platform.pathSeparator}veylor-updater.exe');
      if(!await helper.exists()) {
        throw const FileSystemException('Componente de atualização não encontrado');
      }
      if(!await File('${currentExe.parent.path}${Platform.pathSeparator}unins000.exe').exists()) {
        throw const FileSystemException('Instalação portátil detectada. Atualize manualmente usando o GitHub.');
      }
      final copy=await helper.copy('${package.directory.path}${Platform.pathSeparator}veylor-updater.exe');
      await Process.start(copy.path,[
        '--installer',installer.path,
        '--sha256',package.sha256,
        '--install-dir',currentExe.parent.path,
        '--parent-pid','$pid',
        '--target-version',package.version,
      ],mode:ProcessStartMode.detached);
      // The separate helper waits until this Windows process has fully exited.
      exit(0);
    } catch(e){
      await package.discard();
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Instalação não iniciada: $e')));
    }
  }

}
