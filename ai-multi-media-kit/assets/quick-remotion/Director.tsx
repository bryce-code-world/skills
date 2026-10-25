/** Original Remotion director layouts. No external motion-code dependency. */
import React from 'react';
import {AbsoluteFill,Img,OffthreadVideo,interpolate,spring,staticFile,useCurrentFrame,useVideoConfig} from 'remotion';

export type VisualMode='standard'|'focus'|'showcase'|'kinetic'|'reveal'|'compare'|'steps';
export type DirectedShot={
  title:string;frames:number;image?:string|null;video?:string|null;
  visual_mode?:VisualMode;steps?:string[];
  before_image?:string|null;after_image?:string|null;
};
const themes={
  product:{bg:'#071c35',panel:'#173e5b',paper:'#f3fbfd',ink:'#17344d',accent:'#6ed8c7',secondary:'#a8c9ef'},
  warm:{bg:'#33263c',panel:'#604d58',paper:'#fff7ed',ink:'#4e3540',accent:'#ffc58a',secondary:'#fbe3ba'},
  social:{bg:'#11182a',panel:'#293e62',paper:'#f6fcff',ink:'#172a48',accent:'#ff947f',secondary:'#88e7d6'},
};
const clamp={extrapolateLeft:'clamp',extrapolateRight:'clamp'} as const;
const font='"Microsoft YaHei UI","Microsoft YaHei",system-ui,sans-serif';
const modeTitles={focus:'聚焦细节',showcase:'完整呈现',kinetic:'观点强调',
  reveal:'成果揭晓',compare:'真实前后变化',steps:'具体操作步骤',standard:'画面说明'};
const Media:React.FC<{image?:string|null;video?:string|null;fit?:'contain'|'cover';zoom?:number}>=({
  image,video,fit='contain',zoom=1,
})=>{
  const css:React.CSSProperties={width:'100%',height:'100%',objectFit:fit,
    transform:'scale('+zoom+')'};
  if(video)return <OffthreadVideo src={staticFile(video)} muted style={css}/>;
  return image?<Img src={staticFile(image)} style={css}/>:null;
};
const Heading:React.FC<{title:string;portrait:boolean;color?:string;size?:number}>=({
  title,portrait,color='#fff',size,
})=><div style={{color,fontSize:size||(portrait?70:64),fontWeight:850,lineHeight:1.22,
  letterSpacing:-1.1,overflowWrap:'anywhere',textShadow:'0 2px 12px rgba(0,0,0,.17)'}}>
  {title}
</div>;

export const Director:React.FC<{shot:DirectedShot;number:number;total:number;styleId:string}>=({
  shot,number,total,styleId,
})=>{
  const frame=useCurrentFrame(),{width:w,height:h,fps}=useVideoConfig();
  const portrait=h>w;
  const theme=themes[styleId as keyof typeof themes]||themes.product;
  const mode=shot.visual_mode||'standard';
  const pad=portrait?68:100;
  const full=w-2*pad;
  const progress=interpolate(frame,[0,Math.max(1,shot.frames-1)],[0,1],clamp);
  const entry=spring({frame,fps,config:{damping:22,stiffness:110}});
  const exit=interpolate(frame,[0,13,Math.max(14,shot.frames-9),shot.frames],
    [0,1,1,0],clamp);
  const rise=34*(1-entry);
  const mediaTop=portrait?h*.29:h*.22;
  const region=portrait?h*.42:h*.53;
  const cardShadow='0 30px 86px rgba(0,0,0,.31)';
  const topTitle=(top:number,size?:number)=> <div style={{position:'absolute',left:pad,
      top,right:pad,transform:'translateY('+rise+'px)'}}>
      <Heading title={shot.title} portrait={portrait} size={size}/>
    </div>;
  const asset=(zoom=1)=><Media image={shot.image} video={shot.video} zoom={zoom}/>;
  const card:React.CSSProperties={position:'absolute',left:pad,top:mediaTop,
    width:full,height:region,borderRadius:32,overflow:'hidden',
    background:theme.paper,boxShadow:cardShadow,border:'1px solid rgba(255,255,255,.18)'};
  let center:React.ReactNode;
  if(mode==='showcase'){
    center=<>
      {topTitle(h*.14,portrait?72:64)}
      <div style={{...card,transform:'translateY('+rise+'px)'}}>
        {asset(1+.045*progress)}
        <div style={{position:'absolute',left:0,bottom:0,height:6,
          width:'100%',background:theme.accent}}/>
      </div>
    </>;
  }else if(mode==='focus'){
    center=<>
      {topTitle(h*.14,portrait?73:60)}
      <div style={{...card,left:pad+17,width:full-34,height:region*.96,
        transform:'translateY('+rise+'px)'}}>
        {asset(1+.12*progress)}
        <div style={{position:'absolute',inset:18,borderRadius:24,
          border:'2px solid '+theme.accent,opacity:.32}}/>
        <div style={{position:'absolute',right:25,bottom:24,color:theme.paper,
          background:theme.bg,padding:'14px 23px',borderRadius:17,
          fontWeight:780,fontSize:23}}>画面特写</div>
      </div>
    </>;
  }else if(mode==='compare'){
    const gap=24,half=(full-gap)/2;
    center=<>
      {topTitle(h*.15,portrait?64:57)}
      {[{label:'调整之前',media:shot.before_image,side:0,offset:-72},
        {label:'调整之后',media:shot.after_image,side:1,offset:72}].map(item=>{
        const css:React.CSSProperties={...card,left:pad+item.side*(half+gap),
          top:mediaTop+region*.105,height:region*.78,
          width:half,transform:'translateX('+(item.offset*(1-entry))+'px)'};
        return <div key={item.label} style={css}>
          <div style={{height:region*.78-92,overflow:'hidden'}}>
            <Media image={item.media} zoom={1+.035*progress}/>
          </div>
          <div style={{height:92,display:'flex',alignItems:'center',justifyContent:'center',
            color:theme.ink,fontSize:portrait?31:28,fontWeight:840,
            background:item.side===0?'#ebe9ec':theme.accent}}>{item.label}</div>
        </div>;
      })}
    </>;
  }else if(mode==='steps'){
    center=<>
      {topTitle(h*.155,portrait?62:55)}
      {(shot.steps||[]).map((item,index)=>{
        const local=interpolate(frame,[index*10,index*10+21],[0,1],clamp);
        const top=mediaTop+index*(region/3);
        const left=pad+index*(portrait?26:38);
        return <div key={index} style={{position:'absolute',left,top,
          width:full-index*(portrait?52:76),height:region/3-16,
          background:theme.paper,borderRadius:26,padding:24,
          boxSizing:'border-box',display:'flex',alignItems:'center',
          opacity:Math.max(.3,local),transform:'translateX('+((1-local)*(index%2?-90:90))+'px)',
          boxShadow:'0 16px 40px rgba(0,0,0,.2)'}}>
          <div style={{width:104,height:104,borderRadius:25,flexShrink:0,
            background:index===1?theme.secondary:theme.accent,display:'flex',
            alignItems:'center',justifyContent:'center',fontSize:43,
            color:theme.ink,fontWeight:900}}>
            {String(index+1).padStart(2,'0')}
          </div>
          <div style={{marginLeft:27,overflow:'hidden',textOverflow:'ellipsis',
            whiteSpace:'nowrap',fontWeight:850,fontSize:portrait?49:42,
            color:theme.ink}}>{item}</div>
        </div>;
      })}
    </>;
  }else if(mode==='reveal'){
    const pop=spring({frame:Math.max(0,frame-5),fps,config:{damping:17,stiffness:90}});
    center=<>
      {topTitle(h*.145,portrait?70:60)}
      <div style={{...card,left:pad+12,width:full-24,height:region*.93,
        transform:'translateY('+rise+'px) scale('+(.84+.16*pop)+')'}}>
        {asset(1+.02*progress)}
      </div>
      <div style={{position:'absolute',left:pad+36,
        top:mediaTop+region*.79,background:theme.accent,
        color:theme.ink,borderRadius:18,padding:'18px 28px',
        fontWeight:840,fontSize:portrait?33:28,
        transform:'translateY('+(70*(1-entry))+'px)'}}>
        看见制作成果
      </div>
    </>;
  }else{ // kinetic: the words move as editorial beats instead of sitting on a title card.
    const phrases=shot.title.split(/[，、：:\s]+/).filter(Boolean);
    const pieces=phrases.length>1?phrases:[shot.title];
    center=<>
      <div style={{position:'absolute',left:pad,top:h*.17,color:theme.secondary,
        fontWeight:760,fontSize:portrait?30:25}}>一句话，说清重点</div>
      {(shot.image||shot.video)?<div style={{...card,filter:'blur(28px)',
        opacity:.09,top:h*.26,height:h*.38}}>{asset(1+.1*progress)}</div>:null}
      <div style={{position:'absolute',left:pad,right:pad,top:h*.30,
        display:'flex',flexDirection:'column',gap:27}}>
        {pieces.slice(0,3).map((word,i)=>{
          const v=interpolate(frame,[i*10,i*10+18],[0,1],clamp);
          return <div key={i} style={{fontSize:portrait?82:70,
            fontWeight:890,lineHeight:1.21,letterSpacing:-1.4,
            color:i===pieces.length-1?theme.accent:'#fff',overflowWrap:'anywhere',
            opacity:v,transform:'translateX('+(i%2?90:-90)*(1-v)+'px)'}}>
            {word}
          </div>;
        })}
      </div>
      {(shot.image||shot.video)?<div style={{...card,left:pad+24,width:full-48,
        top:h*.51,height:h*.172,borderRadius:22,border:'2px solid '+theme.accent,
        opacity:interpolate(frame,[16,30],[0,1],clamp),
        transform:'translateY('+(23*(1-entry))+'px)'}}>
        {asset(1+.045*progress)}
      </div>:null}
      <div style={{position:'absolute',left:pad,right:pad,top:h*.70,
        height:9,borderRadius:9,background:theme.panel}}>
        <div style={{height:'100%',width:(100*progress)+'%',background:theme.accent,
          borderRadius:9}}/>
      </div>
    </>;
  }
  return <AbsoluteFill style={{background:theme.bg,fontFamily:font,overflow:'hidden',opacity:exit}}>
    <div style={{position:'absolute',right:-w*.30,top:-h*.13,
      width:w*1.1,height:w*1.1,borderRadius:'50%',
      background:'radial-gradient(circle,'+theme.panel+',transparent 70%)'}}/>
    <div style={{position:'absolute',left:pad,top:portrait?85:48,right:pad,
      display:'flex',justifyContent:'space-between',alignItems:'center',
      color:theme.secondary,fontWeight:730,letterSpacing:1.3,
      fontSize:portrait?24:21}}>
      <span>{modeTitles[mode]}</span>
      <span>{String(number).padStart(2,'0')} / {String(total).padStart(2,'0')}</span>
    </div>
    {center}
    <div style={{position:'absolute',left:pad,right:pad,top:h*.755,height:5,
      background:theme.panel,borderRadius:5}}>
      <div style={{height:'100%',width:(100*progress)+'%',
        background:theme.accent,borderRadius:5}}/>
    </div>
  </AbsoluteFill>;
};
