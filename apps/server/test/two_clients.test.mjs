import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { once } from 'node:events';
import WebSocket from 'ws';

test('two independent clients receive chat/DM events but outsiders do not', {timeout:25000}, async t=>{
  const dir=mkdtempSync(path.join(tmpdir(),'veylor-two-clients-'));
  const port=22000+Math.floor(Math.random()*25000);
  const proc=spawn(process.execPath,['server.mjs'],{
    cwd:path.resolve('apps/server'), env:{...process.env,PORT:String(port),HOST:'127.0.0.1',VEYLOR_DB_PATH:path.join(dir,'db.sqlite')},
    stdio:['ignore','pipe','pipe']
  });
  t.after(()=>{proc.kill();rmSync(dir,{recursive:true,force:true});});
  const base='http://127.0.0.1:'+port;
  let started=false;
  for(let i=0;i<100;i++){
    if(proc.exitCode!==null)break;
    try{started=(await fetch(base+'/health')).ok;if(started)break;}catch{}
    await new Promise(r=>setTimeout(r,70));
  }
  assert.equal(started,true,'server must start');
  const api=async(route,method='GET',token,body)=>{
    const result=await fetch(base+route,{method,
      headers:{...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},
      body:body?JSON.stringify(body):undefined});
    return {status:result.status,...await result.json()};
  };
  const alice=await api('/api/register','POST',null,{username:'user_a_02',password:'password-for-user-a'});
  const bob=await api('/api/register','POST',null,{username:'user_b_02',password:'password-for-user-b'});
  const outsider=await api('/api/register','POST',null,{username:'outsider_02',password:'password-for-user-c'});
  for(const account of [alice,bob,outsider])assert.equal(account.status,201);
  const connect=async account=>{
    const ws=new WebSocket('ws://127.0.0.1:'+port+'/api/realtime',{headers:{Authorization:'Bearer '+account.token}});
    t.after(()=>ws.terminate());
    const events=[];
    ws.on('message',data=>events.push(JSON.parse(String(data))));
    await Promise.race([once(ws,'open'),new Promise((_,reject)=>setTimeout(()=>reject(Error('WebSocket timeout')),3000))]);
    return {ws,events};
  };
  const a=await connect(alice),b=await connect(bob),c=await connect(outsider);
  const wait=async (events,kind)=>{
    for(let i=0;i<80;i++){
      if(events.some(e=>e.type===kind))return;
      await new Promise(r=>setTimeout(r,20));
    }
    assert.fail('Missing event '+kind);
  };
  const invite=await api('/api/servers/'+alice.server.id+'/invites','POST',alice.token,{});
  assert.equal(invite.status,201);
  assert.equal((await api('/api/invites/'+invite.code+'/join','POST',bob.token,{})).status,200);
  const channels=await api('/api/servers/'+alice.server.id+'/channels','GET',bob.token);
  assert.equal(channels.status,200);
  const chatId=channels.channels.find(x=>x.type==='text')?.id;
  assert.ok(chatId);
  assert.equal((await api('/api/channels/'+chatId+'/messages','POST',alice.token,{content:'ola para dois clientes'})).status,201);
  await wait(b.events,'channel.message');
  assert.equal(c.events.some(x=>x.type==='channel.message'),false);
  assert.equal((await api('/api/channels/'+chatId+'/messages','GET',bob.token)).messages[0].content,'ola para dois clientes');
  assert.equal((await api('/api/channels/'+chatId+'/messages','GET',outsider.token)).status,403);
  const dm=await api('/api/dms','POST',bob.token,{username:'user_a_02'});
  assert.equal(dm.status,200);
  assert.equal((await api('/api/dms/'+dm.thread.id+'/messages','POST',bob.token,{content:'mensagem privada'})).status,201);
  await wait(a.events,'dm.message');
  assert.equal(c.events.some(x=>x.type==='dm.message'),false);
  assert.equal((await api('/api/dms/'+dm.thread.id+'/messages','GET',alice.token)).messages[0].content,'mensagem privada');
  assert.equal((await api('/api/dms/'+dm.thread.id+'/messages','GET',outsider.token)).status,403);
});
