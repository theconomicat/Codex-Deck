// npm install playwright; npx playwright install chromium
// FFMPEG_BINARY=/path/to/ffmpeg node render.mjs
// Optional: PLAYWRIGHT_MODULE=/path/to/playwright and CHROMIUM_EXECUTABLE=/path/to/chromium
// This renderer loads only the authored video document. No server or Codex connection.
import { createRequire } from 'node:module';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const here = dirname(fileURLToPath(import.meta.url));
let html = await readFile(join(here, 'index.html'), 'utf8');
for (const path of ['../../images/codex-deck-phone.png', '../../images/codex-deck-phone-portrait.png', '../../app-menu.png', '../../menu-bar-preview.png', 'assets/InterTight.ttf']) {
  const type = path.endsWith('.ttf') ? 'font/ttf' : 'image/png';
  html = html.replaceAll(path, `data:${type};base64,${(await readFile(join(here,path))).toString('base64')}`);
}
const browser = await chromium.launch({headless: true, ...(process.env.CHROMIUM_EXECUTABLE ? {executablePath:process.env.CHROMIUM_EXECUTABLE} : {})});
const page = await browser.newPage({viewport:{width:1920,height:1080},deviceScaleFactor:1});
await page.route('**/*', route => route.abort());
await page.setContent(html, {waitUntil:'load'});
await page.evaluate(async()=>{document.getElementById('play').style.display='none';await document.fonts.ready;await Promise.all([...document.images].map(image=>image.decode()));});
const output = join(here, '..', 'codex-deck-intro.mp4');
const ffmpeg = spawn(process.env.FFMPEG_BINARY || 'ffmpeg', [
  '-y','-hide_banner','-loglevel','warning','-f','image2pipe','-framerate','30','-vcodec','mjpeg','-i','pipe:0',
  '-i',join(here,'soundtrack.m4a'),'-map','0:v:0','-map','1:a:0','-c:v','libx264','-preset','medium',
  '-crf','18','-vf','scale=in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p',
  '-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709',
  '-pix_fmt','yuv420p','-r','30','-c:a','copy',
  '-t','32.5','-movflags','+faststart',output
], {stdio:['pipe','inherit','inherit']});
const finished = once(ffmpeg,'close');
try {
  for (let frame=0;frame<975;frame++) {
    await page.evaluate(t=>renderFrame(t,{exporting:true}),frame/30);
    await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
    const bytes = await page.screenshot({type:'jpeg',quality:97,scale:'css'});
    if (!ffmpeg.stdin.write(bytes)) await once(ffmpeg.stdin,'drain');
    if (frame%90===0) console.log(`Rendered ${frame}/975 frames`);
  }
  ffmpeg.stdin.end();
  const [code]=await finished;
  if (code!==0) throw new Error(`FFmpeg exited with ${code}`);
  await page.evaluate(()=>renderFrame(30,{exporting:true,poster:true}));
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  await writeFile(join(here,'..','codex-deck-intro-poster.jpg'),await page.screenshot({type:'jpeg',quality:90,scale:'css'}));
  console.log(output);
} finally {
  if (!ffmpeg.stdin.destroyed) ffmpeg.stdin.destroy();
  await browser.close();
}
