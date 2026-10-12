import {randomUUID,randomBytes} from 'node:crypto';
import {oauthFail} from './discord-oauth.mjs';

export function sqliteDiscordAdapter(db,{now,newServer,issueToken}) {
  function tx(fn) {
    db.exec('BEGIN IMMEDIATE');
    try {const v=fn();db.exec('COMMIT');return v;}
    catch(e){db.exec('ROLLBACK');throw e;}
  }
  return {
    createAttempt:async a=>{
      db.prepare('DELETE FROM discord_oauth_attempts WHERE expires_at<?').run(Date.now()-60000);
      db.prepare("INSERT INTO discord_oauth_attempts(id,state_hash,proof_hash,status,expires_at) VALUES(?,?,?,'pending',?)")
        .run(a.id,a.stateHash,a.proofHash,a.expiresAt);
    },
    claimState:async(stateHash,at)=>
      db.prepare("UPDATE discord_oauth_attempts SET status='processing' WHERE state_hash=? AND status='pending' AND expires_at>? RETURNING id")
        .get(stateHash,at),
    identityUser:async discordId=>tx(()=>{
      const exists=db.prepare('SELECT user_id FROM discord_accounts WHERE discord_id=?').get(discordId);
      if(exists)return exists.user_id;
      const id=randomUUID(), username='discord_'+randomBytes(8).toString('hex');
      db.prepare('INSERT INTO users VALUES(?,?,?,?)').run(id,username,'discord-only',now());
      db.prepare('INSERT INTO discord_accounts(discord_id,user_id) VALUES(?,?)').run(discordId,id);
      newServer(id,'Meu servidor');
      return id;
    }),
    finish:async(id,userId)=>{
      db.prepare("UPDATE discord_oauth_attempts SET status='ready',user_id=? WHERE id=? AND status='processing'").run(userId,id);
    },
    fail:async id=>{
      db.prepare("UPDATE discord_oauth_attempts SET status='failed' WHERE id=? AND status='processing'").run(id);
    },
    poll:async(id,proofHash,at)=>tx(()=>{
      const row=db.prepare('SELECT status,user_id,expires_at,proof_hash FROM discord_oauth_attempts WHERE id=?').get(id);
      if(!row||row.proof_hash!==proofHash||row.expires_at<=at)
        throw oauthFail(401,'Solicitação OAuth inválida ou expirada');
      if(row.status==='failed')throw oauthFail(401,'Login Discord não autorizado');
      if(row.status!=='ready')return{status:'pending'};
      db.prepare('DELETE FROM discord_oauth_attempts WHERE id=?').run(id);
      const token=issueToken(row.user_id);
      const user=db.prepare('SELECT id,username FROM users WHERE id=?').get(row.user_id);
      return {status:'ready',token,user};
    })
  };
}
