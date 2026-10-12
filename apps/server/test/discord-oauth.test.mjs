import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {randomBytes,createHash,randomUUID} from 'node:crypto';
import {createDiscordOAuth,authorizationUrl,discordConfiguration,discordIdentity} from '../discord-oauth.mjs';
import {sqliteDiscordAdapter} from '../discord-sqlite.mjs';

const env={
  DISCORD_CLIENT_ID:'123456789012345678',
  DISCORD_CLIENT_SECRET:'test_secret_never_send_to_client',
  DISCORD_REDIRECT_URI:'https://veylor.example.com/api/auth/discord/callback'
};
const fakeFetch=async(url,options)=>{
  if(url==='https://discord.com/api/oauth2/token'){
    assert.equal(options.method,'POST');
    const body=new URLSearchParams(options.body);
    assert.equal(body.get('client_secret'),env.DISCORD_CLIENT_SECRET);
    assert.equal(body.get('redirect_uri'),env.DISCORD_REDIRECT_URI);
    return new Response(JSON.stringify({access_token:'mock-discord-access-token-1234567890'}),
      {status:200});
  }
  if(url==='https://discord.com/api/users/@me'){
    assert.equal(options.headers.authorization,'Bearer mock-discord-access-token-1234567890');
    return new Response(JSON.stringify({id:'345678901234567890',username:'ExampleDiscord'}),{status:200});
  }
  throw new Error('Unexpected URL');
};

function setup(){
  const db=new DatabaseSync(':memory:');
  db.exec(`
    PRAGMA foreign_keys=ON;
    CREATE TABLE users(id TEXT PRIMARY KEY, username TEXT UNIQUE,password_hash TEXT,created_at TEXT);
    CREATE TABLE sessions(token_hash TEXT PRIMARY KEY,user_id TEXT REFERENCES users(id),expires_at INTEGER);
    CREATE TABLE servers(id TEXT PRIMARY KEY,name TEXT,owner_id TEXT,created_at TEXT);
    CREATE TABLE members(server_id TEXT,user_id TEXT,role TEXT);
    CREATE TABLE channels(id TEXT,server_id TEXT,name TEXT,type TEXT);
    CREATE TABLE discord_accounts(discord_id TEXT PRIMARY KEY,user_id TEXT UNIQUE REFERENCES users(id));
    CREATE TABLE discord_oauth_attempts(id TEXT PRIMARY KEY,state_hash TEXT UNIQUE,proof_hash TEXT,status TEXT,user_id TEXT REFERENCES users(id),expires_at INTEGER);
  `);
  const now=()=>new Date().toISOString();
  const adapter=sqliteDiscordAdapter(db,{
    now,
    newServer:(userId,name)=>{
      const sid=randomUUID();
      db.prepare('INSERT INTO servers VALUES(?,?,?,?)').run(sid,name,userId,now());
      db.prepare("INSERT INTO members VALUES(?,?,'owner')").run(sid,userId);
      return {id:sid,name};
    },
    issueToken:userId=>{
      const token=randomBytes(32).toString('hex');
      const hashed=createHash('sha256').update(token).digest('hex');
      db.prepare('INSERT INTO sessions VALUES(?,?,?)').run(hashed,userId,Date.now()+300000);
      return token;
    },
  });
  let time=Date.now();
  const oauth=createDiscordOAuth(adapter,{env,fetchImpl:fakeFetch,clock:()=>time});
  return {db,oauth,advance:ms=>time+=ms};
}

test('Discord OAuth configuration is HTTPS-only and minimum identify scope',()=>{
  const cfg=discordConfiguration(env);
  const url=new URL(authorizationUrl(cfg,'1'.repeat(64)));
  assert.equal(url.origin,'https://discord.com');
  assert.equal(url.searchParams.get('scope'),'identify');
  assert.equal(url.searchParams.get('state'),'1'.repeat(64));
  assert.ok(!url.searchParams.has('client_secret'));
  assert.throws(()=>discordConfiguration({...env,DISCORD_REDIRECT_URI:'http://evil/a'}));
  assert.throws(()=>discordConfiguration({...env,DISCORD_CLIENT_SECRET:''}));
});

test('identity exchanges code only on official Discord endpoints',async()=>{
  const profile=await discordIdentity('sample-authorization-code',discordConfiguration(env),fakeFetch);
  assert.equal(profile.id,'345678901234567890');
  assert.deepEqual(Object.keys(profile),['id']);
});

test('OAuth requires app-only secret and consumes the session exactly once',async()=>{
  const {oauth,db}=setup();
  try{
    const started=await oauth.start();
    const url=new URL(started.url);
    assert.equal((await oauth.poll({
      request_id:started.request_id,poll_secret:started.poll_secret
    })).status,'pending');
    await assert.rejects(oauth.poll({request_id:started.request_id,
      poll_secret:'0'.repeat(64)}),{status:401});
    const confirmed=await oauth.callback(
      new URL(`${env.DISCORD_REDIRECT_URI}?state=${url.searchParams.get('state')}&code=sample-auth-code`));
    assert.equal(confirmed,true);
    const done=await oauth.poll({request_id:started.request_id,poll_secret:started.poll_secret});
    assert.equal(done.status,'ready');
    assert.match(done.token,/^[a-f0-9]{64}$/);
    assert.equal(done.user.username,'dc_345678901234567890');
    assert.equal(db.prepare('SELECT COUNT(*) AS count FROM discord_accounts').get().count,1);
    assert.equal(db.prepare('SELECT COUNT(*) AS count FROM servers').get().count,1);
    await assert.rejects(oauth.poll({
      request_id:started.request_id,poll_secret:started.poll_secret
    }),{status:401});
    // Logging in again uses the already linked account instead of duplicating it.
    const next=await oauth.start();
    await oauth.callback(new URL(`${env.DISCORD_REDIRECT_URI}?state=${new URL(next.url).searchParams.get('state')}&code=sample-auth-code`));
    const again=await oauth.poll({request_id:next.request_id,poll_secret:next.poll_secret});
    assert.equal(again.user.id,done.user.id);
    assert.equal(db.prepare('SELECT COUNT(*) AS count FROM users').get().count,1);
  }finally{db.close();}
});

test('forged, denied, expired or replayed browser callbacks are rejected',async()=>{
  const {oauth,db,advance}=setup();
  try{
    const s=await oauth.start();
    const state=new URL(s.url).searchParams.get('state');
    await assert.rejects(oauth.callback(new URL(`${env.DISCORD_REDIRECT_URI}?state=${'f'.repeat(64)}&code=valid-auth-code`)));
    await assert.rejects(oauth.callback(new URL(`${env.DISCORD_REDIRECT_URI}?state=${state}&error=access_denied`)),{status:400});
    await assert.rejects(oauth.poll({request_id:s.request_id,poll_secret:s.poll_secret}),{status:401});
    await assert.rejects(oauth.callback(new URL(`${env.DISCORD_REDIRECT_URI}?state=${state}&code=valid-auth-code`)));
    const t=await oauth.start();
    advance(300001);
    await assert.rejects(oauth.poll({request_id:t.request_id,poll_secret:t.poll_secret}),{status:401});
    await assert.rejects(oauth.callback(new URL(`${env.DISCORD_REDIRECT_URI}?state=${new URL(t.url).searchParams.get('state')}&code=valid-auth-code`)));
  }finally{db.close();}
});
