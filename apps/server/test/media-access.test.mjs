import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {issueMediaAccess} from '../media-access.mjs';
const env={LIVEKIT_URL:'wss://test.example.com',LIVEKIT_API_KEY:'fixture-api-key',LIVEKIT_API_SECRET:'fixture-private-test-only-key'};
const account={id:'test-account-id',username:'voice_tester'},channel={id:'test-channel-id',type:'voice'};
test('media JWT binds authenticated account, permitted channel, sources and expiry',()=>{
  const at=1770000000000,result=issueMediaAccess(account,channel,{env,at});
  assert.equal(result.url,env.LIVEKIT_URL);
  const [header,body,signature]=result.token.split('.'),payload=JSON.parse(Buffer.from(body,'base64url'));
  assert.equal(signature,createHmac('sha256',env.LIVEKIT_API_SECRET).update(header+'.'+body).digest('base64url'));
  assert.equal(payload.sub,account.id);assert.equal(payload.name,account.username);
  assert.equal(payload.exp-payload.iat,3600);assert.equal(payload.nbf,Math.floor(at/1000)-5);
  assert.equal(payload.video.room,'veylor-'+channel.id);assert.equal(payload.video.canPublish,true);assert.equal(payload.video.canSubscribe,true);
  assert.equal(payload.video.canPublishData,false);
  assert.deepEqual(payload.video.canPublishSources,['microphone','camera','screen_share','screen_share_audio']);
  assert.equal(JSON.stringify(result).includes(env.LIVEKIT_API_SECRET),false);assert.equal('roomAdmin' in payload.video,false);
});
test('text channels, missing account and absent configuration cannot get credentials',()=>{
  assert.throws(()=>issueMediaAccess(account,{...channel,type:'text'},{env}),{status:400});
  assert.throws(()=>issueMediaAccess({},channel,{env}),{status:400});
  assert.throws(()=>issueMediaAccess(account,channel,{env:{}}),{status:503});
  assert.throws(()=>issueMediaAccess(account,channel,{env:{...env,LIVEKIT_URL:'ws://public.example.com'}}),{status:503});
});
test('channel grants never reuse the prior room',()=>{
  const parse=result=>JSON.parse(Buffer.from(result.token.split('.')[1],'base64url')).video.room;
  assert.notEqual(parse(issueMediaAccess(account,channel,{env})),parse(issueMediaAccess(account,{...channel,id:'other-channel'},{env})));
});
