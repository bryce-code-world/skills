import React from 'react';
import {Composition,registerRoot} from 'remotion';
import {Quick} from './Quick';
import config from '../shotlist.json';

const Root:React.FC=()=> <Composition id="QuickVideo" component={Quick}
  durationInFrames={config.shots.reduce((total,shot)=>total+shot.frames,0)}
  fps={config.fps} width={config.width} height={config.height}
  defaultProps={{bgm:true}}/>;
registerRoot(Root);
