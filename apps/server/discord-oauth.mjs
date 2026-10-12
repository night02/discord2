import {randomBytes, createHash} from 'node:crypto';

// Discord OAuth2 auth-code handoff. Browser NEVER receives a Veylor session.
// Every login requires both the browser state and the separate app poll secret.
// The database adapter must consume states atomically to prevent replay.
export const digest=value=>createHash('sha256').update(value).digest('hex');
export const secret=()=>randomBytes(32).toString('hex');
export const oauthFail=(status,message)=>Object.assign(new Error(message),{status});

export function discordConfiguration(env=process.env) {
  const id=env.DISCORD_CLIENT_ID, key=env.DISCORD_CLIENT_SECRET, callback=env.DISCORD_REDIRECT_URI;
  if(!id||!key||!callback)throw oauthFail(503,'Login Discord ainda não configurado');
  if(!/^\d{15,22}$/.test(id)||typeof key!=='string'||key.length<12)
    throw oauthFail(503,'Credenciais Discord inválidas no servidor');
  let url;
  try{url=new URL(callback)}catch{throw oauthFail(503,'Redirect URI do Discord inválida')}
  if(url.protocol!=='https:'||url.username||url.password||url.hash||url.search||
      url.pathname!=='/api/auth/discord/callback'||url.port)
    throw oauthFail(503,'Callback Discord deve usar HTTPS sem redirecionamento variável');
  return {id,key,redirect:url.toString()};
}

export function authorizationUrl(config,state){
  if(!/^[a-f0-9]{64}$/.test(state))throw oauthFail(400,'Estado OAuth inválido');
  const url=new URL('https://discord.com/oauth2/authorize');
  url.searchParams.set('client_id',config.id);
  url.searchParams.set('redirect_uri',config.redirect);
  url.searchParams.set('response_type','code');
  url.searchParams.set('scope','identify');
  url.searchParams.set('state',state);
  url.searchParams.set('prompt','consent');
  return url.toString();
}

export async function discordIdentity(code, config, fetchImpl=fetch) {
  if(typeof code!=='string'||code.length<10||code.length>2048)
    throw oauthFail(400,'Código OAuth inválido');
  // Token/refresh token live in this function only. Never save or return them.
  const body=new URLSearchParams({
    client_id:config.id, client_secret:config.key,
    grant_type:'authorization_code', code, redirect_uri:config.redirect
  });
  let grant;
  try{
    const response=await fetchImpl('https://discord.com/api/oauth2/token',{
      method:'POST',headers:{'content-type':'application/x-www-form-urlencoded',
        accept:'application/json'},body:body.toString(),
      signal:AbortSignal.timeout(10000)
    });
    if(!response.ok)throw oauthFail(401,'Autorização Discord recusada');
    grant=await response.json();
    if(typeof grant.access_token!=='string'||grant.access_token.length<15)
      throw oauthFail(401,'Resposta OAuth inválida');
    const identityResponse=await fetchImpl('https://discord.com/api/users/@me',{
      headers:{authorization:`Bearer ${grant.access_token}`,accept:'application/json'},
      signal:AbortSignal.timeout(10000)
    });
    if(!identityResponse.ok)throw oauthFail(502,'Perfil Discord indisponível');
    const profile=await identityResponse.json();
    if(typeof profile.id!=='string'||!/^\d{15,22}$/.test(profile.id)||
      typeof profile.username!=='string')
      throw oauthFail(502,'Perfil Discord inválido');
    return {id:profile.id};
  }catch(error){
    if(error.status)throw error;
    throw oauthFail(502,'Não foi possível consultar Discord neste momento');
  }
}

export const safeOAuthHtml=(message)=>{
  // Only constant text supplied by our route; no OAuth code, state, token or id.
  const safe=message==='ok'?'Autorização concluída. Volte ao aplicativo Veylor.':
    'Não foi possível autorizar. Volte ao Veylor e tente novamente.';
  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Veylor | Discord</title></head><body style="background:#191a20;
  color:white;text-align:center;font:18px system-ui;padding:50px">
  <h1>Veylor</h1><p>${safe}</p><p>Pode fechar esta aba.</p></body></html>`;
};

export function createDiscordOAuth(adapter,{
  env=process.env,fetchImpl=fetch,clock=()=>Date.now()
}={}) {
  const start=async()=>{
    const config=discordConfiguration(env);
    const id=secret(),state=secret(),claim=secret();
    await adapter.createAttempt({
      id,stateHash:digest(state),proofHash:digest(claim),expiresAt:clock()+300000
    });
    return {
      url:authorizationUrl(config,state),
      request_id:id,
      poll_secret:claim,
      expires_in:300
    };
  };
  const callback=async(uri)=>{
    const config=discordConfiguration(env);
    const state=uri.searchParams.get('state');
    if(typeof state!=='string'||!(/^[a-f0-9]{64}$/).test(state))
      throw oauthFail(400,'Estado OAuth inválido');
    const attempt=await adapter.claimState(digest(state),clock());
    if(!attempt)throw oauthFail(400,'Autorização expirada ou já utilizada');
    try{
      if(uri.searchParams.get('error'))throw oauthFail(400,'Autorização Discord cancelada');
      const identity=await discordIdentity(uri.searchParams.get('code'),config,fetchImpl);
      const userId=await adapter.identityUser(identity.id);
      await adapter.finish(attempt.id,userId);
      return true;
    }catch(error){
      await adapter.fail(attempt.id);
      throw error;
    }
  };
  const poll=async(body)=>{
    const id=body?.request_id, proof=body?.poll_secret;
    if(typeof id!=='string'||!/^[a-f0-9]{64}$/.test(id)||
       typeof proof!=='string'||!/^[a-f0-9]{64}$/.test(proof))
      throw oauthFail(400,'Solicitação OAuth inválida');
    // Adapter enforces proof, expiration and single-use consumption in DB.
    return adapter.poll(id,digest(proof),clock());
  };
  return {start,callback,poll};
}
