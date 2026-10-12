import http from 'node:http';
import {readFileSync} from 'node:fs';
import {
  one,rows,query,transaction,randomUUID,randomBytes,sha,now,fail,json,body,
  passwordHash,passwordMatch,createSession,sessionUser,memberRole,requireAdmin,
  createServer,channelFor,checkedMessage,checkedNonce,afterCursor,limit,mediaToken
} from './pg-common.mjs';
import {pool,ensureSchema} from './pg-db.mjs';
import {attachRealtime,disconnectToken,notifyServer,notifyChannel} from './pg-realtime.mjs';
import {extraRoutes} from './pg-routes.mjs';

const release=JSON.parse(readFileSync(new URL('./mobile-release.json',import.meta.url),'utf8'));
const windowsRelease=JSON.parse(readFileSync(new URL('./windows-release.json',import.meta.url),'utf8'));
export const app=http.createServer(async(req,res)=>{
  try{
    const url=new URL(req.url||'/','http://localhost'),route=url.pathname,m=req.method;
    if(m==='GET'&&route==='/health'){
      await query('SELECT 1');
      return json(res,200,{status:'ok',app:'Veylor',storage:'postgres'});
    }
    if(m==='GET'&&route==='/api/updates/android')return json(res,200,release);
    if(m==='GET'&&route==='/api/updates/windows')return json(res,200,windowsRelease);
    if(m==='POST'&&route==='/api/register'){
      limit(req,'auth',10);
      const {username,password}=await body(req);
      if(typeof username!=='string'||!/^[a-zA-Z0-9_]{3,24}$/.test(username))
        throw fail(400,'Usuário: 3 a 24 letras, números ou _');
      if(typeof password!=='string'||password.length<10||password.length>128)
        throw fail(400,'Senha precisa de 10 a 128 caracteres');
      const id=randomUUID();
      const data=await transaction(async c=>{
        await c.query('INSERT INTO users VALUES($1,$2,$3,$4)',
          [id,username,passwordHash(password),now()]);
        const server=await createServer(c,id,'Meu servidor');
        const token=await createSession(c,id);
        return {token,user:{id,username},server};
      });
      return json(res,201,data);
    }
    if(m==='POST'&&route==='/api/login'){
      limit(req,'auth',10);
      const {username,password}=await body(req);
      if(typeof username!=='string'||typeof password!=='string')
        throw fail(400,'Credenciais inválidas');
      const record=await one('SELECT * FROM users WHERE lower(username)=lower($1)',username);
      if(!record||!passwordMatch(password,record.password_hash))
        throw fail(401,'Usuário ou senha incorretos');
      const token=await transaction(c=>createSession(c,record.id));
      return json(res,200,{token,user:{id:record.id,username:record.username}});
    }

    const user=await sessionUser(req);
    if(await extraRoutes(req,res,user,route,m,url))return;
    if(m==='GET'&&route==='/api/me')return json(res,200,{user});
    if(m==='POST'&&route==='/api/logout'){
      const t=req.headers.authorization.slice(7);
      await query('DELETE FROM sessions WHERE token_hash=$1',sha(t));
      disconnectToken(t);
      return json(res,200,{ok:true});
    }
    if(m==='GET'&&route==='/api/servers'){
      const servers=await rows(
        'SELECT s.id,s.name,m.role FROM servers s JOIN members m ON m.server_id=s.id WHERE m.user_id=$1 ORDER BY s.created_at',
        user.id);
      return json(res,200,{servers});
    }
    if(m==='POST'&&route==='/api/servers'){
      limit(req,'server',12);
      const {name}=await body(req);
      if(typeof name!=='string'||name.trim().length<2||name.length>50)
        throw fail(400,'Nome do servidor inválido');
      const server=await transaction(c=>createServer(c,user.id,name.trim()));
      return json(res,201,{server});
    }
    const channelList=/^\/api\/servers\/([a-f0-9-]+)\/channels$/.exec(route);
    if(channelList&&m==='GET'){
      await memberRole(user.id,channelList[1]);
      const channels=await rows('SELECT id,name,type FROM channels WHERE server_id=$1 ORDER BY type,name',channelList[1]);
      return json(res,200,{channels});
    }
    const inviteCreate=/^\/api\/servers\/([a-f0-9-]+)\/invites$/.exec(route);
    if(inviteCreate&&m==='POST'){
      limit(req,'invite',20);
      await requireAdmin(user.id,inviteCreate[1],true);
      const code=randomBytes(12).toString('base64url');
      await query('INSERT INTO invites VALUES($1,$2,$3,$4)',code,inviteCreate[1],user.id,Date.now()+604800000);
      return json(res,201,{code,expires_in_days:7});
    }
    const inviteJoin=/^\/api\/invites\/([a-zA-Z0-9_-]+)\/join$/.exec(route);
    if(inviteJoin&&m==='POST'){
      limit(req,'join',30);
      const invite=await one('SELECT server_id FROM invites WHERE code=$1 AND expires_at>$2',
        inviteJoin[1],Date.now());
      if(!invite)throw fail(404,'Convite inválido ou expirado');
      await query("INSERT INTO members(server_id,user_id,role) VALUES($1,$2,'member') ON CONFLICT DO NOTHING",
        invite.server_id,user.id);
      await notifyServer(invite.server_id);
      return json(res,200,{server_id:invite.server_id});
    }
    const messages=/^\/api\/channels\/([a-f0-9-]+)\/messages$/.exec(route);
    if(messages&&(m==='GET'||m==='POST')){
      const channel=await channelFor(user.id,messages[1]);
      if(channel.type!=='text')throw fail(400,'Este não é um canal de texto');
      if(m==='GET'){
        const messages=await rows(
          'SELECT msg.id,msg.content,msg.created_at,u.username FROM messages msg JOIN users u ON u.id=msg.author_id WHERE msg.channel_id=$1 AND msg.id>$2 ORDER BY msg.id LIMIT 100',
          channel.id,afterCursor(url));
        return json(res,200,{messages:messages.map(x=>({...x,id:Number(x.id)}))});
      }
      limit(req,'message',120);
      const payload=await body(req);
      const content=checkedMessage(payload.content),nonce=checkedNonce(payload.client_nonce);
      const created_at=now();
      const inserted=await one(
        'INSERT INTO messages(channel_id,author_id,content,created_at,client_nonce) VALUES($1,$2,$3,$4,$5) ON CONFLICT (channel_id,author_id,client_nonce) DO NOTHING RETURNING id,content,created_at',
        channel.id,user.id,content,created_at,nonce);
      const record=inserted??await one(
        'SELECT id,content,created_at FROM messages WHERE channel_id=$1 AND author_id=$2 AND client_nonce=$3',
        channel.id,user.id,nonce);
      if(!record)throw fail(503,'Não foi possível confirmar a mensagem');
      if(record.content!==content)throw fail(409,'Identificador já usado em outra mensagem');
      if(inserted)await notifyChannel(channel.id,channel.server_id);
      return json(res,inserted?201:200,{message:{
        id:Number(record.id),content:record.content,created_at:record.created_at,username:user.username
      },duplicate:!inserted});
    }
    if(m==='POST'&&route==='/api/media/token'){
      const {channel_id}=await body(req);
      if(typeof channel_id!=='string')throw fail(400,'Canal inválido');
      const channel=await channelFor(user.id,channel_id);
      if(channel.type!=='voice')throw fail(400,'Entre em um canal de voz');
      const {LIVEKIT_URL,LIVEKIT_API_KEY,LIVEKIT_API_SECRET}=process.env;
      if(!LIVEKIT_URL||!LIVEKIT_API_KEY||!LIVEKIT_API_SECRET||!LIVEKIT_URL.startsWith('wss://'))
        throw fail(503,'LiveKit ainda não configurado no servidor');
      return json(res,200,{url:LIVEKIT_URL,token:mediaToken(user,'veylor-'+channel.id)});
    }
    throw fail(404,'Rota não encontrada');
  }catch(error){
    let status=Number.isInteger(error.status)?error.status:500;
    if(error.code==='23505')status=409;
    if(error.code==='23503')status=409;
    if(status===500)console.error('Postgres API error',error);
    if(!res.headersSent)json(res,status,{
      error:status===500?'Erro interno do servidor':status===409?'Registro já existe ou vínculo inválido':error.message
    });
  }
});
attachRealtime(app);
export async function start(){
  await ensureSchema();
  const port=Number(process.env.PORT||8080),host=process.env.HOST||'127.0.0.1';
  await new Promise((resolve,reject)=>{
    app.once('error',reject);
    app.listen(port,host,()=>{
      app.removeListener('error',reject);
      resolve();
    });
  });
  console.log('Veylor Postgres API ready');
}
start().catch(async err=>{
  console.error('PostgreSQL initialization failed:',err.message);
  process.exitCode=1;
  await pool.end();
});
