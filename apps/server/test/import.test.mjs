import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {spawnSync} from 'node:child_process';
import {scryptSync,randomUUID} from 'node:crypto';
import pg from 'pg';

test('SQLite snapshot import preserves records and refuses nonempty target', {timeout:30000},async t=>{
  if(!process.env.DATABASE_URL)throw Error('DATABASE_URL must be set');
  const dir=mkdtempSync(join(tmpdir(),'veylor-import-'));
  const source=join(dir,'veylor.sqlite');
  const sqlite=new DatabaseSync(source);
  t.after(()=>{try{sqlite.close();}catch{}rmSync(dir,{recursive:true,force:true});});
  sqlite.exec([
    'PRAGMA foreign_keys=ON;',
    'CREATE TABLE users(id TEXT PRIMARY KEY,username TEXT NOT NULL UNIQUE,password_hash TEXT NOT NULL,created_at TEXT NOT NULL);',
    'CREATE TABLE sessions(token_hash TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),expires_at INTEGER NOT NULL);',
    'CREATE TABLE servers(id TEXT PRIMARY KEY,name TEXT NOT NULL,owner_id TEXT NOT NULL REFERENCES users(id),created_at TEXT NOT NULL);',
    'CREATE TABLE members(server_id TEXT NOT NULL REFERENCES servers(id),user_id TEXT NOT NULL REFERENCES users(id),role TEXT NOT NULL,PRIMARY KEY(server_id,user_id));',
    'CREATE TABLE channels(id TEXT PRIMARY KEY,server_id TEXT NOT NULL REFERENCES servers(id),name TEXT NOT NULL,type TEXT NOT NULL);',
    'CREATE TABLE messages(id INTEGER PRIMARY KEY AUTOINCREMENT,channel_id TEXT NOT NULL REFERENCES channels(id),author_id TEXT NOT NULL REFERENCES users(id),content TEXT NOT NULL,created_at TEXT NOT NULL);',
    'CREATE TABLE invites(code TEXT PRIMARY KEY,server_id TEXT NOT NULL REFERENCES servers(id),created_by TEXT NOT NULL REFERENCES users(id),expires_at INTEGER NOT NULL);',
    'CREATE TABLE direct_threads(id TEXT PRIMARY KEY,user_a TEXT NOT NULL REFERENCES users(id),user_b TEXT NOT NULL REFERENCES users(id),created_at TEXT NOT NULL);',
    'CREATE TABLE direct_messages(id INTEGER PRIMARY KEY AUTOINCREMENT,thread_id TEXT NOT NULL REFERENCES direct_threads(id),author_id TEXT NOT NULL REFERENCES users(id),content TEXT NOT NULL,created_at TEXT NOT NULL);'
  ].join('\n'));
  const alice=randomUUID(),bob=randomUUID(),sid=randomUUID(),cid=randomUUID(),dm=randomUUID();
  const timestamp=new Date().toISOString();
  const salt='0123456789abcdef0123456789abcdef';
  const pass=salt+':'+scryptSync('password-for-migrated',salt,64).toString('hex');
  sqlite.prepare('INSERT INTO users VALUES(?,?,?,?)').run(alice,'migrated_test',pass,timestamp);
  sqlite.prepare('INSERT INTO users VALUES(?,?,?,?)').run(bob,'migration_peer',pass,timestamp);
  sqlite.prepare('INSERT INTO servers VALUES(?,?,?,?)').run(sid,'Old server',alice,timestamp);
  sqlite.prepare('INSERT INTO members VALUES(?,?,?)').run(sid,alice,'owner');
  sqlite.prepare('INSERT INTO members VALUES(?,?,?)').run(sid,bob,'member');
  sqlite.prepare('INSERT INTO channels VALUES(?,?,?,?)').run(cid,sid,'geral','text');
  sqlite.prepare('INSERT INTO messages VALUES(?,?,?,?,?)').run(41,cid,alice,'historic-message',timestamp);
  sqlite.prepare('INSERT INTO direct_threads VALUES(?,?,?,?)').run(dm,...[alice,bob].sort(),timestamp);
  sqlite.prepare('INSERT INTO direct_messages VALUES(?,?,?,?,?)').run(71,dm,bob,'historic-DM',timestamp);
  const script=resolve('apps/server/scripts/import-sqlite.mjs');
  const run=()=>spawnSync(process.execPath,[script,'--confirm',source],{
    cwd:resolve('.'),env:{...process.env},encoding:'utf8',timeout:20000
  });
  const result=run();
  assert.equal(result.status,0,'import failed: '+result.stderr);
  const pool=new pg.Pool({connectionString:process.env.DATABASE_URL});
  try{
    const users=await pool.query('SELECT username FROM users WHERE id=$1',[alice]);
    assert.equal(users.rows[0].username,'migrated_test');
    const msgs=await pool.query('SELECT content FROM messages WHERE id=41');
    assert.equal(msgs.rows[0].content,'historic-message');
    const dms=await pool.query('SELECT content FROM direct_messages WHERE id=71');
    assert.equal(dms.rows[0].content,'historic-DM');
    const inserted=await pool.query('INSERT INTO messages(channel_id,author_id,content,created_at) VALUES($1,$2,$3,$4) RETURNING id',[cid,alice,'new-message',timestamp]);
    assert.equal(Number(inserted.rows[0].id),42,'sequence should follow imported IDs');
    const again=run();
    assert.notEqual(again.status,0,'import must fail when target is not empty');
    const count=await pool.query('SELECT COUNT(*)::int AS n FROM users');
    assert.equal(count.rows[0].n,2,'refused import must not modify target');
  }finally{await pool.end();}
});
