import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import WebSocket from 'ws';
const url=process.env.DATABASE_URL;
if(!url)throw Error('Set DATABASE_URL to a test PostgreSQL database');
test('Postgres: accounts, membership, DMs, realtime, persistence across restart', {timeout:35000},async t=>{
  let child;
  let port;
  const open=async()=>{
    port=26000+Math.floor(Math.random()*16000);
    child=spawn(process.execPath,['server.mjs'],{
      cwd:new URL('..',import.meta.url).pathname,
      env:{...process.env,PORT:String(port),HOST:'127.0.0.1'},
      stdio:['ignore','pipe','pipe']
    });
    const base='http://127.0.0.1:'+port;
    let ready=false;
    for(let i=0;i<120;i++){
      if(child.exitCode!==null)break;
      try{
        const r=await fetch(base+'/health');
        if(r.ok){const v=await r.json();assert.equal(v.storage,'postgres');ready=true;break;}
      }catch{}
      await new Promise(r=>setTimeout(r,75));
    }
    assert.equal(ready,true,'PostgreSQL server should boot');
    return base;
  };
  t.after(()=>child?.kill());
  let base=await open();
  const api=async(path,method='GET',token,body)=>{
    const r=await fetch(base+path,{method,headers:{
      ...(body?{'Content-Type':'application/json'}:{}),
      ...(token?{Authorization:'Bearer '+token}:{})
    },body:body?JSON.stringify(body):undefined});
    return {status:r.status,...await r.json()};
  };
  const suffix=Math.random().toString(36).slice(2,9);
  const alice=await api('/api/register','POST',null,{username:'a_'+suffix,password:'password-for-alice'});
  const bob=await api('/api/register','POST',null,{username:'b_'+suffix,password:'password-for-bob'});
  const third=await api('/api/register','POST',null,{username:'x_'+suffix,password:'password-for-third'});
  for(const u of [alice,bob,third])assert.equal(u.status,201);
  const login=await api('/api/login','POST',null,{username:('A_'+suffix),password:'password-for-alice'});
  assert.equal(login.status,200,'case-insensitive login should work');
  const c=await api('/api/servers/'+alice.server.id+'/channels','GET',alice.token);
  assert.equal(c.status,200);
  const textChannel=c.channels.find(ch=>ch.type==='text')?.id;
  assert.ok(textChannel);
  assert.equal((await api('/api/channels/'+textChannel+'/messages','GET',third.token)).status,403);
  const invite=await api('/api/servers/'+alice.server.id+'/invites','POST',alice.token,{});
  assert.equal(invite.status,201);
  assert.equal((await api('/api/invites/'+invite.code+'/join','POST',bob.token,{})).status,200);
  const ws=new WebSocket(base.replace('http:','ws:')+'/api/realtime',{
    headers:{Authorization:'Bearer '+bob.token}
  });
  t.after(()=>ws.terminate());
  await Promise.race([once(ws,'open'),new Promise((_,rej)=>setTimeout(()=>rej(Error('Socket timeout')),4000))]);
  const ev=[];ws.on('message',d=>ev.push(JSON.parse(String(d))));
  const msg=await api('/api/channels/'+textChannel+'/messages','POST',alice.token,{content:'saved-postgres'});
  assert.equal(msg.status,201);
  const nonce='abcd1234abcd1234abcd1234abcd1234';
  const onceMsg=await api('/api/channels/'+textChannel+'/messages','POST',alice.token,{content:'retry-safe',client_nonce:nonce});
  const repeated=await api('/api/channels/'+textChannel+'/messages','POST',alice.token,{content:'retry-safe',client_nonce:nonce});
  assert.equal(onceMsg.status,201);
  assert.equal(repeated.status,200);
  assert.equal(repeated.message.id,onceMsg.message.id);
  assert.equal(repeated.duplicate,true);
  assert.equal((await api('/api/channels/'+textChannel+'/messages','POST',alice.token,{content:'other payload',client_nonce:nonce})).status,409);
  const read=await api('/api/channels/'+textChannel+'/messages','GET',bob.token);
  assert.equal(read.messages[0].content,'saved-postgres');
  await new Promise(r=>setTimeout(r,100));
  assert.ok(ev.some(e=>e.type==='channel.message'));
  assert.equal((await api('/api/servers/'+alice.server.id+'/channels','POST',bob.token,{name:'novidades',type:'text'})).status,403);
  const dm=await api('/api/dms','POST',bob.token,{username:'a_'+suffix});
  assert.equal(dm.status,200);
  assert.equal((await api('/api/dms/'+dm.thread.id+'/messages','POST',alice.token,{content:'private-pg'})).status,201);
  const dmNonce='abcd1234abcd1234abcd1234abcd0001';
  const initialDm=await api('/api/dms/'+dm.thread.id+'/messages','POST',alice.token,{content:'safe private retry',client_nonce:dmNonce});
  const repeatDm=await api('/api/dms/'+dm.thread.id+'/messages','POST',alice.token,{content:'safe private retry',client_nonce:dmNonce});
  assert.equal(initialDm.status,201);
  assert.equal(repeatDm.status,200);
  assert.equal(initialDm.message.id,repeatDm.message.id);
  assert.equal((await api('/api/dms/'+dm.thread.id+'/messages','GET',bob.token)).messages[0].content,'private-pg');
  assert.equal((await api('/api/dms/'+dm.thread.id+'/messages','GET',third.token)).status,403);
  const role=await api('/api/servers/'+alice.server.id+'/members/'+bob.user.id,'PATCH',alice.token,{role:'moderator'});
  assert.equal(role.status,200);
  const ch=await api('/api/servers/'+alice.server.id+'/channels','POST',bob.token,{name:'news',type:'text'});
  assert.equal(ch.status,201);
  assert.equal((await api('/api/servers/'+alice.server.id+'/channels/'+ch.channel.id,'DELETE',bob.token)).status,200);
  assert.equal((await api('/api/media/token','POST',bob.token,{channel_id:c.channels.find(x=>x.type==='voice').id})).status,503);
  assert.equal((await api('/api/updates/android')).status,200);
  // Mimic replacing a Render instance: the API process is gone, but the database remains.
  ws.terminate();
  child.kill();
  await Promise.race([once(child,'exit'),new Promise(r=>setTimeout(r,3000))]);
  base=await open();
  const persisted=await api('/api/channels/'+textChannel+'/messages','GET',alice.token);
  assert.equal(persisted.status,200);
  assert.equal(persisted.messages[0].content,'saved-postgres');
  assert.equal((await api('/api/login','POST',null,{username:'b_'+suffix,password:'password-for-bob'})).status,200);
});
