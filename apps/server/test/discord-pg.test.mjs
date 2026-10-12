import test from 'node:test';
import assert from 'node:assert/strict';
import {ensureSchema,pool,one} from '../pg-db.mjs';
import {createDiscordOAuth} from '../discord-oauth.mjs';
import {pgDiscordAdapter} from '../discord-pg.mjs';

test('PostgreSQL: Discord OAuth preserves accounts, consumes session only once', {timeout:30000}, async()=>{
  await ensureSchema();
  const env={
    DISCORD_CLIENT_ID:'123456789012345678',
    DISCORD_CLIENT_SECRET:'fake_discord_secret_only_test',
    DISCORD_REDIRECT_URI:'https://veylor.example.com/api/auth/discord/callback'
  };
  const discordId='246813579135792468';
  const mockedFetch=async url=>{
    if(url==='https://discord.com/api/oauth2/token')
      return new Response(JSON.stringify({access_token:'test-only-token-12345678901234567890'}),{status:200});
    if(url==='https://discord.com/api/users/@me')
      return new Response(JSON.stringify({id:discordId,username:'test_user'}),{status:200});
    throw new Error('Unexpected request');
  };
  try{
    const oauth=createDiscordOAuth(pgDiscordAdapter(),{env,fetchImpl:mockedFetch});
    const begin=await oauth.start();
    const pending=await oauth.poll({request_id:begin.request_id,poll_secret:begin.poll_secret});
    assert.equal(pending.status,'pending');
    await assert.rejects(oauth.poll({request_id:begin.request_id,poll_secret:'f'.repeat(64)}));
    const state=new URL(begin.url).searchParams.get('state');
    assert.equal(await oauth.callback(new URL(`${env.DISCORD_REDIRECT_URI}?state=${state}&code=authorization-from-discord`)),true);
    const result=await oauth.poll({request_id:begin.request_id,poll_secret:begin.poll_secret});
    assert.equal(result.status,'ready');
    assert.match(result.token,/^[a-f0-9]{64}$/);
    const account=await one('SELECT user_id FROM discord_accounts WHERE discord_id=$1',discordId);
    assert.equal(result.user.id,account.user_id);
    await assert.rejects(oauth.poll({request_id:begin.request_id,poll_secret:begin.poll_secret}));
    const again=await oauth.start();
    const newState=new URL(again.url).searchParams.get('state');
    await oauth.callback(new URL(`${env.DISCORD_REDIRECT_URI}?state=${newState}&code=authorization-from-discord`));
    const current=await oauth.poll({request_id:again.request_id,poll_secret:again.poll_secret});
    assert.equal(result.user.id,current.user.id);
  } finally {
    await pool.end();
  }
});
