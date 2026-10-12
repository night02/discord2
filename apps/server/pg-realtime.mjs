import {WebSocketServer,WebSocket} from 'ws';
import {sha,one,rows,sessionUser,limit} from './pg-common.mjs';

const wss=new WebSocketServer({noServer:true,maxPayload:4096,perMessageDeflate:false});
const sockets=new Map();
const valid=async entry=>Boolean(await one(
  'SELECT 1 FROM sessions WHERE token_hash=$1 AND expires_at>$2',entry.hash,Date.now()));

export async function notifyUser(userId,data){
  const group=sockets.get(userId);
  if(!group)return;
  for(const entry of group){
    try{
      if(!(await valid(entry))){entry.ws.close(1008,'Sessão expirada');continue;}
      if(entry.ws.readyState===WebSocket.OPEN){
        if(entry.ws.bufferedAmount>262144)entry.ws.terminate();
        else entry.ws.send(JSON.stringify(data));
      }
    }catch{entry.ws.terminate();}
  }
}
export async function notifyServer(sid){
  const members=await rows('SELECT user_id FROM members WHERE server_id=$1',sid);
  await Promise.all(members.map(m=>notifyUser(m.user_id,{type:'server.updated',server_id:sid})));
}
export async function notifyChannel(cid,sid){
  const members=await rows('SELECT user_id FROM members WHERE server_id=$1',sid);
  await Promise.all(members.map(m=>notifyUser(m.user_id,{type:'channel.message',channel_id:cid})));
}
export function disconnectToken(raw){
  const digest=sha(raw);
  for(const group of sockets.values())for(const item of group)
    if(item.hash===digest)item.ws.close(1008,'Sessão encerrada');
}
export function attachRealtime(app){
  app.on('upgrade',(req,socket,head)=>{
    (async()=>{
      const url=new URL(req.url||'/','http://localhost');
      if(url.pathname!=='/api/realtime')throw Error('Not a realtime route');
      const user=await sessionUser(req);
      const auth=/^Bearer ([a-f0-9]{64})$/.exec(req.headers.authorization||'');
      if(!auth)throw Error('Session invalid');
      limit(req,'websocket',40);
      wss.handleUpgrade(req,socket,head,ws=>{
        const entry={ws,hash:sha(auth[1])};
        if(!sockets.has(user.id))sockets.set(user.id,new Set());
        sockets.get(user.id).add(entry);
        ws.on('close',()=>{
          sockets.get(user.id)?.delete(entry);
          if(!sockets.get(user.id)?.size)sockets.delete(user.id);
        });
        ws.on('message',()=>valid(entry).then(ok=>{
          if(!ok)ws.close(1008,'Sessão expirada');
        }).catch(()=>ws.terminate()));
        ws.send(JSON.stringify({type:'connected'}));
      });
    })().catch(()=>{
      if(!socket.destroyed)socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
    });
  });
  const cleanup=setInterval(async()=>{
    for(const group of sockets.values())for(const entry of group){
      try{if(!(await valid(entry)))entry.ws.close(1008,'Sessão expirada');}
      catch{entry.ws.terminate();}
    }
  },60000);
  cleanup.unref();
}
