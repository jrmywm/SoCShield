const playback=document.querySelector('#playback'),cycleRange=document.querySelector('#cycle-range'),cycleLabel=document.querySelector('#cycle-label'),playToggle=document.querySelector('#play-toggle'),speedSelect=document.querySelector('#play-speed');
let replay=null,playFrame=0,lastFrame=0,cycleNow=0;
function prepareReplay(run){
  replay=run;const m=run.metrics;const begin=Number(m.begin_cycle)||0,ack=Number(m.ack_cycle)||begin;
  replay.lo=Math.max(0,begin-24);replay.hi=Math.max(replay.lo+1,ack+24);cycleNow=replay.lo;
  cycleRange.min=replay.lo;cycleRange.max=replay.hi;cycleRange.value=cycleNow;playToggle.textContent='▶ Play';
  drawReplay();
}
function drawReplay(){
  if(!replay)return;const ctx=playback.getContext('2d'),w=playback.clientWidth||600,h=144,dpr=window.devicePixelRatio||1;
  playback.width=w*dpr;playback.height=h*dpr;ctx.scale(dpr,dpr);ctx.clearRect(0,0,w,h);
  const left=52,right=w-15,top=17,bottom=112,range=replay.hi-replay.lo||1;
  const xAt=c=>left+(right-left)*(c-replay.lo)/range;const lane={request:36,response:70,ack:103};
  ctx.font='10px DM Mono, monospace';ctx.fillStyle='#a7b8b6';ctx.strokeStyle='#30464e';
  for(const [kind,y] of Object.entries(lane)){ctx.fillText({request:'DMA request',response:'Response',ack:'Policy ack'}[kind],4,y+3);ctx.beginPath();ctx.moveTo(left,y);ctx.lineTo(right,y);ctx.stroke()}
  for(const e of replay.events){if(!(e.event in lane)||e.cycle<replay.lo||e.cycle>replay.hi)continue;const x=xAt(e.cycle);ctx.fillStyle={request:'#78bce0',response:'#8ed8b5',ack:'#f07976'}[e.event];ctx.globalAlpha=e.cycle<=cycleNow?.9:.22;ctx.beginPath();ctx.arc(x,lane[e.event],3,0,Math.PI*2);ctx.fill()}
  ctx.globalAlpha=1;const cursor=xAt(cycleNow);ctx.strokeStyle='#f1a66c';ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(cursor,top);ctx.lineTo(cursor,bottom+8);ctx.stroke();
  cycleLabel.textContent=`Cycle ${Math.round(cycleNow).toLocaleString()}`;
}
function stopReplay(){if(playFrame)cancelAnimationFrame(playFrame);playFrame=0;lastFrame=0;playToggle.textContent='▶ Play'}
function animateReplay(ts){if(!replay)return;if(!lastFrame)lastFrame=ts;const elapsed=Math.min(ts-lastFrame,100);lastFrame=ts;cycleNow+=elapsed*Number(speedSelect.value)/1000;if(cycleNow>=replay.hi){cycleNow=replay.hi;stopReplay()}cycleRange.value=cycleNow;drawReplay();if(!playFrame&&cycleNow>=replay.hi)return;playFrame=requestAnimationFrame(animateReplay)}
document.addEventListener('socshield-run-loaded',e=>prepareReplay(e.detail));
playToggle.addEventListener('click',()=>{if(!replay)return;if(playFrame){stopReplay();return}if(cycleNow>=replay.hi)cycleNow=replay.lo;lastFrame=0;playToggle.textContent='Ⅱ Pause';playFrame=requestAnimationFrame(animateReplay)});
cycleRange.addEventListener('input',()=>{stopReplay();cycleNow=Number(cycleRange.value);drawReplay()});
window.addEventListener('resize',drawReplay);
