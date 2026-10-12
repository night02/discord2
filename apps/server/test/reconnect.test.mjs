import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {randomBytes} from 'node:crypto';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import WebSocket from 'ws';

test('two independent clients recover missed messages after a dropped socket; repeated sends are idempotent', {timeout:30000}, async t=>{
  const dir=mkdtempSync(path.join(tmpdir(),'veylor-resume-'));
  const port=21000+Math.floor(Math.random()*15000);
  const proc=spawn(process.execPath,['server.mjs'],{
    cwd:path.resolve('apps/server'),
    env:{...process.env,DATABASE_URL:'',PORT:String(port),HOST:'127.0.0.1',VEYLOR_DB_PATH:path.join(dir,'data.sqlite')},
    stdio:['ignore','pipe','pipe']
  });
  t.after(()=>{proc.kill();rmSync(dir,{recursive:true,force:true});});
  const base='http://127.0.0.1:'+port;
  let ready=false;
  for(let attempt=0;attempt<100;attempt++){
    if(proc.exitCode!==null)break;
    try{ready=(await fetch(base+'/health')).ok;if(ready)break;}catch{}
    await new Promise(r=>setTimeout(r,75));
  }
  assert.equal(ready,true);
  const request=async(route,method='GET',token,payload)=>{
    const response=await fetch(base+route,{method,headers:{
      ...(token?{Authorization:'Bearer '+token}:{}),
      ...(payload?{'Content-Type':'application/json'}:{})
    },body:payload?JSON.stringify(payload):undefined});
    return {status:response.status,...await response.json()};
  };
  const suffix=randomBytes(4).toString('hex');
  const alice=await request('/api/register','POST',null,{username:'alice_'+suffix,password:'stablepassword123'});
  const bob=await request('/api/register','POST',null,{username:'bob_'+suffix,password:'stablepassword123'});
  const stranger=await request('/api/register','POST',null,{username:'str_'+suffix,password:'stablepassword123'});
  for(const u of [alice,bob,stranger])assert.equal(u.status,201);
  const invite=await request('/api/servers/'+alice.server.id+'/invites','POST',alice.token,{});
  assert.equal((await request('/api/invites/'+invite.code+'/join','POST',bob.token,{})).status,200);
  const channels=await request('/api/servers/'+alice.server.id+'/channels','GET',alice.token);
  const channel=channels.channels.find(x=>x.type==='text').id;
  const connect=async(token)=>{
    const ws=new WebSocket(base.replace('http:','ws:')+'/api/realtime',{
      headers:{Authorization:'Bearer '+token}
    });
    t.after(()=>ws.terminate());
    await Promise.race([once(ws,'open'),new Promise((_,reject)=>setTimeout(()=>reject(Error('WebSocket open timed out')),3000))]);
    return ws;
  };
  const bobSocket=await connect(bob.token);
  bobSocket.terminate(); // forced mobile network loss, not an intentional logout
  const firstKey=randomBytes(16).toString('hex');
  const first=await request('/api/channels/'+channel+'/messages','POST',alice.token,{content:'first',client_nonce:firstKey});
  const duplicate=await request('/api/channels/'+channel+'/messages','POST',alice.token,{content:'first',client_nonce:firstKey});
  assert.equal(first.status,201);
  assert.equal(duplicate.status,200);
  assert.equal(duplicate.duplicate,true);
  assert.equal(duplicate.message.id,first.message.id);
  assert.equal((await request('/api/channels/'+channel+'/messages','POST',alice.token,{content:'changed',client_nonce:firstKey})).status,409);
  assert.equal((await request('/api/channels/'+channel+'/messages','POST',alice.token,{content:'bad key',client_nonce:'oops'})).status,400);
  // A second desktop keeps sending while Bob's mobile is offline.
  for(let i=0;i<105;i++){
    const sent=await request('/api/channels/'+channel+'/messages','POST',alice.token,{
      content:'offline-'+i,client_nonce:randomBytes(16).toString('hex')
    });
    assert.equal(sent.status,201,'offline batch '+i);
  }
  const bobReconnected=await connect(bob.token);
  assert.equal(bobReconnected.readyState,WebSocket.OPEN);
  // Mobile catches up over REST after the new socket is connected, with pagination.
  const collected=[];let after=0;
  for(let page=0;page<4;page++){
    const result=await request('/api/channels/'+channel+'/messages?after='+after,'GET',bob.token);
    assert.equal(result.status,200);
    collected.push(...result.messages);
    if(result.messages.length<100)break;
    after=result.messages.at(-1).id;
  }
  assert.equal(collected.length,106);
  assert.equal(new Set(collected.map(x=>x.id)).size,106);
  assert.equal(collected[0].content,'first');
  assert.equal(collected.at(-1).content,'offline-104');
  assert.equal((await request('/api/channels/'+channel+'/messages','GET',stranger.token)).status,403);
  const dm=await request('/api/dms','POST',bob.token,{username:alice.user.username});
  assert.equal(dm.status,200);
  const dmKey=randomBytes(16).toString('hex');
  const d1=await request('/api/dms/'+dm.thread.id+'/messages','POST',bob.token,{content:'safe DM',client_nonce:dmKey});
  const d2=await request('/api/dms/'+dm.thread.id+'/messages','POST',bob.token,{content:'safe DM',client_nonce:dmKey});
  assert.equal(d1.status,201);
  assert.equal(d2.status,200);
  assert.equal(d1.message.id,d2.message.id);
  assert.equal((await request('/api/dms/'+dm.thread.id+'/messages','GET',stranger.token)).status,403);
  assert.equal((await request('/api/dms/'+dm.thread.id+'/messages','GET',alice.token)).messages.length,1);
  await request('/api/logout','POST',bob.token,{});
  assert.equal((await request('/api/dms','GET',bob.token)).status,401);
  bobReconnected.terminate();
});
