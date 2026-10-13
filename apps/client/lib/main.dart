import 'package:flutter/material.dart';
import 'application_host.dart';
export 'application_host.dart' show VeylorApp;
export 'api_client.dart' show Api,ApiException;
void main(List<String> args){
  WidgetsFlutterBinding.ensureInitialized();
  runApp(VeylorApp(startupArguments:args));
}
