import http from 'node:http';
import { randomBytes, createHash, createHmac, scryptSync, timingSafeEqual, randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { createV02 } from './v02.mjs';

// Public update metadata points only to already-built, manually verified beta artifacts.
const androidRelease = JSON.parse(readFileSync(new URL('./mobile-release.json', import.meta.url),'utf8'));
const windowsRelease = JSON.parse(readFileSync(new URL('./windows-release.json', import.meta.url),'utf8'));
const port = Number(process.env.PORT || 8080);
const host = process.env.HOST || '127.0.0.1';
const databaseFile = path.resolve(process.env.VEYLOR_DB_PATH || './data/veylor.sqlite');
mkdirSync(path.dirname(databaseFile), { recursive: true });
const db = new DatabaseSync(databaseFile);
db.exec(`PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE COLLATE NOCASE, password_hash TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS sessions (token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, expires_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS servers (id TEXT PRIMARY KEY, name TEXT NOT NULL, owner_id TEXT NOT NULL REFERENCES users(id), created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS members (server_id TEXT NOT NULL REFERENCES servers(id) ON DELETE CASCADE, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, role TEXT NOT NULL DEFAULT 'member', PRIMARY KEY(server_id,user_id));
CREATE TABLE IF NOT EXISTS channels (id TEXT PRIMARY KEY, server_id TEXT NOT NULL REFERENCES servers(id) ON DELETE CASCADE, name TEXT NOT NULL, type TEXT NOT NULL CHECK(type IN ('text','voice')));
CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY AUTOINCREMENT, channel_id TEXT NOT NULL REFERENCES channels(id) ON DELETE CASCADE, author_id TEXT NOT NULL REFERENCES users(id), content TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS invites (code TEXT PRIMARY KEY, server_id TEXT NOT NULL REFERENCES servers(id) ON DELETE CASCADE, created_by TEXT NOT NULL REFERENCES users(id), expires_at INTEGER NOT NULL); `);
// Non-destructive migration for existing local SQLite installations.
if(!db.prepare('PRAGMA table_info(messages)').all().some(c=>c.name==='client_nonce'))
  db.exec('ALTER TABLE messages ADD COLUMN client_nonce TEXT');
db.exec('CREATE UNIQUE INDEX IF NOT EXISTS messages_nonce_idx ON messages(channel_id,author_id,client_nonce)');
const now = () => new Date().toISOString();
const sha256 = value => createHash('sha256').update(value).digest('hex');
const passwordHash = password => {
  const salt = randomBytes(16).toString('hex');
  return salt + ':' + scryptSync(password, salt, 64).toString('hex');
};
const passwordMatch = (password, saved) => {
  if (!saved || !saved.includes(':')) return false;
  const [salt, expected] = saved.split(':');
  const got = scryptSync(password, salt, 64);
  const expectedBytes = Buffer.from(expected, 'hex');
  return got.length === expectedBytes.length && timingSafeEqual(got, expectedBytes);
};
const json = (res, status, payload) => {
  res.writeHead(status, {
    'Content-Type':'application/json; charset=utf-8',
    'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff',
    'Referrer-Policy':'no-referrer'
  });
  res.end(JSON.stringify(payload));
};
const fail = (status, message) => Object.assign(new Error(message), { status });
const requestBody = async req => {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 65536) throw fail(413, 'Corpo da requisição muito grande');
    chunks.push(chunk);
  }
  try {
    const parsed = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object') throw Error();
    return parsed;
  } catch { throw fail(400, 'JSON inválido'); }
};
const sessionUser = req => {
  const match = /^Bearer ([a-f0-9]{64})$/.exec(req.headers.authorization || '');
  if (!match) throw fail(401, 'Faça login para continuar');
  const user = db.prepare(`SELECT u.id, u.username FROM sessions s JOIN users u ON u.id=s.user_id
    WHERE s.token_hash=? AND s.expires_at>?`).get(sha256(match[1]), Date.now());
  if (!user) throw fail(401, 'Sessão inválida ou expirada');
  return user;
};
const membership = (userId, serverId) => {
  const member = db.prepare('SELECT role FROM members WHERE server_id=? AND user_id=?').get(serverId,userId);
  if (!member) throw fail(403, 'Sem acesso a este servidor');
  return member;
};
const accessibleChannel = (userId, channelId) => {
  const channel = db.prepare('SELECT id,server_id,name,type FROM channels WHERE id=?').get(channelId);
  if (!channel) throw fail(404, 'Canal não encontrado');
  membership(userId,channel.server_id);
  return channel;
};
const newServer = (ownerId, name) => {
  const id = randomUUID();
  db.prepare('INSERT INTO servers VALUES (?,?,?,?)').run(id,name,ownerId,now());
  db.prepare('INSERT INTO members(server_id,user_id,role) VALUES (?,?,?)').run(id,ownerId,'owner');
  for (const [label,type] of [['geral','text'],['bate-papo','voice']]) {
    db.prepare('INSERT INTO channels(id,server_id,name,type) VALUES (?,?,?,?)').run(randomUUID(),id,label,type);
  }
  return {id,name};
};
const rate = new Map();
const limit = (req, category, max) => {
  const addr = req.socket.remoteAddress || 'unknown';
  const key = addr + ':' + category;
  const current = Date.now();
  const slot = rate.get(key);
  if (!slot || current-slot.start>60_000) {
    rate.set(key,{ start:current,count:1 });
  } else if (++slot.count>max) {
    throw fail(429, 'Muitas tentativas. Aguarde um minuto');
  }
  if (rate.size>5000) for (const [k,v] of rate) if (current-v.start>60_000) rate.delete(k);
};
const issueToken = userId => {
  const token = randomBytes(32).toString('hex');
  db.prepare('INSERT INTO sessions VALUES (?,?,?)').run(sha256(token),userId,Date.now()+7*86400_000);
  return token;
};
const b64 = obj => Buffer.from(JSON.stringify(obj)).toString('base64url');
const mediaToken = (user, room) => {
  const issued = Math.floor(Date.now()/1000);
  const payload = { iss:process.env.LIVEKIT_API_KEY,sub:user.id,name:user.username,
    iat:issued,nbf:issued-5,exp:issued+3600,
    video:{room,roomJoin:true,canPublish:true,canSubscribe:true} };
  const unsigned = b64({alg:'HS256',typ:'JWT'}) + '.' + b64(payload);
  return unsigned + '.' + createHmac('sha256', process.env.LIVEKIT_API_SECRET).update(unsigned).digest('base64url');
};

const v02 = createV02({ db, sessionUser, membership, limit, fail, json, requestBody, now });

export const app = http.createServer(async (req,res) => {
  try {
    const uri = new URL(req.url || '/', 'http://localhost');
    const pathname = uri.pathname;
    const method = req.method;
    if (method==='GET' && pathname==='/health') return json(res,200,{status:'ok',app:'Veylor'});
    if (method==='GET' && pathname==='/api/updates/android') return json(res,200,androidRelease);
    if (method==='GET' && pathname==='/api/updates/windows') return json(res,200,windowsRelease);
    if (method==='POST' && pathname==='/api/register') {
      limit(req,'auth',10);
      const {username,password} = await requestBody(req);
      if (typeof username!=='string' || !/^[a-zA-Z0-9_]{3,24}$/.test(username))
        throw fail(400,'Usuário: 3 a 24 letras, números ou _');
      if (typeof password!=='string' || password.length<10 || password.length>128)
        throw fail(400,'A senha precisa de 10 a 128 caracteres');
      const id = randomUUID();
      try {
        db.prepare('INSERT INTO users VALUES (?,?,?,?)').run(id,username,passwordHash(password),now());
      } catch (error) {
        if (String(error).includes('UNIQUE')) throw fail(409,'Nome de usuário indisponível');
        throw error;
      }
      const server = newServer(id,'Meu servidor');
      return json(res,201,{token:issueToken(id),user:{id,username},server});
    }
    if (method==='POST' && pathname==='/api/login') {
      limit(req,'auth',10);
      const {username,password}=await requestBody(req);
      if (typeof username!=='string' || typeof password!=='string') throw fail(400,'Credenciais inválidas');
      const user=db.prepare('SELECT * FROM users WHERE username=?').get(username);
      if (!user || !passwordMatch(password,user.password_hash)) throw fail(401,'Usuário ou senha incorretos');
      return json(res,200,{token:issueToken(user.id),user:{id:user.id,username:user.username}});
    }

    const user=sessionUser(req);
    if (await v02.route(req,res,user,pathname,method,uri)) return;
    if (method==='GET' && pathname==='/api/me') return json(res,200,{user});
    if (method==='POST' && pathname==='/api/logout') {
      const token=req.headers.authorization.slice(7);
      db.prepare('DELETE FROM sessions WHERE token_hash=?').run(sha256(token));
      v02.disconnectToken(token);
      return json(res,200,{ok:true});
    }
    if (method==='GET' && pathname==='/api/servers') {
      const servers=db.prepare(`SELECT s.id,s.name,m.role FROM servers s JOIN members m ON s.id=m.server_id
        WHERE m.user_id=? ORDER BY s.created_at ASC`).all(user.id);
      return json(res,200,{servers});
    }
    if (method==='POST' && pathname==='/api/servers') {
      limit(req,'server',12);
      const {name}=await requestBody(req);
      if (typeof name!=='string' || name.trim().length<2 || name.length>50) throw fail(400,'Nome do servidor inválido');
      return json(res,201,{server:newServer(user.id,name.trim())});
    }
    const channelList=/^\/api\/servers\/([a-f0-9-]+)\/channels$/.exec(pathname);
    if (channelList && method==='GET') {
      membership(user.id,channelList[1]);
      const channels=db.prepare('SELECT id,name,type FROM channels WHERE server_id=? ORDER BY type,name').all(channelList[1]);
      return json(res,200,{channels});
    }
    const inviteCreate=/^\/api\/servers\/([a-f0-9-]+)\/invites$/.exec(pathname);
    if (inviteCreate && method==='POST') {
      limit(req,'invite',20);
      const member=membership(user.id,inviteCreate[1]);
      if (member.role!=='owner') throw fail(403,'Apenas o proprietário pode criar convites nesta versão');
      const code=randomBytes(12).toString('base64url');
      db.prepare('INSERT INTO invites VALUES (?,?,?,?)').run(code,inviteCreate[1],user.id,Date.now()+7*86400_000);
      return json(res,201,{code,expires_in_days:7});
    }
    const inviteJoin=/^\/api\/invites\/([a-zA-Z0-9_-]+)\/join$/.exec(pathname);
    if (inviteJoin && method==='POST') {
      limit(req,'join',30);
      const invite=db.prepare('SELECT * FROM invites WHERE code=? AND expires_at>?').get(inviteJoin[1],Date.now());
      if (!invite) throw fail(404,'Convite inválido ou expirado');
      db.prepare('INSERT OR IGNORE INTO members(server_id,user_id,role) VALUES (?,?,?)').run(invite.server_id,user.id,'member');
      v02.notifyServer(invite.server_id);
      return json(res,200,{server_id:invite.server_id});
    }
    const messages=/^\/api\/channels\/([a-f0-9-]+)\/messages$/.exec(pathname);
    if (messages && (method==='GET'||method==='POST')) {
      const channel=accessibleChannel(user.id,messages[1]);
      if (channel.type!=='text') throw fail(400,'Este não é um canal de texto');
      if (method==='GET') {
        const after=Number(uri.searchParams.get('after')||'0');
        if (!Number.isSafeInteger(after) || after<0) throw fail(400,'Cursor inválido');
        const rows=db.prepare(`SELECT msg.id,msg.content,msg.created_at,usr.username
          FROM messages msg JOIN users usr ON usr.id=msg.author_id
          WHERE msg.channel_id=? AND msg.id>?
          ORDER BY msg.id ASC LIMIT 100`).all(channel.id,after);
        return json(res,200,{messages:rows});
      }
      limit(req,'message',120);
      const payload=await requestBody(req);
      const {content}=payload,nonce=payload.client_nonce??null;
      if (typeof content!=='string' || content.trim().length===0 || content.length>4000)
        throw fail(400,'Mensagem inválida (máximo 4000 caracteres)');
      if (nonce!==null&&(typeof nonce!=='string'||!/^[a-f0-9]{32}$/.test(nonce)))
        throw fail(400,'Identificador de mensagem inválido');
      const created_at=now(),body=content.trim();
      const inserted=db.prepare('INSERT INTO messages(channel_id,author_id,content,created_at,client_nonce) VALUES (?,?,?,?,?) ON CONFLICT(channel_id,author_id,client_nonce) DO NOTHING RETURNING id,content,created_at')
        .get(channel.id,user.id,body,created_at,nonce);
      const record=inserted??db.prepare('SELECT id,content,created_at FROM messages WHERE channel_id=? AND author_id=? AND client_nonce=?')
        .get(channel.id,user.id,nonce);
      if(!record)throw fail(503,'Não foi possível confirmar a mensagem');
      if(record.content!==body)throw fail(409,'Identificador já usado em outra mensagem');
      if(inserted)v02.notifyChannel(channel.id, channel.server_id);
      return json(res,inserted?201:200,{message:{id:Number(record.id),content:record.content,username:user.username,created_at:record.created_at},duplicate:!inserted});
    }
    if (method==='POST' && pathname==='/api/media/token') {
      const {channel_id}=await requestBody(req);
      if (typeof channel_id!=='string') throw fail(400,'Canal inválido');
      const channel=accessibleChannel(user.id,channel_id);
      if (channel.type!=='voice') throw fail(400,'Entre em um canal de voz');
      const {LIVEKIT_URL,LIVEKIT_API_KEY,LIVEKIT_API_SECRET}=process.env;
      if (!LIVEKIT_URL||!LIVEKIT_API_KEY||!LIVEKIT_API_SECRET) throw fail(503,'LiveKit ainda não configurado no servidor');
      if (!/^wss:\/\//.test(LIVEKIT_URL)) throw fail(503,'LiveKit precisa de uma URL segura wss://');
      return json(res,200,{url:LIVEKIT_URL,token:mediaToken(user,'veylor-'+channel.id)});
    }
    throw fail(404,'Rota não encontrada');
  } catch (error) {
    const status=Number.isInteger(error.status)?error.status:500;
    if(status===500) console.error(error);
    if(!res.headersSent) json(res,status,{error:status===500?'Erro interno do servidor':error.message});
  }
});

v02.attach(app);

if (true) {
  app.listen(port,host,()=>console.log(`Veylor API ouvindo em http://${host}:${port}`));
}
