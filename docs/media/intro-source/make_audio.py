"""Build the original score and synthetic English narration.

pip install kokoro-onnx==0.6.1 soundfile numpy
python make_audio.py /path/to/kokoro-model-directory
Model files: kokoro-v1.0.onnx and voices-v1.0.bin (not included in this repo).
"""
from pathlib import Path
import json
import sys
import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

HERE = Path(__file__).parent
RATE, DURATION = 48000, 32.5
SPOKEN = [
    (.65, 'Stay in the flow.'),
    (3.15, 'Meet Codex Deck.'),
    (6.1, 'Your favorite models. The reasoning you need. One shortcut.'),
    (12.2, 'Turn your phone into a control deck.'),
    (16.3, 'Tap to switch. Drag to think deeper.'),
    (21.05, "Know what's left. Keep building."),
    (26.25, 'Free. Open source. Made for your Mac.'),
]
model_dir = Path(sys.argv[1])
engine = Kokoro(str(model_dir/'kokoro-v1.0.onnx'), str(model_dir/'voices-v1.0.bin'))
size = round(RATE*DURATION)
narration = np.zeros(size)
duck = np.ones(size)
segments=[]
for index, (start, text) in enumerate(SPOKEN):
    audio, sr = engine.create(text, voice='af_heart', speed=.94, lang='en-us')
    audio = np.interp(np.arange(round(len(audio)*RATE/sr))*sr/RATE, np.arange(len(audio)), audio)
    # Normalize phrases consistently without bringing breaths above speech.
    rms=np.sqrt(np.mean(audio**2))
    audio *= min(.14/max(rms,1e-6), .76/max(np.max(np.abs(audio)),1e-6))
    duration=len(audio)/RATE
    end=start+duration
    assert end < (SPOKEN[index+1][0]-.12 if index+1<len(SPOKEN) else DURATION-.65), (text,end)
    at=round(start*RATE)
    narration[at:at+len(audio)]+=audio
    times=np.arange(size)/RATE
    gate=np.minimum(np.clip((times-start+.24)/.24,0,1),np.clip((end+.45-times)/.45,0,1))
    duck=np.minimum(duck,1-.76*gate)
    segments.append({'start':start,'end':round(end,3),'text':text})
    print(f'{start:.2f}–{end:.2f}: {text}',flush=True)

score=np.zeros((size,2))
def note(start,freq,length,gain,pan=0,pad=False):
    t=np.arange(round(RATE*length))/RATE
    env=(1-np.exp(-t/(.65 if pad else .025)))*np.exp(-t/(length*.9 if pad else 1.15))
    env*=np.clip((length-t)/(.8 if pad else .4),0,1)
    wave=np.sin(2*np.pi*freq*t)
    if pad:
        wave=.7*wave+.15*np.sin(2*np.pi*freq*1.002*t)+.15*np.sin(2*np.pi*freq*.998*t)
        wave+=.08*np.sin(4*np.pi*freq*t)
    else:
        wave+=.14*np.sin(4*np.pi*freq*t)*np.exp(-3*t)
    n=min(len(t),size-round(start*RATE)); at=round(start*RATE)
    score[at:at+n]+=wave[:n,None]*env[:n,None]*gain*np.sqrt([(1-pan)/2,(1+pan)/2])

def hz(midi): return 440*2**((midi-69)/12)
# Low orchestral-synth foundation, opening up to a warm major cadence.
for start,notes,length in [(0,[36,43,48,55,62],6.6),(5.6,[33,45,52,57,60],6.7),(11.6,[29,41,48,57,64],9.4),(20.3,[31,43,50,55,62],6.9),(25.8,[36,43,48,52,59],6.7)]:
    for i,midi in enumerate(notes): note(start,hz(midi),length,.065 if i<2 else .038,(i-2)*.27,True)
    note(start+.05,hz(notes[0]),2,.2)
    for i,midi in enumerate(notes[2:]):note(start+.18+i*.23,hz(midi+12),3,.04,(i-1)*.3)
for t in [7.5,9.1,13.2,14.8,16.4,18,22,23.6,27.4,29]:
    note(t,65.406,.8,.025)
note(8.15,hz(72),.8,.035)
note(29.5,hz(76),2.7,.045,.2)

# Sparse stereo reflections make the score spacious; speech remains dry and centered.
dry=score.copy()
for delay,gain in [(.12,.16),(.27,.1),(.43,.055)]:
    d=round(RATE*delay);score[d:]+=dry[:-d,::-1]*gain
score*=duck[:,None]
mix=score+narration[:,None]
fade=np.minimum(1,np.arange(size)/(RATE*.12))*np.minimum(1,np.arange(size)[::-1]/(RATE*1.0))
mix*=fade[:,None]
mix*=min(1,.89/max(np.max(np.abs(mix)),1e-6))
sf.write(HERE/'narration.wav',narration,RATE,subtype='PCM_16')
sf.write(HERE/'soundtrack.wav',mix,RATE,subtype='PCM_16')
(HERE/'narration.json').write_text(json.dumps(segments,indent=2)+'\n')
def stamp(t):
    ms=round(t*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'
(HERE.parent/'codex-deck-intro.en.srt').write_text('\n\n'.join(f'{i+1}\n{stamp(s["start"])} --> {stamp(s["end"])}\n{s["text"]}' for i,s in enumerate(segments))+'\n')
print(f'Created {DURATION}s soundtrack and English captions.',flush=True)
