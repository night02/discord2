import { randomUUID, createHash } from 'node:crypto';
import { WebSocketServer, WebSocket } from 'ws';

export function createV02({db,sessionUser,membership,limit,fail,json,requestBody,now}) {
  db.exec("CREATE TABLE IF NOT EXISTS direct_threads (id TEXT PRIMARY KEY, user_a TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, user_b TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, created_at TEXT NOT NULL, UNIQUE(user_a,user_b));" +
    "CREATE TABLE IF NOT EXISTS direct_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, thread_id TEXT NOT NULL REFERENCES direct_threads(id) ON DELETE CASCADE, author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, content TEXT NOT NULL, created_at TEXT NOT NULL);" +
    "CREATE INDEX IF NOT EXISTS idx_direct_thread_messages ON direct_messages(thread_id,id);" +
    "CREATE INDEX IF NOT EXISTS idx_channel_messages ON messages(channel_id,id);");
  if(!db.prepare('PRAGMA table_info(direct_messages)').all().some(c=>c.name==='client_nonce'))
    db.exec('ALTER TABLE direct_messages ADD COLUMN client_nonce TEXT');
  db.exec('CREATE UNIQUE INDEX IF NOT EXISTS direct_messages_nonce_idx ON direct_messages(thread_id,author_id,client_nonce)');
  const sockets=new Map();
  const wss=new WebSocketServer({noServer:true,maxPayload:4096,perMessageDeflate:false});
  const sha=x=>createHash('sha256').update(x).digest('hex');
  const valid=entry=> {
    const s=db.prepare('SELECT expires_at FROM sessions WHERE token_hash=?').get(entry.hash);
    return s && s.expires_at>Date.now();
  };
  const send=(id,data)=>{
    for(const entry of sockets.get(id)||[]) {
      if(!valid(entry)) {entry.ws.close(1008,'Sessão expirada');continue;}
      if(entry.ws.readyState===WebSocket.OPEN) {
        if(entry.ws.bufferedAmount>262144) {entry.ws.terminate();continue;}
        entry.ws.send(JSON.stringify(data));
      }
    }
  };
  const notifyServer=id=>{
    for(const m of db.prepare('SELECT user_id FROM members WHERE server_id=?').all(id))
      send(m.user_id,{type:'server.updated',server_id:id});
  };
  const notifyChannel=(channelId,serverId)=>{
    for(const m of db.prepare('SELECT user_id FROM members WHERE server_id=?').all(serverId))
      send(m.user_id,{type:'channel.message',channel_id:channelId});
  };
  const disconnectToken=token=>{
    for(const group of sockets.values())for(const entry of group)
      if(entry.hash===sha(token))entry.ws.close(1008,'Sessão encerrada');
  };
  const admin=(id,sid,owner=false)=>{
    const role=membership(id,sid).role;
    if(owner?role!=='owner':!['owner','moderator'].includes(role))
      throw fail(403,'Permissão insuficiente');
    return role;
  };
  const thread=(uid,id)=>{
    const t=db.prepare('SELECT * FROM direct_threads WHERE id=?').get(id);
    if(!t)throw fail(404,'Conversa não encontrada');
    if(t.user_a!==uid && t.user_b!==uid)throw fail(403,'Conversa privada');
    return t;
  };
  const cursor=uri=>{
    const value=uri.searchParams.get('after')||'0';
    if(!/^\d{1,16}$/.test(value)||!Number.isSafeInteger(Number(value)))throw fail(400,'Cursor inválido');
    return Number(value);
  };
  const bodyText=body=>{
    if(typeof body.content!=='string'||!body.content.trim()||body.content.length>4000)
      throw fail(400,'Mensagem inválida');
    return body.content.trim();
  };
  async function route(req,res,user,path,method,uri) {
    if(method==='GET'&&path==='/api/dms') {
      const rows=db.prepare("SELECT t.id, CASE WHEN t.user_a=? THEN b.username ELSE a.username END username, " +
        "CASE WHEN t.user_a=? THEN t.user_b ELSE t.user_a END peer_id FROM direct_threads t " +
        "JOIN users a ON a.id=t.user_a JOIN users b ON b.id=t.user_b " +
        "WHERE t.user_a=? OR t.user_b=? ORDER BY t.created_at DESC")
        .all(user.id,user.id,user.id,user.id);
      json(res,200,{threads:rows});return true;
    }
    if(method==='POST'&&path==='/api/dms') {
      limit(req,'dm-create',25);
      const {username}=await requestBody(req);
      if(typeof username!=='string'||!/^[a-zA-Z0-9_]{3,24}$/.test(username))
        throw fail(400,'Usuário inválido');
      const peer=db.prepare('SELECT id,username FROM users WHERE username=?').get(username);
      if(!peer)throw fail(404,'Usuário não encontrado');
      if(peer.id===user.id)throw fail(400,'Escolha outra pessoa');
      const [a,b]=[peer.id,user.id].sort();
      db.prepare('INSERT OR IGNORE INTO direct_threads VALUES (?,?,?,?)').run(randomUUID(),a,b,now());
      const t=db.prepare('SELECT id FROM direct_threads WHERE user_a=? AND user_b=?').get(a,b);
      send(peer.id,{type:'dm.updated'});
      json(res,200,{thread:{id:t.id,username:peer.username,peer_id:peer.id}});return true;
    }
    const dm=/^\/api\/dms\/([a-f0-9-]+)\/messages$/.exec(path);
    if(dm&&(method==='GET'||method==='POST')) {
      const t=thread(user.id,dm[1]);
      if(method==='GET') {
        const rows=db.prepare("SELECT d.id,d.content,d.created_at,u.username FROM direct_messages d " +
          "JOIN users u ON u.id=d.author_id WHERE d.thread_id=? AND d.id>? ORDER BY d.id LIMIT 100").all(t.id,cursor(uri));
        json(res,200,{messages:rows});return true;
      }
      limit(req,'message',120);
      const payload=await requestBody(req);
      const content=bodyText(payload),nonce=payload.client_nonce??null,created_at=now();
      if(nonce!==null&&(typeof nonce!=='string'||!/^[a-f0-9]{32}$/.test(nonce)))
        throw fail(400,'Identificador de mensagem inválido');
      const inserted=db.prepare('INSERT INTO direct_messages(thread_id,author_id,content,created_at,client_nonce) VALUES (?,?,?,?,?) ON CONFLICT(thread_id,author_id,client_nonce) DO NOTHING RETURNING id,content,created_at')
        .get(t.id,user.id,content,created_at,nonce);
      const record=inserted??db.prepare('SELECT id,content,created_at FROM direct_messages WHERE thread_id=? AND author_id=? AND client_nonce=?')
        .get(t.id,user.id,nonce);
      if(!record)throw fail(503,'Não foi possível confirmar a mensagem');
      if(record.content!==content)throw fail(409,'Identificador já usado em outra mensagem');
      if(inserted){
        const target=t.user_a===user.id?t.user_b:t.user_a;
        send(target,{type:'dm.message',thread_id:t.id});
        send(user.id,{type:'dm.message',thread_id:t.id});
      }
      json(res,inserted?201:200,{message:{
        id:Number(record.id),content:record.content,created_at:record.created_at,username:user.username
      },duplicate:!inserted});return true;
    }
    const members=/^\/api\/servers\/([a-f0-9-]+)\/members$/.exec(path);
    if(members&&method==='GET') {
      membership(user.id,members[1]);
      const rows=db.prepare("SELECT u.id,u.username,m.role FROM members m JOIN users u ON u.id=m.user_id " +
        "WHERE m.server_id=? ORDER BY CASE m.role WHEN 'owner' THEN 0 WHEN 'moderator' THEN 1 ELSE 2 END,u.username").all(members[1]);
      json(res,200,{members:rows});return true;
    }
    const member=/^\/api\/servers\/([a-f0-9-]+)\/members\/([a-f0-9-]+)$/.exec(path);
    if(member&&(method==='PATCH'||method==='DELETE')) {
      limit(req,'member',30);
      const role=admin(user.id,member[1],method==='PATCH');
      const target=db.prepare('SELECT role FROM members WHERE server_id=? AND user_id=?').get(member[1],member[2]);
      if(!target)throw fail(404,'Membro não encontrado');
      if(target.role==='owner')throw fail(403,'Proprietário protegido');
      if(method==='PATCH') {
        const data=await requestBody(req);
        if(!['moderator','member'].includes(data.role))throw fail(400,'Cargo inválido');
        db.prepare('UPDATE members SET role=? WHERE server_id=? AND user_id=?').run(data.role,member[1],member[2]);
      } else {
        if(role==='moderator'&&target.role!=='member')throw fail(403,'Não pode remover moderador');
        db.prepare('DELETE FROM members WHERE server_id=? AND user_id=?').run(member[1],member[2]);
        send(member[2],{type:'server.removed',server_id:member[1]});
      }
      notifyServer(member[1]);
      json(res,200,{ok:true});return true;
    }
    const channels=/^\/api\/servers\/([a-f0-9-]+)\/channels$/.exec(path);
    if(channels&&method==='POST') {
      limit(req,'channel',40);
      admin(user.id,channels[1]);
      const {name,type}=await requestBody(req);
      if(typeof name!=='string'||!/^[\p{L}\p{N}_-]{2,40}$/u.test(name)||!['text','voice'].includes(type))
        throw fail(400,'Canal inválido');
      const id=randomUUID();
      db.prepare('INSERT INTO channels VALUES (?,?,?,?)').run(id,channels[1],name,type);
      notifyServer(channels[1]);
      json(res,201,{channel:{id,name,type}});return true;
    }
    const channel=/^\/api\/servers\/([a-f0-9-]+)\/channels\/([a-f0-9-]+)$/.exec(path);
    if(channel&&method==='DELETE') {
      limit(req,'channel',40);
      admin(user.id,channel[1]);
      const r=db.prepare('DELETE FROM channels WHERE server_id=? AND id=?').run(channel[1],channel[2]);
      if(!r.changes)throw fail(404,'Canal não encontrado');
      notifyServer(channel[1]);
      json(res,200,{ok:true});return true;
    }
    return false;
  }
  function attach(app){
    app.on('upgrade',(req,socket,head)=>{
      try {
        const url=new URL(req.url||'/', 'http://localhost');
        if(url.pathname!=='/api/realtime')throw fail(404,'Sem rota');
        const user=sessionUser(req);
        const match=/^Bearer ([a-f0-9]{64})$/.exec(req.headers.authorization||'');
        if(!match)throw fail(401,'Sessão inválida');
        limit(req,'websocket',40);
        wss.handleUpgrade(req,socket,head,ws=>{
          const entry={ws,hash:sha(match[1])};
          if(!sockets.has(user.id))sockets.set(user.id,new Set());
          sockets.get(user.id).add(entry);
          ws.on('close',()=>{
            sockets.get(user.id)?.delete(entry);
            if(!sockets.get(user.id)?.size)sockets.delete(user.id);
          });
          ws.on('message',()=>{
            if(!valid(entry))ws.close(1008,'Sessão expirada');
          });
          ws.send(JSON.stringify({type:'connected'}));
        });
      }catch(e) {
        const status=Number.isInteger(e.status)?e.status:500;
        socket.end('HTTP/1.1 '+status+' Error\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
      }
    });
    const interval=setInterval(()=>{
      for(const group of sockets.values())for(const entry of group)
        if(!valid(entry))entry.ws.close(1008,'Sessão expirada');
    },60000);
    interval.unref();
  }
  return {route,attach,notifyServer,notifyChannel,disconnectToken};
}
