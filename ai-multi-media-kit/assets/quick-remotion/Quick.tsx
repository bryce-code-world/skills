import React from 'react';
import {AbsoluteFill, Audio, Easing, Img, interpolate, Sequence, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import raw from '../shotlist.json';

type Shot = {title:string; caption:string; voiceover:string; frames:number; image:string|null; audio:string|null};
const shots:Shot[] = raw.shots;
const cutoffs = shots.reduce<number[]>((all, shot) => {
  all.push((all.at(-1) || 0) + shot.frames);
  return all;
}, []);
const font = '"Microsoft YaHei UI","Microsoft YaHei",system-ui,sans-serif';
const limit = {extrapolateLeft:'clamp', extrapolateRight:'clamp'} as const;
const ease = Easing.bezier(.16, 0, .14, 1);

// Measure the actual font and render explicit lines: no clipping or hidden overflow.
const fitText = (text:string, width:number, maxHeight:number, maxLines:number, maxSize:number, minSize:number, weight:number, lineHeight:number) => {
  const context = document.createElement('canvas').getContext('2d');
  if (!context) throw new Error('Text measurement is unavailable');
  const value = text.replace(/\s+/g, ' ').trim();
  const wrap = (lineWidth:number) => {
    const lines:string[] = [];
    let line = '';
    for (const char of value) {
      if (line && context.measureText(line + char).width > lineWidth) {
        lines.push(line.trim());
        line = '';
      }
      line += char;
    }
    if (line) lines.push(line.trim());
    return lines;
  };
  for (let size = maxSize; size >= minSize; size--) {
    context.font = `${weight} ${size}px ${font}`;
    let lines = wrap(width);
    if (lines.length <= maxLines && lines.length * size * lineHeight <= maxHeight) {
      // Keep the chosen size and line count, then balance away short trailing lines.
      const lineCount = lines.length;
      if (lineCount > 1) {
        let low = 0, high = width;
        for (let attempt = 0; attempt < 8; attempt++) {
          const candidateWidth = (low + high) / 2;
          const candidate = wrap(candidateWidth);
          if (candidate.length <= lineCount) {
            high = candidateWidth;
            lines = candidate;
          } else {
            low = candidateWidth;
          }
        }
      }
      return {size, lines};
    }
  }
  throw new Error('QuickVideo text is too long at a readable size; shorten the title or caption');
};

const Scene:React.FC<{shot:Shot; number:number}> = ({shot, number}) => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();
  const portrait = height > width;
  const enter = interpolate(frame, [0, 16], [0, 1], {...limit, easing:ease});
  const fadeOut = interpolate(frame, [shot.frames - 8, shot.frames], [1, 0], limit);
  const padding = portrait ? 77 : 110;
  const headingWidth = !shot.image || portrait ? width - padding * 2 : 820;
  const heading = React.useMemo(
    () => fitText(shot.title, headingWidth, portrait && shot.image ? 290 : 440, 4, portrait ? 78 : 79, 48, 800, 1.22),
    [shot.title, shot.image, headingWidth, portrait],
  );
  const caption = React.useMemo(
    () => shot.caption ? fitText(shot.caption, width - padding * 2 - 48, height * .13 - 48, 2, portrait ? 35 : 34, 30, 600, 1.35) : null,
    [shot.caption, width, padding, height, portrait],
  );
  return <AbsoluteFill style={{background:'#082733', overflow:'hidden', opacity:fadeOut, fontFamily:font}}>
    <div style={{position:'absolute', top:-390, right:-370, width:1350, height:1350, borderRadius:'50%',
      background:'radial-gradient(circle,rgba(64,165,187,.35),transparent 68%)'}}/>
    <div style={{position:'absolute', left:padding, top:portrait ? 132 : 95,
      fontSize:25, fontWeight:700, color:'#8bdae5', letterSpacing:3}}>
      {String(number).padStart(2,'0')} / {String(shots.length).padStart(2,'0')}
    </div>
    <div style={{position:'absolute', left:padding, top:shot.image ? (portrait ? 230 : 220) : height * .27,
      width:headingWidth, opacity:enter, textAlign:shot.image ? 'left' : 'center',
      transform:`translateY(${(1 - enter) * 30}px)`}}>
      <div style={{color:'#fff', fontWeight:800, fontSize:heading.size, lineHeight:1.22}}>
        {heading.lines.map((line, index) => <div key={index}>{line}</div>)}
      </div>
      <div style={{height:6, width:290 * enter, margin:shot.image ? '30px 0 0' : '30px auto 0',
        borderRadius:8, background:'linear-gradient(90deg,#67cddd,#167b94)'}}/>
    </div>
    {shot.image ? <div style={{position:'absolute', left:portrait ? 68 : 1040, top:portrait ? 570 : 165,
      width:portrait ? width - 136 : width - 1140, height:portrait ? 790 : 590,
      borderRadius:portrait ? 35 : 27, overflow:'hidden', background:'#164251',
      border:'1px solid rgba(218,248,251,.27)', boxShadow:'0 26px 75px rgba(0,15,22,.27)', opacity:enter,
      transform:`translateY(${(1 - enter) * 30}px)`}}>
      <Img src={staticFile(shot.image)} style={{height:'100%', width:'100%', objectFit:'contain'}}/>
    </div> : null}
    {caption ? <div style={{position:'absolute', left:padding, right:padding, top:height * .78, height:height * .13,
      display:'flex', alignItems:'center', justifyContent:'center', boxSizing:'border-box', padding:24,
      borderRadius:22, background:'rgba(10,45,57,.96)', border:'1px solid rgba(105,208,224,.38)', opacity:enter}}>
      <div style={{textAlign:'center', fontSize:caption.size, color:'#f0fbfc', fontWeight:600, lineHeight:1.35}}>
        {caption.lines.map((line, index) => <div key={index}>{line}</div>)}
      </div>
    </div> : null}
    <div style={{position:'absolute', left:padding, right:padding, bottom:portrait ? 123 : 28, display:'flex', gap:9}}>
      {shots.map((_, index) => <div key={index} style={{flex:1, height:6, borderRadius:7,
        background:index <= number - 1 ? '#5cc5d5' : 'rgba(140,194,206,.2)'}}/>)}
    </div>
  </AbsoluteFill>;
};

export const Quick:React.FC = () => <AbsoluteFill style={{background:'#082733'}}>
  {shots.map((shot, index) => <Sequence key={index} from={index === 0 ? 0 : cutoffs[index - 1]} durationInFrames={shot.frames}>
    <Scene shot={shot} number={index + 1}/>
    {shot.audio ? <Audio src={staticFile(shot.audio)} volume={.95}/> : null}
  </Sequence>)}
</AbsoluteFill>;
