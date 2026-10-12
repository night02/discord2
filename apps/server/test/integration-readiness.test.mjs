import test from 'node:test';
import assert from 'node:assert/strict';
import {integrationStatus,liveKitReady} from '../integration-readiness.mjs';

const discord={
  DISCORD_CLIENT_ID:'123456789012345678',
  DISCORD_CLIENT_SECRET:'private-only-test-secret',
  DISCORD_REDIRECT_URI:'https://veylor-postgres-staging.onrender.com/api/auth/discord/callback'
};
const livekit={
  LIVEKIT_URL:'wss://veylor-livekit.example.com',
  LIVEKIT_API_KEY:'local-test-key',
  LIVEKIT_API_SECRET:'local-test-secret'
};

test('staging readiness stays false until BOTH integrations are configured',()=>{
  assert.deepEqual(integrationStatus({}),{
    discord:{configured:false},livekit:{configured:false}
  });
  assert.deepEqual(integrationStatus(discord),{
    discord:{configured:true},livekit:{configured:false}
  });
  assert.deepEqual(integrationStatus(livekit),{
    discord:{configured:false},livekit:{configured:true}
  });
});

test('readiness does not disclose credentials, callback URLs or user data',()=>{
  const report=integrationStatus({...discord,...livekit});
  assert.deepEqual(report,{discord:{configured:true},livekit:{configured:true}});
  const output=JSON.stringify(report);
  for(const forbidden of Object.values({...discord,...livekit})){
    assert.equal(output.includes(forbidden),false);
  }
});

test('LiveKit fails closed for insecure and malformed media URLs',()=>{
  for(const value of [
    'ws://veylor-livekit.example.com',
    'https://veylor-livekit.example.com',
    'wss://user:password@veylor-livekit.example.com',
    'wss://veylor-livekit.example.com/?secret=test',
    'wss://veylor-livekit.example.com/path',
    'wss://veylor-livekit.example.com/#hash',
    'wss://veylor-livekit.example.com:5000',
    'not a URL',
    ''
  ]){
    assert.equal(liveKitReady({...livekit,LIVEKIT_URL:value}),false,value);
  }
  assert.equal(liveKitReady({...livekit,LIVEKIT_API_SECRET:''}),false);
  assert.equal(liveKitReady({...livekit,LIVEKIT_API_KEY:''}),false);
  assert.equal(liveKitReady(livekit),true);
});

test('Discord readiness requires a valid HTTPS callback on the OAuth route',()=>{
  for(const redirect of [
    'http://veylor-postgres-staging.onrender.com/api/auth/discord/callback',
    'https://veylor-postgres-staging.onrender.com/api/auth/discord/not-callback',
    'https://veylor-postgres-staging.onrender.com/api/auth/discord/callback?code=secret'
  ]){
    assert.equal(integrationStatus({...discord,DISCORD_REDIRECT_URI:redirect})
      .discord.configured,false);
  }
});
