import {discordConfiguration} from './discord-oauth.mjs';

// Return only feature readiness flags. Never include IDs, URLs, access tokens,
// API keys or secret values in diagnostics.
export function liveKitReady(env=process.env) {
  if(typeof env.LIVEKIT_API_KEY!=='string' || !env.LIVEKIT_API_KEY.trim() ||
     typeof env.LIVEKIT_API_SECRET!=='string' || !env.LIVEKIT_API_SECRET.trim())return false;
  if(typeof env.LIVEKIT_URL!=='string')return false;
  try{
    const u=new URL(env.LIVEKIT_URL);
    return u.protocol==='wss:' && !!u.hostname && !u.username && !u.password &&
      !u.hash && !u.search && (u.pathname==='/'||u.pathname==='') &&
      !u.port;
  }catch{return false;}
}

export function integrationStatus(env=process.env) {
  let discord=false;
  try{discordConfiguration(env);discord=true;}catch{}
  return {
    discord:{configured:discord},
    livekit:{configured:liveKitReady(env)}
  };
}
