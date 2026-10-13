import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
import {AudioFrame,AudioSource,AudioStream,LocalAudioTrack,LocalVideoTrack,Room,RoomEvent,TrackKind,TrackPublishOptions,TrackSource,VideoBufferType,VideoFrame,VideoSource,VideoStream,dispose} from '@livekit/rtc-node';
import {issueMediaAccess} from '../../apps/server/media-access.mjs';
async function availablePort(){
  const server=createServer();await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const port=server.address().port;await new Promise(resolve=>server.close(resolve));return port;
}
test('real SFU delivers two-way audio, screen frames, isolation and share stop',{timeout:45000},async t=>{
  const binary=process.env.LIVEKIT_TEST_BINARY;assert.ok(binary,'Set LIVEKIT_TEST_BINARY to verified LiveKit 1.13.9.');
  const port=await availablePort(),tcpPort=await availablePort(),udpPort=42000+Math.floor(Math.random()*15000);
  const config='port: '+port+'\nrtc:\n  tcp_port: '+tcpPort+'\n  udp_port: '+udpPort+'\n  use_external_ip: false\n  enable_loopback_candidate: true\n';
  const server=spawn(binary,['--dev','--bind','127.0.0.1','--node-ip','127.0.0.1','--config-body',config],{stdio:['ignore','pipe','pipe']});
  let stderr='';const append=chunk=>{stderr=(stderr+chunk).slice(-4000);};server.stderr.on('data',append);server.stdout.on('data',append);
  t.after(()=>{if(server.exitCode===null)server.kill('SIGTERM');});
  let ready=false;
  for(let i=0;i<150;i++){
    if(server.exitCode!==null)break;
    try{await fetch('http://127.0.0.1:'+port);ready=true;break;}catch{}
    await delay(50);
  }
  assert.ok(ready,'SFU failed to start: '+stderr);
  const env={LIVEKIT_URL:'wss://local-test.example.com',LIVEKIT_API_KEY:'devkey',LIVEKIT_API_SECRET:'secret'};
  const credential=(id,channel)=>issueMediaAccess({id,username:id},{id:channel,type:'voice'},{env}).token;
  const alice=new Room(),bob=new Room(),isolated=new Room();
  const received={aliceAudio:0,bobAudio:0,bobVideo:0,isolated:0,width:null,height:null},readers=[],handles=[],tracks=[];
  function listen(room,key){
    room.on(RoomEvent.TrackSubscribed,track=>{
      if(key==='isolated'){received.isolated++;return;}
      if(track.kind===TrackKind.KIND_AUDIO){
        const reader=new AudioStream(track,{sampleRate:48000,numChannels:1}).getReader();handles.push(reader);
        readers.push((async()=>{while(true){const {value:frame,done}=await reader.read();if(done)break;if(frame.samplesPerChannel>0)received[key+'Audio']++;}})().catch(()=>{}));
      }else if(track.kind===TrackKind.KIND_VIDEO && key==='bob'){
        const reader=new VideoStream(track).getReader();handles.push(reader);
        readers.push((async()=>{while(true){const {value:event,done}=await reader.read();if(done)break;received.bobVideo++;received.width=event.frame.width;received.height=event.frame.height;}})().catch(()=>{}));
      }
    });
  }
  listen(alice,'alice');listen(bob,'bob');listen(isolated,'isolated');
  try{
    const url='ws://127.0.0.1:'+port;
    await alice.connect(url,credential('alice-test','shared'),{autoSubscribe:true});
    await bob.connect(url,credential('bob-test','shared'),{autoSubscribe:true});
    await isolated.connect(url,credential('isolated-test','different'),{autoSubscribe:true});
    const sourceA=new AudioSource(48000,1),sourceB=new AudioSource(48000,1);
    const audioA=LocalAudioTrack.createAudioTrack('alice-fixture',sourceA),audioB=LocalAudioTrack.createAudioTrack('bob-fixture',sourceB);tracks.push(audioA,audioB);
    const options=new TrackPublishOptions({source:TrackSource.SOURCE_MICROPHONE});
    await alice.localParticipant.publishTrack(audioA,options);await bob.localParticipant.publishTrack(audioB,options);
    const width=160,height=90,sourceV=new VideoSource(width,height),video=LocalVideoTrack.createVideoTrack('screen-fixture',sourceV);tracks.push(video);
    const screen=await alice.localParticipant.publishTrack(video,new TrackPublishOptions({source:TrackSource.SOURCE_SCREENSHARE,simulcast:false}));
    const pixels=new Uint8Array(width*height*4);
    for(let i=0;i<pixels.length;i+=4){pixels[i]=30;pixels[i+1]=120;pixels[i+2]=220;pixels[i+3]=255;}
    for(let tick=0;tick<200;tick++){
      const wave=Int16Array.from({length:960},(_,i)=>Math.round(1000*Math.sin(2*Math.PI*440*(tick*960+i)/48000)));
      await Promise.all([sourceA.captureFrame(new AudioFrame(wave,48000,1,960)),sourceB.captureFrame(new AudioFrame(wave,48000,1,960))]);
      if(tick%3===0){for(let i=0;i<pixels.length;i+=4)pixels[i]=(tick*13)%256;sourceV.captureFrame(new VideoFrame(pixels,width,height,VideoBufferType.RGBA));}
      if(received.aliceAudio>=10 && received.bobAudio>=10 && received.bobVideo>=3)break;
      await delay(20);
    }
    assert.ok(received.aliceAudio>=10,'Alice must receive real PCM from Bob.');
    assert.ok(received.bobAudio>=10,'Bob must receive real PCM from Alice.');
    assert.ok(received.bobVideo>=3,'Bob must receive decoded video.');
    assert.equal(received.width,width);assert.equal(received.height,height);assert.equal(received.isolated,0);
    let ended=false;
    bob.on(RoomEvent.TrackUnpublished,publication=>{if(publication.sid===screen.sid)ended=true;});
    await alice.localParticipant.unpublishTrack(screen.sid);
    for(let i=0;i<50 && !ended;i++)await delay(40);
    assert.ok(ended,'Stop must remove the remote publication.');
    t.diagnostic('Actual two-way PCM, decoded 160x90 video, room isolation and unpublish event verified.');
  }finally{
    await Promise.allSettled(handles.map(reader=>reader.cancel()));
    await Promise.allSettled(tracks.map(track=>track.close()));
    await Promise.allSettled([alice.disconnect(),bob.disconnect(),isolated.disconnect()]);
    await dispose();await Promise.allSettled(readers);
  }
});
