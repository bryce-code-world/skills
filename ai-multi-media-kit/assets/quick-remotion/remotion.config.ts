import {Config} from '@remotion/cli/config';

Config.setVideoImageFormat('jpeg');
Config.setOverwriteOutput(false);
// New projects store real media once, in the Chinese user-facing asset directory.
// The project-local Remotion working directory is 99-专业工程.
Config.setPublicDir(require('node:path').resolve(process.cwd(), '..', '02-媒体素材'));
