import {createHmac} from 'node:crypto';
import {liveKitReady} from './integration-readiness.mjs';
const fail=(status,message)=>Object.assign(new Error(message),{status});
const encode=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
// Call only after authenticating and resolving the channel through membership.
export function issueMediaAccess(user,channel,{env=process.env,at=Date.now()}={}){
  if(!user?.id || !user?.username || !channel?.id || channel.type!=='voice')throw fail(400,'Entre em um canal de voz');
  if(!liveKitReady(env))throw fail(503,'LiveKit ainda não configurado no servidor');
  const issued=Math.floor(at/1000);
  const payload={iss:env.LIVEKIT_API_KEY,sub:user.id,name:user.username,iat:issued,nbf:issued-5,exp:issued+3600,
    video:{room:'veylor-'+channel.id,roomJoin:true,canPublish:true,canSubscribe:true,canPublishData:false,
      canPublishSources:['microphone','camera','screen_share','screen_share_audio']}};
  const unsigned=encode({alg:'HS256',typ:'JWT'})+'.'+encode(payload);
  return {url:env.LIVEKIT_URL,token:unsigned+'.'+createHmac('sha256',env.LIVEKIT_API_SECRET).update(unsigned).digest('base64url')};
}
