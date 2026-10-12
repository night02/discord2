import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { once } from 'node:events';

test('autenticação, isolamento, convites, mensagens e controles LiveKit', {timeout:20000}, async t => {
  const dir=mkdtempSync(path.join(tmpdir(),'veylor-'));
  const port=18000+Math.floor(Math.random()*20000);
  const server=spawn(process.execPath,['server.mjs'],{
    cwd: path.resolve('apps/server'),
    env:{...process.env,HOST:'127.0.0.1',PORT:String(port),VEYLOR_DB_PATH:path.join(dir,'test.sqlite')},
    stdio:['ignore','pipe','pipe']
  });
  t.after(()=>{server.kill();rmSync(dir,{recursive:true,force:true});});
  const base=`http://127.0.0.1:${port}`;
  let started=false;
  for(let i=0;i<100;i++){
    if(server.exitCode!==null) break;
    try { const r=await fetch(base+'/health');if(r.ok){started=true;break;} }catch{}
    await new Promise(r=>setTimeout(r,80));
  }
  assert.equal(started,true,'servidor deveria iniciar');
  const req=async (route,{method='GET',body,token}={})=>{
    const r=await fetch(base+route,{method,headers:{...(body?{'Content-Type':'application/json'}:{}),...(token?{Authorization:'Bearer '+token}:{})},body:body?JSON.stringify(body):undefined});
    return {status:r.status,...await r.json()};
  };
  const a=await req('/api/register',{method:'POST',body:{username:'alice_test',password:'senha-super-segura-123'}});
  assert.equal(a.status,201);
  const b=await req('/api/register',{method:'POST',body:{username:'bob_test',password:'outra-senha-segura-456'}});
  assert.equal(b.status,201);
  const logged=await req('/api/login',{method:'POST',body:{username:'alice_test',password:'senha-super-segura-123'}});
  assert.equal(logged.status,200);
  const channels=await req('/api/servers/'+a.server.id+'/channels',{token:a.token});
  const textChannel=channels.channels.find(c=>c.type==='text');
  const voiceChannel=channels.channels.find(c=>c.type==='voice');
  assert.ok(textChannel && voiceChannel);
  assert.equal((await req('/api/channels/'+textChannel.id+'/messages',{token:b.token})).status,403);
  assert.equal((await req('/api/media/token',{method:'POST',token:b.token,body:{channel_id:voiceChannel.id}})).status,403);
  const invite=await req('/api/servers/'+a.server.id+'/invites',{method:'POST',token:a.token});
  assert.equal(invite.status,201);
  assert.equal((await req('/api/invites/'+invite.code+'/join',{method:'POST',token:b.token})).status,200);
  const msg=await req('/api/channels/'+textChannel.id+'/messages',{method:'POST',token:b.token,body:{content:'Olá Veylor'}});
  assert.equal(msg.status,201);
  const list=await req('/api/channels/'+textChannel.id+'/messages',{token:a.token});
  assert.equal(list.messages[0].content,'Olá Veylor');
  assert.equal((await req('/api/media/token',{method:'POST',token:b.token,body:{channel_id:voiceChannel.id}})).status,503);
  assert.equal((await req('/api/channels/'+textChannel.id+'/messages',{token:'a'.repeat(64)})).status,401);
  assert.equal((await req('/api/logout',{method:'POST',token:b.token})).status,200);
  assert.equal((await req('/api/me',{token:b.token})).status,401);
});
