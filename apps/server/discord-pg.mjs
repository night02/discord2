import {one,query,transaction} from './pg-db.mjs';
import {randomUUID,randomBytes,createServer,createSession,now} from './pg-common.mjs';
import {oauthFail} from './discord-oauth.mjs';

// DB-backed OAuth state survives a Render process restart or multiple workers.
export function pgDiscordAdapter() {
  return {
    async createAttempt(a) {
      await query('DELETE FROM discord_oauth_attempts WHERE expires_at<$1',Date.now()-60000);
      await query(
        "INSERT INTO discord_oauth_attempts(id,state_hash,proof_hash,status,expires_at) VALUES($1,$2,$3,'pending',$4)",
        a.id,a.stateHash,a.proofHash,a.expiresAt);
    },
    async claimState(stateHash,at) {
      return one(
        "UPDATE discord_oauth_attempts SET status='processing' WHERE state_hash=$1 AND status='pending' AND expires_at>$2 RETURNING id",
        stateHash,at);
    },
    async identityUser(discordId) {
      return transaction(async client=>{
        // Serialize account creation across concurrent callbacks for this Discord user.
        await client.query('SELECT pg_advisory_xact_lock(hashtext($1))',[discordId]);
        const found=(await client.query('SELECT user_id FROM discord_accounts WHERE discord_id=$1',[discordId])).rows[0];
        if(found)return found.user_id;
        const id=randomUUID(),username='discord_'+randomBytes(8).toString('hex');
        await client.query('INSERT INTO users(id,username,password_hash,created_at) VALUES($1,$2,$3,$4)',
          [id,username,'discord-only',now()]);
        await client.query('INSERT INTO discord_accounts(discord_id,user_id) VALUES($1,$2)',[discordId,id]);
        await createServer(client,id,'Meu servidor');
        return id;
      });
    },
    async finish(attemptId,userId){
      await query("UPDATE discord_oauth_attempts SET status='ready',user_id=$2 WHERE id=$1 AND status='processing'",
        attemptId,userId);
    },
    async fail(attemptId){
      await query("UPDATE discord_oauth_attempts SET status='failed' WHERE id=$1 AND status='processing'",attemptId);
    },
    async poll(id,proofHash,at){
      return transaction(async client=>{
        const row=(await client.query(
          'SELECT status,user_id,expires_at,proof_hash FROM discord_oauth_attempts WHERE id=$1 FOR UPDATE',
          [id])).rows[0];
        if(!row||row.proof_hash!==proofHash||Number(row.expires_at)<=at)
          throw oauthFail(401,'Solicitação OAuth inválida ou expirada');
        if(row.status==='failed')throw oauthFail(401,'Login Discord não autorizado');
        if(row.status!=='ready')return{status:'pending'};
        // Delete before creating a token, in the same transaction, prevents replay.
        await client.query('DELETE FROM discord_oauth_attempts WHERE id=$1',[id]);
        const token=await createSession(client,row.user_id);
        const user=(await client.query('SELECT id,username FROM users WHERE id=$1',[row.user_id])).rows[0];
        return {status:'ready',token,user};
      });
    }
  };
}
