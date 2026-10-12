import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';

test('Android update manifest is public and uses trusted HTTPS download', {timeout:15000},async t=>{
  const dir=mkdtempSync(path.join(tmpdir(),'veylor-updates-'));
  const port=25000+Math.floor(Math.random()*15000);
  const child=spawn(process.execPath,['server.mjs'],{cwd:path.resolve('apps/server'),
    env:{...process.env,HOST:'127.0.0.1',PORT:String(port),VEYLOR_DB_PATH:path.join(dir,'db.sqlite')},
    stdio:['ignore','pipe','pipe']});
  t.after(()=>{child.kill();rmSync(dir,{recursive:true,force:true});});
  const root='http://127.0.0.1:'+port;
  let ready=false;
  for(let i=0;i<100;i++){
    if(child.exitCode!==null)break;
    try{ready=(await fetch(root+'/health')).ok;if(ready)break;}catch{}
    await new Promise(r=>setTimeout(r,80));
  }
  assert.equal(ready,true,'API failed to start');
  const result=await fetch(root+'/api/updates/android');
  assert.equal(result.status,200);
  const data=await result.json();
  assert.equal(data.platform,'android');
  assert.equal(data.channel,'beta');
  assert.ok(Number.isSafeInteger(data.build)&&data.build>0);
  const uri=new URL(data.download_url);
  assert.equal(uri.protocol,'https:');
  assert.equal(uri.hostname,'github.com');
  assert.match(uri.pathname,/^\/Night0231-creator\/discord2\/actions\/runs\/\d+$/);
  assert.equal(data.installation,'manual');
  const win=await fetch(root+'/api/updates/windows');
  assert.equal(win.status,200);
  const windows=await win.json();
  assert.equal(windows.schema,1);
  assert.equal(windows.platform,'windows');
  assert.equal(windows.channel,'beta');
  assert.ok(Number.isSafeInteger(windows.build)&&windows.build>0);
  assert.equal(windows.installation,'manual');
  const source=new URL(windows.download_url);
  assert.equal(source.protocol,'https:');
  assert.equal(source.hostname,'github.com');
  assert.match(source.pathname,/^\/Night0231-creator\/discord2\/(?:actions\/runs\/\d+|releases\/tag\/v\d+\.\d+\.\d+-beta)$/);
  const missing=await fetch(root+'/api/updates/ios');
  assert.equal(missing.status,401);
});
