import React from 'react';
import {AbsoluteFill,Audio,Easing,Img,interpolate,Sequence,staticFile,useCurrentFrame,useVideoConfig} from 'remotion';
import {FlashCut} from './FlashCut';
import raw from '../shotlist.json';

type Shot={title:string;caption:string;voiceover:string;frames:number;image:string|null;audio:string|null};
const shots:Shot[] = raw.shots;
const cutoffs=shots.reduce<number[]>((all,s)=>{
  all.push((all.at(-1)||0)+s.frames);return all;
},[]);
const font='"Microsoft YaHei UI","Microsoft YaHei",system-ui,sans-serif';
const limit={extrapolateLeft:'clamp',extrapolateRight:'clamp'} as const;
const ease=Easing.bezier(.16,0,.14,1);

const Scene:React.FC<{shot:Shot;number:number}>=({shot,number})=>{
  const frame=useCurrentFrame(),{width,height}=useVideoConfig(),portrait=height>width;
  const enter=interpolate(frame,[0,24],[0,1],{...limit,easing:ease});
  const drift=interpolate(frame,[0,shot.frames],[0,1],limit);
  const fadeOut=interpolate(frame,[shot.frames-12,shot.frames],[1,0],limit);
  const padding=portrait?77:110;
  const heroTop=portrait?575:165;
  const heroHeight=portrait?820:740;
  const heroLeft=portrait?68:1040;
  const heroWidth=portrait?width-136:width-1140;
  const heading=portrait?78:79;
  return <AbsoluteFill style={{background:'#082733',overflow:'hidden',opacity:fadeOut,fontFamily:font}}>
    <div style={{position:'absolute',top:-390,right:-370,width:1350,height:1350,borderRadius:'50%',
      background:'radial-gradient(circle,rgba(64,165,187,.35),transparent 68%)'}}/>
    <div style={{position:'absolute',left:padding,top:portrait?132:95,zIndex:8,
      fontSize:25,fontWeight:760,color:'#8bdae5',letterSpacing:3}}>
      {String(number).padStart(2,'0')} / {String(shots.length).padStart(2,'0')}
    </div>
    <div style={{position:'absolute',left:padding,top:portrait?260:220,zIndex:10,
      right:portrait?padding:width*.53,opacity:enter,
      transform:'translateY('+((1-enter)*44)+'px)'}}>
      <div style={{color:'#fff',fontWeight:830,fontSize:heading,
        lineHeight:1.26,letterSpacing:-2,overflowWrap:'anywhere'}}>{shot.title}</div>
      <div style={{fontSize:portrait?35:37,color:'#bcdde4',fontWeight:550,marginTop:40,
        lineHeight:1.57}}>{shot.caption}</div>
      <div style={{height:6,width:(portrait?310:290)*enter,
        borderRadius:8,background:'linear-gradient(90deg,#67cddd,#167b94)',marginTop:52}}/>
    </div>
    <div style={{position:'absolute',left:heroLeft,top:heroTop,width:heroWidth,height:heroHeight,zIndex:6,
      borderRadius:portrait?35:27,overflow:'hidden',
      background:'linear-gradient(145deg,#164251,#f0f8fa)',border:'1px solid rgba(218,248,251,.27)',
      boxShadow:'0 26px 75px rgba(0,15,22,.27)',opacity:enter,
      transform:'translateY('+((1-enter)*52)+'px)'}}>
      {shot.image
        ?<Img src={staticFile(shot.image)} style={{height:'100%',width:'100%',objectFit:'contain',
           transform:'scale('+(1+drift*.045)+')',filter:'saturate(.98)'}}/>
        :<div style={{height:'100%',width:'100%',display:'flex',justifyContent:'center',alignItems:'center',
          fontSize:portrait?83:75,color:'#eaf9fb',fontWeight:830,textAlign:'center',padding:65,
          boxSizing:'border-box',lineHeight:1.4}}>
           {shot.title}
         </div>}
    </div>
    <div style={{position:'absolute',left:padding,right:padding,bottom:portrait?220:85,
      height:portrait?137:107,display:'flex',alignItems:'center',justifyContent:'center',zIndex:15,
      borderRadius:22,background:'rgba(10,45,57,.96)',border:'1px solid rgba(105,208,224,.38)',
      opacity:enter,boxShadow:'0 12px 34px rgba(4,20,28,.12)'}}>
      <div style={{textAlign:'center',fontSize:portrait?35:30,color:'#f0fbfc',fontWeight:640,
        padding:21,lineHeight:1.4}}>{shot.caption||shot.title}</div>
    </div>
    <div style={{position:'absolute',left:padding,right:padding,bottom:portrait?123:28,
      display:'flex',gap:9}}>
      {shots.map((_,i)=><div key={i} style={{flex:1,height:6,borderRadius:7,
        background:i<=number-1?'#5cc5d5':'rgba(140,194,206,.2)'}}/>)}
    </div>
  </AbsoluteFill>;
};

export const Quick:React.FC<{bgm?:boolean}>=({bgm=true})=><AbsoluteFill style={{background:'#082733'}}>
  {shots.map((shot,i)=>{
    const from=i===0?0:cutoffs[i-1];
    return <React.Fragment key={i}>
      <Sequence from={from} durationInFrames={shot.frames}>
        <Scene shot={shot} number={i+1}/>
        {shot.audio?<Audio src={staticFile(shot.audio)} volume={.95}/>:null}
      </Sequence>
      {i>0?<Sequence from={from} durationInFrames={10}>
        <FlashCut duration={10}/>
      </Sequence>:null}
    </React.Fragment>;
  })}
  {bgm?<Audio src={staticFile('audio/bgm.mp3')} loop volume={.038}/>:null}
</AbsoluteFill>;
