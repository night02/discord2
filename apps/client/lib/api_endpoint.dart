/// Only HTTPS may be used with remote hosts to protect bearer credentials.
String validateApiEndpoint(String input) {
  final uri=Uri.tryParse(input.trim());
  if(uri==null || !uri.hasAuthority || uri.host.isEmpty ||
      !['http','https'].contains(uri.scheme) || uri.userInfo.isNotEmpty ||
      uri.hasQuery || uri.hasFragment || (uri.path.isNotEmpty && uri.path!='/')) {
    throw const FormatException('Use https://api.seudominio.com');
  }
  if(uri.scheme=='http' &&
      !['localhost','127.0.0.1','::1'].contains(uri.host) &&
      !const bool.fromEnvironment('ALLOW_INSECURE_DEV_API')) {
    throw const FormatException('Endereços remotos exigem HTTPS.');
  }
  return uri.origin;
}

const previousVeylorApi='https://veylor-v02-api.onrender.com';
const newVeylorApi='https://veylor-postgres-staging.onrender.com';

/// Decides whether an installation should move to the fresh PostgreSQL service.
/// Explicit third-party/self-hosted endpoints are never silently overridden.
class StartupServer {
  const StartupServer(this.address,{required this.clearOldSession,required this.movedFromLegacy});
  final String address;
  final bool clearOldSession;
  final bool movedFromLegacy;
}

StartupServer selectStartupServer(String? savedAddress,{String defaultAddress=newVeylorApi}) {
  final target=validateApiEndpoint(defaultAddress);
  final saved=(savedAddress==null||savedAddress.trim().isEmpty)
      ?null:validateApiEndpoint(savedAddress);
  if(saved==null) {
    // An older version might have saved a token but not its API address.
    return StartupServer(target,clearOldSession:true,movedFromLegacy:false);
  }
  if(saved==previousVeylorApi && saved!=target) {
    return StartupServer(target,clearOldSession:true,movedFromLegacy:true);
  }
  return StartupServer(saved,clearOldSession:false,movedFromLegacy:false);
}
