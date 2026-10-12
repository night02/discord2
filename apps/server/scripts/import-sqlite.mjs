// One-time offline migration: requires a CONSISTENT SQLite snapshot and an EMPTY PostgreSQL DB.
// Never run against the live Render SQLite file while users are writing data.
import {DatabaseSync} from 'node:sqlite';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';
import {Pool} from 'pg';
import {pool,ensureSchema} from '../pg-db.mjs';

const tables=[
  ['users',['id','username','password_hash','created_at']],
  ['sessions',['token_hash','user_id','expires_at']],
  ['servers',['id','name','owner_id','created_at']],
  ['members',['server_id','user_id','role']],
  ['channels',['id','server_id','name','type']],
  ['messages',['id','channel_id','author_id','content','created_at']],
  ['invites',['code','server_id','created_by','expires_at']],
  ['direct_threads',['id','user_a','user_b','created_at']],
  ['direct_messages',['id','thread_id','author_id','content','created_at']]
];
const args=process.argv.slice(2);
const pathArg=args.find(arg=>arg!=='--confirm');
if(!args.includes('--confirm') || !pathArg || !process.env.DATABASE_URL){
  console.error('Usage: DATABASE_URL=postgres://... node scripts/import-sqlite.mjs --confirm /absolute/path/to/snapshot.sqlite');
  process.exitCode=2;
}else{
  const path=resolve(pathArg);
  if(!existsSync(path)){
    console.error('SQLite snapshot does not exist');
    process.exitCode=2;
  }else{
    const sqlite=new DatabaseSync(path,{readOnly:true});
    const client=await pool.connect();
    try{
      const integrity=sqlite.prepare('PRAGMA integrity_check').all();
      if(integrity.length!==1 || integrity[0].integrity_check!=='ok')
        throw Error('SQLite snapshot failed integrity_check');
      await ensureSchema();
      await client.query('BEGIN');
      // Require ALL tables to be empty so source IDs, sessions, and messages cannot conflict.
      for(const [name] of tables){
        const check=await client.query('SELECT COUNT(*)::int AS count FROM '+name);
        if(check.rows[0].count!==0)throw Error('Target database is NOT empty: '+name);
      }
      const counts={};
      for(const [name,columns]of tables){
        const rows=sqlite.prepare('SELECT '+columns.join(',')+' FROM '+name).all();
        const placeholders=columns.map((_,i)=>'$'+(i+1)).join(',');
        const query='INSERT INTO '+name+' ('+columns.join(',')+') VALUES ('+placeholders+')';
        for(const row of rows)await client.query(query,columns.map(col=>row[col]));
        counts[name]=rows.length;
        const stored=await client.query('SELECT COUNT(*)::int AS count FROM '+name);
        if(stored.rows[0].count!==rows.length)throw Error('Record count mismatch in '+name);
      }
      // Update generated identity counters for imported legacy message IDs.
      for(const table of ['messages','direct_messages']){
        const seq=await client.query('SELECT pg_get_serial_sequence($1,$2) AS sequence',[table,'id']);
        const stats=await client.query('SELECT COALESCE(MAX(id),0)::bigint AS last,COUNT(*)::int AS count FROM '+table);
        await client.query('SELECT setval($1::regclass,$2::bigint,$3)',[
          seq.rows[0].sequence,Math.max(Number(stats.rows[0].last),1),stats.rows[0].count>0
        ]);
      }
      await client.query('COMMIT');
      console.log('Migration completed; imported row counts:',JSON.stringify(counts));
    }catch(err){
      try{await client.query('ROLLBACK');}catch{}
      console.error('Migration aborted:',err.message);
      process.exitCode=1;
    }finally{
      client.release();
      sqlite.close();
      await pool.end();
    }
  }
}
