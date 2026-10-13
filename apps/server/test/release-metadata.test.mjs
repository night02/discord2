import test from 'node:test';
import assert from 'node:assert/strict';
import {createReleaseMetadata} from '../release-metadata.mjs';

const sha='a'.repeat(40);
const tag='v0.4.3-beta.123456';
const page='https://github.com/night02/discord2/releases/tag/'+tag;
const release={draft:false,prerelease:true,tag_name:tag,html_url:page,
  target_commitish:sha,assets:[
    'Veylor-v0.4.3-Setup-Windows-x64.exe','Veylor-v0.4.3-Windows-x64.zip',
    'Veylor-v0.4.3-Linux-x64.tar.gz','Veylor-v0.4.3-Android-debug-TEST-ONLY.apk',
    'SHA256SUMS.txt'
  ].map(name=>({name,size:100}))};
const run={name:'Veylor preview builds',status:'completed',conclusion:'success',
  event:'push',head_branch:'main',head_sha:sha,run_number:97};
const fallback=Object.fromEntries(['android','windows'].map(platform=>[platform,{
  schema:1,platform,version:'0.4.2',build:95,channel:'beta',notes:'Fallback beta',
  download_url:'https://github.com/night02/discord2/releases/tag/v0.4.2-beta.38341839352',
  installation:'manual'
}]));
function client({candidate=release,build=run,clock=()=>1,fail=false}={}){
  const calls=[];
  const metadata=createReleaseMetadata({fallback,enabled:true,clock,
    fetchImpl:async(url,options)=>{
      calls.push({url,options});
      return {ok:!fail,json:async()=>url.includes('/releases?')?[candidate]:build};
    }});
  return {metadata,calls};
}

test('uses the actual package build number, not the large workflow ID',async()=>{
  const {metadata,calls}=client();
  const value=await metadata.get('windows');
  assert.equal(value.build,97);
  assert.equal(value.version,'0.4.3');
  assert.equal(value.download_url,page);
  assert.equal(value.installation,'manual');
  assert.equal(calls.length,2);
  assert.equal(calls[0].options.headers.authorization,undefined);
  assert.ok(calls.every(c=>c.url.startsWith('https://api.github.com/repos/night02/discord2/')));
});

test('simultaneous Windows/Android clients share one refresh and cached snapshot',async()=>{
  const {metadata,calls}=client();
  const values=await Promise.all([metadata.get('windows'),metadata.get('android')]);
  assert.deepEqual(values.map(v=>v.build),[97,97]);
  await metadata.get('windows');
  assert.equal(calls.length,2);
});

test('rejects incomplete, forged-origin and unapproved or foreign builds',async()=>{
  for(const candidate of [
    {...release,html_url:'https://github.com/other/repository/releases/tag/'+tag},
    {...release,assets:release.assets.slice(1)},
    {...release,draft:true}
  ])assert.equal((await client({candidate}).metadata.get('windows')).build,95);
  for(const build of [
    {...run,head_branch:'feature/test'}, {...run,conclusion:'failure'},
    {...run,head_sha:'b'.repeat(40)}, {...run,event:'pull_request'}
  ])assert.equal((await client({build}).metadata.get('windows')).build,95);
});

test('provider outage keeps fallback and backs off rather than retrying per client',async()=>{
  let now=1;
  const {metadata,calls}=client({fail:true,clock:()=>now});
  assert.equal((await metadata.get('android')).version,'0.4.2');
  now=1000;
  await metadata.get('windows');
  assert.equal(calls.length,1);
  now=61001;
  await metadata.get('windows');
  assert.equal(calls.length,2);
});
