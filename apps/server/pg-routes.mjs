import {
  one,rows,query,randomUUID,memberRole,requireAdmin,threadFor,
  checkedMessage,checkedNonce,afterCursor,body,limit,fail,json,now
} from './pg-common.mjs';
import {notifyUser,notifyServer} from './pg-realtime.mjs';

export async function extraRoutes(req,res,user,route,method,url){
  if(route==='/api/dms'&&method==='GET'){
    const threads=await rows(
      "SELECT t.id,CASE WHEN t.user_a=$1 THEN b.username ELSE a.username END username, "+
      "CASE WHEN t.user_a=$2 THEN t.user_b ELSE t.user_a END peer_id "+
      "FROM direct_threads t JOIN users a ON a.id=t.user_a JOIN users b ON b.id=t.user_b "+
      "WHERE t.user_a=$3 OR t.user_b=$4 ORDER BY t.created_at DESC",
      user.id,user.id,user.id,user.id);
    json(res,200,{threads});return true;
  }
  if(route==='/api/dms'&&method==='POST'){
    limit(req,'dm-create',25);
    const {username}=await body(req);
    if(typeof username!=='string'||!/^[a-zA-Z0-9_]{3,24}$/.test(username))
      throw fail(400,'Nome de usuário inválido');
    const peer=await one('SELECT id,username FROM users WHERE lower(username)=lower($1)',username);
    if(!peer)throw fail(404,'Usuário não encontrado');
    if(peer.id===user.id)throw fail(400,'Não é possível criar DM consigo mesmo');
    const[a,b]=[user.id,peer.id].sort();
    await query('INSERT INTO direct_threads VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING',
      randomUUID(),a,b,now());
    const t=await one('SELECT id FROM direct_threads WHERE user_a=$1 AND user_b=$2',a,b);
    await notifyUser(peer.id,{type:'dm.updated'});
    json(res,200,{thread:{id:t.id,username:peer.username,peer_id:peer.id}});return true;
  }
  const dm=/^\/api\/dms\/([a-f0-9-]+)\/messages$/.exec(route);
  if(dm&&(method==='GET'||method==='POST')){
    const thread=await threadFor(user.id,dm[1]);
    if(method==='GET'){
      const messages=await rows(
        'SELECT d.id,d.content,d.created_at,u.username FROM direct_messages d JOIN users u ON u.id=d.author_id WHERE d.thread_id=$1 AND d.id>$2 ORDER BY d.id LIMIT 100',
        thread.id,afterCursor(url));
      json(res,200,{messages:messages.map(r=>({...r,id:Number(r.id)}))});return true;
    }
    limit(req,'message',120);
    const payload=await body(req);
    const content=checkedMessage(payload.content),nonce=checkedNonce(payload.client_nonce);
    const created_at=now();
    const inserted=await one(
      'INSERT INTO direct_messages(thread_id,author_id,content,created_at,client_nonce) VALUES($1,$2,$3,$4,$5) ON CONFLICT (thread_id,author_id,client_nonce) DO NOTHING RETURNING id,content,created_at',
      thread.id,user.id,content,created_at,nonce);
    const record=inserted??await one(
      'SELECT id,content,created_at FROM direct_messages WHERE thread_id=$1 AND author_id=$2 AND client_nonce=$3',
      thread.id,user.id,nonce);
    if(!record)throw fail(503,'Não foi possível confirmar a mensagem');
    if(record.content!==content)throw fail(409,'Identificador já usado em outra mensagem');
    if(inserted){
      const other=thread.user_a===user.id?thread.user_b:thread.user_a;
      await Promise.all([
        notifyUser(other,{type:'dm.message',thread_id:thread.id}),
        notifyUser(user.id,{type:'dm.message',thread_id:thread.id})
      ]);
    }
    json(res,inserted?201:200,{message:{
      id:Number(record.id),username:user.username,content:record.content,created_at:record.created_at
    },duplicate:!inserted});return true;
  }
  const members=/^\/api\/servers\/([a-f0-9-]+)\/members$/.exec(route);
  if(members&&method==='GET'){
    await memberRole(user.id,members[1]);
    const data=await rows(
      "SELECT u.id,u.username,m.role FROM members m JOIN users u ON u.id=m.user_id WHERE m.server_id=$1 ORDER BY CASE m.role WHEN 'owner' THEN 0 WHEN 'moderator' THEN 1 ELSE 2 END,u.username",
      members[1]);
    json(res,200,{members:data});return true;
  }
  const member=/^\/api\/servers\/([a-f0-9-]+)\/members\/([a-f0-9-]+)$/.exec(route);
  if(member&&(method==='PATCH'||method==='DELETE')){
    limit(req,'member',30);
    const role=await requireAdmin(user.id,member[1],method==='PATCH');
    const target=await one('SELECT role FROM members WHERE server_id=$1 AND user_id=$2',
      member[1],member[2]);
    if(!target)throw fail(404,'Membro não encontrado');
    if(target.role==='owner')throw fail(403,'Proprietário protegido');
    if(method==='PATCH'){
      const {role:next}=await body(req);
      if(!['moderator','member'].includes(next))throw fail(400,'Cargo inválido');
      await query('UPDATE members SET role=$1 WHERE server_id=$2 AND user_id=$3',next,member[1],member[2]);
    }else{
      if(role==='moderator'&&target.role!=='member')
        throw fail(403,'Moderador não pode remover outro moderador');
      await query('DELETE FROM members WHERE server_id=$1 AND user_id=$2',member[1],member[2]);
      await notifyUser(member[2],{type:'server.removed',server_id:member[1]});
    }
    await notifyServer(member[1]);
    json(res,200,{ok:true});return true;
  }
  const channels=/^\/api\/servers\/([a-f0-9-]+)\/channels$/.exec(route);
  if(channels&&method==='POST'){
    limit(req,'channel',40);
    await requireAdmin(user.id,channels[1]);
    const {name,type}=await body(req);
    if(typeof name!=='string'||!/^[\p{L}\p{N}_-]{2,40}$/u.test(name)||
       !['text','voice'].includes(type))throw fail(400,'Canal inválido');
    const id=randomUUID();
    await query('INSERT INTO channels VALUES($1,$2,$3,$4)',id,channels[1],name,type);
    await notifyServer(channels[1]);
    json(res,201,{channel:{id,name,type}});return true;
  }
  const channel=/^\/api\/servers\/([a-f0-9-]+)\/channels\/([a-f0-9-]+)$/.exec(route);
  if(channel&&method==='DELETE'){
    limit(req,'channel',40);
    await requireAdmin(user.id,channel[1]);
    const result=await query('DELETE FROM channels WHERE server_id=$1 AND id=$2',channel[1],channel[2]);
    if(result.rowCount===0)throw fail(404,'Canal não encontrado');
    await notifyServer(channel[1]);
    json(res,200,{ok:true});return true;
  }
  return false;
}
