# Codex Deck — Stay in the flow

A 32.5-second, 1920 × 1080 / 30 fps product film with synthetic English narration, an original cinematic synth score, and English captions. The opening uses a slow product reveal; the body moves between dark phone scenes and light Mac controls. The final URL remains visible for four seconds.

## Edit and render

Open `index.html` and choose **Play with narration**. It opens on a static poster, scales to the window, and reduces movement when the system requests reduced motion.

Edit the HTML copy and `renderFrame()` timeline. To export:

```sh
npm install playwright
npx playwright install chromium
FFMPEG_BINARY=/path/to/ffmpeg node render.mjs
```

The renderer loads local assets in an isolated browser with network requests blocked. It does not control Codex. Set `PLAYWRIGHT_MODULE` or `CHROMIUM_EXECUTABLE` if using an existing runtime. The output and poster are written to the parent directory. Keep the relative `docs/images` and screenshot paths when moving the source.

## Narration and music

The included `soundtrack.m4a` is the final mix. Speech uses the stock `af_heart` voice in [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), rendered locally with [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx). It is AI-generated narration, not a recording of a person or an imitation of an OpenAI presenter.

To regenerate, install `kokoro-onnx==0.6.1`, `soundfile`, and `numpy`, then download the model and voice files linked in kokoro-onnx's setup guide to a directory outside this repository:

```sh
python make_audio.py /path/to/models
ffmpeg -y -i soundtrack.wav -af loudnorm=I=-16:TP=-1.5:LRA=9 \
  -ar 48000 -c:a aac -b:a 192k soundtrack.m4a
```

`narration.json` records the exact speech timing; `../codex-deck-intro.en.srt` contains matching captions. The score is original additive synthesis: low sustained chords, sparse accents, stereo reflections, and music ducking beneath speech. No third-party music is sampled. Model weights are not distributed here.

## Images and type

- Phone images are the project's existing AI-generated promotional mockups based on offline UI previews.
- Mac images are the user's actual screenshots; the older menu is labeled **earlier interface** in the film. The 94% usage figure is illustrative.
- Inter Tight is bundled under the SIL Open Font License; see `assets/OFL.txt`.
- This is an independent Codex Deck introduction. It does not use OpenAI branding to claim official affiliation or present the edited sequence as live integration footage.

The application version is unchanged by this media update.
