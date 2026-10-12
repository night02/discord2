import {randomUUID,randomBytes,createHash,scryptSync,timingSafeEqual,createHmac} from 'node:crypto';
import {one,rows,query,transaction} from './pg-db.mjs';

export {randomUUID,randomBytes,one,rows,query,transaction};
export const now=()=>new Date().toISOString();
export const sha=t=>createHash('sha256').update(t).digest('hex');
export const fail=(status,message)=>Object.assign(new Error(message),{status});
export const json=(res,status,data)=>{
  res.writeHead(status,{'Content-Type':'application/json; charset=utf-8',
    'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'});
  res.end(JSON.stringify(data));
};
export const body=async req=>{
  const chunks=[];let size=0;
  for await(const buf of req){
    size+=buf.length;if(size>65536)throw fail(413,'Corpo da requisição muito grande');
    chunks.push(buf);
  }
  try{
    const data=JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if(!data||Array.isArray(data)||typeof data!=='object')throw Error();
    return data;
  }catch{throw fail(400,'JSON inválido');}
};
export const passwordHash=p=>{
  const salt=randomBytes(16).toString('hex');
  return salt+':'+scryptSync(p,salt,64).toString('hex');
};
export const passwordMatch=(p,s)=>{
  if(!s||!s.includes(':'))return false;
  const[salt,encoded]=s.split(':');
  const actual=scryptSync(p,salt,64);
  const expected=Buffer.from(encoded,'hex');
  return actual.length===expected.length&&timingSafeEqual(actual,expected);
};
export const createSession=async(client,id)=>{
  const t=randomBytes(32).toString('hex');
  await client.query('INSERT INTO sessions VALUES($1,$2,$3)',[sha(t),id,Date.now()+604800000]);
  return t;
};
export const sessionUser=async req=>{
  const match=/^Bearer ([a-f0-9]{64})$/.exec(req.headers.authorization||'');
  if(!match)throw fail(401,'Faça login para continuar');
  const u=await one('SELECT u.id,u.username FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=$1 AND s.expires_at>$2',sha(match[1]),Date.now());
  if(!u)throw fail(401,'Sessão inválida ou expirada');
  return u;
};
export const memberRole=async(uid,sid)=>{
  const r=await one('SELECT role FROM members WHERE user_id=$1 AND server_id=$2',uid,sid);
  if(!r)throw fail(403,'Sem acesso ao servidor');
  return r.role;
};
export const requireAdmin=async(uid,sid,ownerOnly=false)=>{
  const role=await memberRole(uid,sid);
  if(ownerOnly?role!=='owner':!['owner','moderator'].includes(role))throw fail(403,'Permissão insuficiente');
  return role;
};
export const channelFor=async(uid,cid)=>{
  const c=await one('SELECT id,server_id,name,type FROM channels WHERE id=$1',cid);
  if(!c)throw fail(404,'Canal não encontrado');
  await memberRole(uid,c.server_id);
  return c;
};
export const threadFor=async(uid,id)=>{
  const t=await one('SELECT * FROM direct_threads WHERE id=$1',id);
  if(!t)throw fail(404,'Conversa não encontrada');
  if(t.user_a!==uid&&t.user_b!==uid)throw fail(403,'Conversa privada');
  return t;
};
export const checkedNonce=value=>{
  if(value===undefined||value===null)return null;
  if(typeof value!=='string'||!/^[a-f0-9]{32}$/.test(value))
    throw fail(400,'Identificador de mensagem inválido');
  return value;
};
export const checkedMessage=content=>{
  if(typeof content!=='string'||content.trim().length===0||content.length>4000)
    throw fail(400,'Mensagem inválida (máximo 4000 caracteres)');
  return content.trim();
};
export const afterCursor=url=>{
  const s=url.searchParams.get('after')||'0';
  const n=Number(s);
  if(!/^\d{1,16}$/.test(s)||!Number.isSafeInteger(n)||n<0)
    throw fail(400,'Cursor inválido');
  return n;
};
const limits=new Map();
export const limit=(req,type,max)=>{
  const key=(req.socket.remoteAddress||'unknown')+':'+type;
  const at=Date.now();const v=limits.get(key);
  if(!v||at-v.at>60000)limits.set(key,{at,count:1});
  else if(++v.count>max)throw fail(429,'Muitas tentativas. Aguarde um minuto');
  if(limits.size>5000)for(const[k,slot]of limits)if(at-slot.at>60000)limits.delete(k);
};
export const createServer=async(client,uid,name)=>{
  const sid=randomUUID();
  await client.query('INSERT INTO servers VALUES($1,$2,$3,$4)',[sid,name,uid,now()]);
  await client.query("INSERT INTO members VALUES($1,$2,'owner')",[sid,uid]);
  await client.query("INSERT INTO channels VALUES($1,$2,'geral','text')",[randomUUID(),sid]);
  await client.query("INSERT INTO channels VALUES($1,$2,'bate-papo','voice')",[randomUUID(),sid]);
  return{id:sid,name};
};
const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
export const mediaToken=(u,room)=>{
  const t=Math.floor(Date.now()/1000);
  const payload={iss:process.env.LIVEKIT_API_KEY,sub:u.id,name:u.username,iat:t,nbf:t-5,exp:t+3600,
    video:{room,roomJoin:true,canPublish:true,canSubscribe:true}};
  const unsigned=enc({alg:'HS256',typ:'JWT'})+'.'+enc(payload);
  return unsigned+'.'+createHmac('sha256',process.env.LIVEKIT_API_SECRET).update(unsigned).digest('base64url');
};
