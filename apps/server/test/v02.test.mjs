import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { once } from 'node:events';
import WebSocket from 'ws';

test('V0.2: private DMs, roles, channels and authenticated WS', {timeout:25000}, async t => {
  const dir=mkdtempSync(path.join(tmpdir(),'veylor-v02-'));
  const port=19000+Math.floor(Math.random()*20000);
  const child=spawn(process.execPath,['server.mjs'],{
    cwd:path.resolve('apps/server'),
    env:{...process.env,HOST:'127.0.0.1',PORT:String(port),VEYLOR_DB_PATH:path.join(dir,'db.sqlite')},
    stdio:['ignore','pipe','pipe']
  });
  t.after(()=>{child.kill();rmSync(dir,{recursive:true,force:true});});
  const base='http://127.0.0.1:'+port;
  let ready=false;
  for(let i=0;i<100;i++){
    if(child.exitCode!==null)break;
    try{ready=(await fetch(base+'/health')).ok;if(ready)break;}catch{}
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  assert.equal(ready,true,'API should start');
  const req=async(route,method='GET',body,token)=>{
    const r=await fetch(base+route,{method,headers:{
      ...(token?{Authorization:'Bearer '+token}:{}),
      ...(body?{'Content-Type':'application/json'}:{})
    },body:body?JSON.stringify(body):undefined});
    return {status:r.status,...await r.json()};
  };
  const a=await req('/api/register','POST',{username:'owner_v02',password:'owner-password-789'});
  const b=await req('/api/register','POST',{username:'member_v02',password:'member-password-789'});
  const c=await req('/api/register','POST',{username:'outsider_v02',password:'outsider-password-789'});
  assert.equal(a.status,201);
  assert.equal(b.status,201);
  assert.equal(c.status,201);
  const ws=new WebSocket('ws://127.0.0.1:'+port+'/api/realtime',{headers:{Authorization:'Bearer '+b.token}});
  t.after(()=>ws.terminate());
  await Promise.race([once(ws,'open'),new Promise((_,reject)=>setTimeout(()=>reject(Error('WS timed out')),3500))]);
  const received=[];
  ws.on('message',data=>received.push(JSON.parse(String(data))));
  assert.equal((await req('/api/dms','POST',{username:'owner_v02'},b.token)).status,200);
  const list=await req('/api/dms','GET',null,a.token);
  const dm=list.threads[0];
  assert.ok(dm?.id);
  assert.equal((await req('/api/dms/'+dm.id+'/messages','GET',null,c.token)).status,403);
  assert.equal((await req('/api/dms/'+dm.id+'/messages','POST',{content:'Oi da DM'},b.token)).status,201);
  const dmRead=await req('/api/dms/'+dm.id+'/messages','GET',null,a.token);
  assert.equal(dmRead.messages[0].content,'Oi da DM');
  assert.equal((await req('/api/dms/'+dm.id+'/messages','POST',{content:'sem permissão'},c.token)).status,403);
  assert.equal((await req('/api/servers/'+a.server.id+'/channels','POST',{name:'admins',type:'text'},b.token)).status,403);
  const invite=await req('/api/servers/'+a.server.id+'/invites','POST',{},a.token);
  assert.equal((await req('/api/invites/'+invite.code+'/join','POST',{},b.token)).status,200);
  const badPatch=await req('/api/servers/'+a.server.id+'/members/'+a.user.id,'PATCH',{role:'member'},b.token);
  assert.equal(badPatch.status,403);
  assert.equal((await req('/api/servers/'+a.server.id+'/members/'+b.user.id,'PATCH',{role:'moderator'},a.token)).status,200);
  const ch=await req('/api/servers/'+a.server.id+'/channels','POST',{name:'novidades',type:'text'},b.token);
  assert.equal(ch.status,201);
  assert.equal((await req('/api/servers/'+a.server.id+'/members','GET',null,c.token)).status,403);
  assert.equal((await req('/api/servers/'+a.server.id+'/channels/'+ch.channel.id,'DELETE',null,c.token)).status,403);
  assert.equal((await req('/api/servers/'+a.server.id+'/channels/'+ch.channel.id,'DELETE',null,b.token)).status,200);
  await new Promise(resolve=>setTimeout(resolve,100));
  assert.ok(received.some(e=>e.type==='server.updated'),'member should receive membership/channel notices');
  assert.equal((await req('/api/logout','POST',{},b.token)).status,200);
  const closed=await Promise.race([once(ws,'close').then(()=>true),new Promise(resolve=>setTimeout(()=>resolve(false),2500))]);
  assert.equal(closed,true,'logout should invalidate realtime socket');
});
