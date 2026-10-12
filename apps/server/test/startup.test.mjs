import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';

test('staging refuses to boot without a configured Postgres database',()=>{
  const result=spawnSync(process.execPath,['server.mjs'],{
    cwd:resolve('apps/server'),
    env:{...process.env,REQUIRE_POSTGRES:'1',DATABASE_URL:''},
    encoding:'utf8',timeout:8000
  });
  assert.notEqual(result.status,0);
  assert.match(result.stderr,/PostgreSQL obrigatório/);
});
test('staging rejects non-Postgres connection URLs',()=>{
  const result=spawnSync(process.execPath,['server.mjs'],{
    cwd:resolve('apps/server'),
    env:{...process.env,REQUIRE_POSTGRES:'1',DATABASE_URL:'https://example.invalid/a'},
    encoding:'utf8',timeout:8000
  });
  assert.notEqual(result.status,0);
  assert.match(result.stderr,/DATABASE_URL deve ser uma conexão PostgreSQL válida/);
});
