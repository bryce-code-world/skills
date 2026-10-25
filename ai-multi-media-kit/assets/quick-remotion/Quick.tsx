import React from 'react';
import {AbsoluteFill, Audio, Easing, Img, OffthreadVideo, interpolate, Sequence, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import raw from '../shotlist.json';
import timing from '../subtitles.json';
import {Director} from './Director';

type Shot = {title:string; caption:string; voiceover:string; frames:number; image:string|null;
  video?:string|null; audio:string|null; visual_mode?:'standard'|'focus'|'showcase'|'kinetic'|'reveal'|'compare'|'steps';
  visual_intent?:string;steps?:string[];before_image?:string|null;after_image?:string|null;};
type Cue = {start:number;end:number;text:string};
// The Python validator guarantees the union, JSON imports infer visual_mode as plain string.
const shots:Shot[] = raw.shots as unknown as Shot[];
const cues:Cue[] = timing.cues;
const hasTimedSubtitles = cues.length > 0;
const masterAudio:string|null = raw.narration_audio || null;
const visualStyle = 'visual_style' in raw ? String(raw.visual_style) : 'product';
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
        // Closing punctuation belongs to the preceding word/character.
        // Move that character with the punctuation rather than showing
        // a dangling comma at the start of a new subtitle line.
        if (/[，。、；：！？,.!?;:）】》”’]/u.test(char) && line.length > 1) {
          lines.push(line.slice(0, -1).trim());
          line = line.slice(-1);
        } else {
          lines.push(line.trim());
          line = '';
        }
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

const Subtitle:React.FC = () => {
  const frame=useCurrentFrame();
  const {fps,width,height}=useVideoConfig();
  const time=frame/fps;
  const cue=cues.find(item=>time>=item.start && time<item.end);
  const portrait=height>width;
  const padding=portrait?77:110;
  const layout=React.useMemo(
    ()=>cue ? fitText(cue.text,width-padding*2-48,height*.13-48,2,portrait?44:36,portrait?38:32,700,1.3):null,
    [cue?.text,width,height,padding,portrait]
  );
  if(!cue || !layout)return null;
  return <div style={{position:'absolute',zIndex:20,left:padding,right:padding,top:height*.78,
    height:height*.13,display:'flex',alignItems:'center',justifyContent:'center',
    boxSizing:'border-box',padding:24,borderRadius:22,
    background:'rgba(7,32,43,.93)',border:'1px solid rgba(105,208,224,.4)',fontFamily:font}}>
      <div style={{textAlign:'center',fontSize:layout.size,fontWeight:700,lineHeight:1.3,
        color:'#fff',textShadow:'0 2px 10px rgba(0,0,0,.55)'}}>
        {layout.lines.map((line,i)=><div key={i}>{line}</div>)}
      </div>
    </div>;
};

const Scene:React.FC<{shot:Shot; number:number}> = ({shot, number}) => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();
  const portrait = height > width;
  const enter = interpolate(frame, [0, 16], [0, 1], {...limit, easing:ease});
  const fadeOut = interpolate(frame, [shot.frames - 8, shot.frames], [1, 0], limit);
  const padding = portrait ? 77 : 110;
  const hasVisual = Boolean(shot.image || shot.video);
  const headingWidth = !hasVisual || portrait ? width - padding * 2 : 820;
  const heading = React.useMemo(
    () => fitText(shot.title, headingWidth, portrait && hasVisual ? 290 : 440, 4, portrait ? 78 : 79, 48, 800, 1.22),
    [shot.title, hasVisual, headingWidth, portrait],
  );
  const caption = React.useMemo(
    () => !hasTimedSubtitles && shot.caption ? fitText(shot.caption, width - padding * 2 - 48, height * .13 - 48, 2, portrait ? 35 : 34, 30, 600, 1.35) : null,
    [shot.caption, width, padding, height, portrait],
  );
  return <AbsoluteFill style={{background:'#082733', overflow:'hidden', opacity:fadeOut, fontFamily:font}}>
    <div style={{position:'absolute', top:-390, right:-370, width:1350, height:1350, borderRadius:'50%',
      background:'radial-gradient(circle,rgba(64,165,187,.35),transparent 68%)'}}/>
    <div style={{position:'absolute', left:padding, top:portrait ? 132 : 95,
      fontSize:25, fontWeight:700, color:'#8bdae5', letterSpacing:3}}>
      {String(number).padStart(2,'0')} / {String(shots.length).padStart(2,'0')}
    </div>
    <div style={{position:'absolute', left:padding, top:hasVisual ? (portrait ? 230 : 220) : height * .27,
      width:headingWidth, opacity:enter, textAlign:hasVisual ? 'left' : 'center',
      transform:`translateY(${(1 - enter) * 30}px)`}}>
      <div style={{color:'#fff', fontWeight:800, fontSize:heading.size, lineHeight:1.22}}>
        {heading.lines.map((line, index) => <div key={index}>{line}</div>)}
      </div>
      <div style={{height:6, width:290 * enter, margin:hasVisual ? '30px 0 0' : '30px auto 0',
        borderRadius:8, background:'linear-gradient(90deg,#67cddd,#167b94)'}}/>
    </div>
    {hasVisual ? <div style={{position:'absolute', left:portrait ? 68 : 1040, top:portrait ? 570 : 165,
      width:portrait ? width - 136 : width - 1140, height:portrait ? 790 : 590,
      borderRadius:portrait ? 35 : 27, overflow:'hidden', background:'#164251',
      border:'1px solid rgba(218,248,251,.27)', boxShadow:'0 26px 75px rgba(0,15,22,.27)', opacity:enter,
      transform:`translateY(${(1 - enter) * 30}px)`}}>
      {shot.video ? <OffthreadVideo src={staticFile(shot.video)} muted style={{height:'100%',width:'100%',objectFit:'contain'}}/> :
        shot.image ? <Img src={staticFile(shot.image)} style={{height:'100%', width:'100%', objectFit:'contain'}}/> : null}
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
  {masterAudio ? <Audio src={staticFile(masterAudio)} volume={.95}/> : null}
  {shots.map((shot, index) => <Sequence key={index} from={index === 0 ? 0 : cutoffs[index - 1]} durationInFrames={shot.frames}>
    {shot.visual_mode && shot.visual_mode !== 'standard'
      ? <Director shot={shot} number={index+1} total={shots.length} styleId={visualStyle}/>
      : <Scene shot={shot} number={index + 1}/>}
    {!masterAudio && shot.audio ? <Audio src={staticFile(shot.audio)} volume={.95}/> : null}
  </Sequence>)}
  {hasTimedSubtitles ? <Subtitle/> : null}
</AbsoluteFill>;
