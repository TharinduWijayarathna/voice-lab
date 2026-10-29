"""VoiceLab's engine: the Kokoro voice model, pronunciations, and the clips ("takes") saved on disk."""
import json, os, re, sys, threading, time, uuid

import numpy as np
import soundfile as sf

APP_NAME = 'VoiceLab'
DATA_DIR = os.environ.get('VOICELAB_DATA') or os.path.expanduser(f'~/Library/Application Support/{APP_NAME}')
MODEL_DIR = os.environ.get('KOKORO_DIR') or os.path.join(DATA_DIR, 'models')
MODEL_FILE = 'kokoro-v1.0.onnx'
VOICES_FILE = 'voices-v1.0.bin'
DEFAULT_OUT = os.path.expanduser(f'~/Documents/{APP_NAME}')

# The voices, grouped as people would look for them. Grades are from the model's own voice notes; the best come first.
GROUPS = [
    ('af', 'American women', 'en-us'), ('am', 'American men', 'en-us'),
    ('bf', 'British women', 'en-gb'), ('bm', 'British men', 'en-gb'),
    ('e', 'Spanish', 'es'), ('f', 'French', 'fr-fr'), ('h', 'Hindi', 'hi'),
    ('i', 'Italian', 'it'), ('p', 'Portuguese (Brazil)', 'pt-br'),
]
GRADE = {
    'af_heart': 'A', 'af_bella': 'A-', 'af_nicole': 'B-', 'af_aoede': 'C+', 'af_kore': 'C+', 'af_sarah': 'C+',
    'af_nova': 'C', 'af_alloy': 'C', 'af_sky': 'C-', 'af_jessica': 'D', 'af_river': 'D',
    'am_fenrir': 'C+', 'am_michael': 'C+', 'am_puck': 'C+', 'am_echo': 'D', 'am_eric': 'D', 'am_liam': 'D',
    'am_onyx': 'D', 'am_santa': 'D-', 'am_adam': 'F+',
    'bf_emma': 'B-', 'bf_isabella': 'C', 'bf_alice': 'D', 'bf_lily': 'D',
    'bm_george': 'C', 'bm_fable': 'C', 'bm_lewis': 'D+', 'bm_daniel': 'D',
}
RANK = {g: i for i, g in enumerate(['A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D+', 'D', 'D-', 'F+', 'F'])}

DEFAULT_LEXICON = []
DEFAULT_SETTINGS = {
    'voice': 'af_heart', 'speed': 1.0, 'pause': 0.25, 'mix_voice': '', 'mix': 0.3,
    'split': False, 'out_dir': DEFAULT_OUT, 'draft': '',
}


def _read_json(path, fallback):
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return fallback


def _write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def safe_name(s, n=48):
    s = re.sub(r'[\\/:*?"<>|\n\r\t]+', ' ', s).strip()
    s = re.sub(r'\s+', ' ', s)
    return (s[:n].rstrip(' .') or 'Clip')


def title_from(text):
    text = re.sub(r'\s+', ' ', text).strip()
    if len(text.split(' ')) <= 8:
        return text
    first = re.split(r'(?<=[.!?])\s', text, 1)[0]
    words = first.split(' ')
    if len(words) <= 8:
        return first
    return ' '.join(words[:7]).rstrip(',;:') + '…'


class Studio:
    def __init__(self):
        os.makedirs(DATA_DIR, exist_ok=True)
        self.settings = {**DEFAULT_SETTINGS, **_read_json(os.path.join(DATA_DIR, 'settings.json'), {})}
        self.lexicon = _read_json(os.path.join(DATA_DIR, 'pronunciations.json'), DEFAULT_LEXICON)
        self.kokoro = None
        self.error = None
        self.voices = []
        self.lock = threading.Lock()
        self.takes = []
        self._load_takes()
        threading.Thread(target=self._load_model, daemon=True).start()

    # ---- the model -------------------------------------------------------
    def _load_model(self):
        try:
            m, v = os.path.join(MODEL_DIR, MODEL_FILE), os.path.join(MODEL_DIR, VOICES_FILE)
            if not (os.path.exists(m) and os.path.exists(v)):
                raise FileNotFoundError(f'The voice model isn\'t installed. Run install.command again to download it into {MODEL_DIR}.')
            from kokoro_onnx import Kokoro, EspeakConfig
            k = Kokoro(m, v, espeak_config=EspeakConfig(data_path=self._espeak_data()))
            have = set(k.get_voices())
            voices = []
            for prefix, group, lang in GROUPS:
                ids = [x for x in have if x.split('_')[0] == prefix or (len(prefix) == 1 and x[0] == prefix)]
                ids.sort(key=lambda x: (RANK.get(GRADE.get(x, 'D'), 9), x))
                for x in ids:
                    voices.append({
                        'id': x, 'name': x.split('_', 1)[1].replace('_', ' ').title(), 'group': group, 'lang': lang,
                        'gender': 'female' if x[1] == 'f' else 'male',
                        'best': GRADE.get(x, 'D') in ('A', 'A-', 'B+', 'B', 'B-'),
                    })
            self.voices = voices
            self.kokoro = k
        except Exception as e:  # shown in the window
            self.error = str(e)

    @staticmethod
    def _espeak_data():
        """espeak-ng (which turns words into sounds) only reads its data from a short path without spaces,
        so when its folder sits somewhere long, keep a copy in a short place."""
        import shutil, tempfile
        import espeakng_loader
        dp = espeakng_loader.get_data_path()
        if ' ' not in dp and len(dp) < 140:
            return dp
        base = os.path.expanduser('~/Library/Caches') if sys.platform == 'darwin' else tempfile.gettempdir()
        short = os.path.join(base, 'voicelab-espeak')
        if ' ' in short or len(short) >= 140:
            short = os.path.join(tempfile.gettempdir(), 'voicelab-espeak')
        stamp = os.path.join(short, '.from')
        if _read_json(stamp, None) != dp:
            shutil.rmtree(short, ignore_errors=True)
            shutil.copytree(dp, short)
            _write_json(stamp, dp)
        return short

    def voice_lang(self, vid):
        for v in self.voices:
            if v['id'] == vid:
                return v['lang']
        return 'en-us'

    # ---- pronunciations --------------------------------------------------
    def _phonemes(self, text, lang):
        """Text → the model's sounds, with the pronunciation list applied. Returns (input, is_phonemes)."""
        sounds, respell = {}, []
        for e in self.lexicon:
            w, say = (e.get('word') or '').strip(), (e.get('say') or '').strip()
            if not w or not say:
                continue
            if len(say) > 1 and say[0] == '/' and say[-1] == '/':
                sounds[w.lower()] = say[1:-1].strip()
            else:
                respell.append((w, say))
        for w, say in respell:
            text = re.sub(r'(?<![\w])' + re.escape(w) + r'(?![\w])', say, text, flags=re.I)
        if not sounds:
            return text, False
        pat = re.compile(r'(?<![\w])(' + '|'.join(re.escape(w) for w in sorted(sounds, key=len, reverse=True)) + r')(?![\w])', re.I)
        if not pat.search(text):
            return text, False
        out = []
        for i, part in enumerate(pat.split(text)):
            if i % 2:
                out.append(sounds[part.lower()])
            elif part.strip():
                out.append(self.kokoro.tokenizer.phonemize(part, lang))
            else:
                out.append(part)
        return ''.join(out), True

    def _style(self, voice, mix_voice, mix):
        if mix_voice and mix_voice != voice and mix > 0:
            a, b = self.kokoro.get_voice_style(voice), self.kokoro.get_voice_style(mix_voice)
            return (a * (1 - mix) + b * mix).astype(np.float32)
        return voice

    def synth(self, text, voice, speed=1.0, pause=0.25, mix_voice='', mix=0.0):
        if not self.kokoro:
            raise RuntimeError(self.error or 'The voice model is still loading.')
        lang = self.voice_lang(voice)
        inp, is_ph = self._phonemes(text, lang)
        with self.lock:
            a, sr = self.kokoro.create(inp, voice=self._style(voice, mix_voice, mix), speed=float(speed), lang=lang,
                                       is_phonemes=is_ph, sentence_pause=float(pause), clause_pause=float(pause) * .4)
        idx = np.where(np.abs(a) > .008)[0]
        if len(idx):
            a = a[max(0, idx[0] - int(.03 * sr)): idx[-1] + int(.08 * sr)]
        return a.astype(np.float32), sr

    # ---- takes -----------------------------------------------------------
    @property
    def out_dir(self):
        return self.settings.get('out_dir') or DEFAULT_OUT

    def _index_path(self):
        return os.path.join(self.out_dir, '.voicelab.json')

    def _load_takes(self):
        takes = _read_json(self._index_path(), [])
        self.takes = [t for t in takes if os.path.exists(os.path.join(self.out_dir, t['file']))]

    def _save_takes(self):
        _write_json(self._index_path(), self.takes)

    def _next_number(self):
        n = 0
        for t in self.takes:
            m = re.match(r'(\d+)', t['file'])
            if m:
                n = max(n, int(m.group(1)))
        return n + 1

    @staticmethod
    def peaks(a, bins=160):
        if not len(a):
            return [0] * bins
        chunks = np.array_split(np.abs(a), bins)
        p = np.array([c.max() if len(c) else 0 for c in chunks])
        top = max(p.max(), 1e-6)
        return [round(float(x / top), 3) for x in p]

    def make_takes(self, text, voice, speed, pause, mix_voice, mix, split, at=0):
        text = text.strip()
        if not text:
            raise ValueError('Type something to say first.')
        pieces = [l.strip() for l in text.split('\n') if l.strip()] if split else [re.sub(r'\s*\n\s*', ' ', text)]
        made = []
        os.makedirs(self.out_dir, exist_ok=True)
        for piece in pieces:
            a, sr = self.synth(piece, voice, speed, pause, mix_voice, mix)
            n = self._next_number()
            title = title_from(piece)
            fname = f'{n:03d} {safe_name(title.rstrip("…"))}.wav'
            sf.write(os.path.join(self.out_dir, fname), a, sr, subtype='PCM_16')
            take = {
                'id': uuid.uuid4().hex[:10], 'file': fname, 'title': title, 'text': piece, 'voice': voice,
                'mix_voice': mix_voice if mix > 0 else '', 'mix': mix, 'speed': speed, 'pause': pause,
                'seconds': round(len(a) / sr, 2), 'peaks': self.peaks(a), 'created': time.time(),
            }
            self.takes.insert(min(max(int(at), 0), len(self.takes)), take)
            at += 1
            self._save_takes()
            made.append(take)
        return made

    def find(self, tid):
        for t in self.takes:
            if t['id'] == tid:
                return t
        raise KeyError('That clip is gone.')

    def rename(self, tid, title):
        t = self.find(tid)
        title = re.sub(r'\s+', ' ', title).strip() or t['title']
        m = re.match(r'(\d+)', t['file'])
        new = f'{m.group(1) if m else "000"} {safe_name(title)}.wav'
        if new != t['file']:
            base, i = new[:-4], 2
            while os.path.exists(os.path.join(self.out_dir, new)):
                new = f'{base} ({i}).wav'; i += 1
            os.rename(os.path.join(self.out_dir, t['file']), os.path.join(self.out_dir, new))
            t['file'] = new
        t['title'] = title
        self._save_takes()
        return t

    def delete(self, tid):
        """Forget a clip. The app moves the file to the Bin itself (so Finder's "Put Back" works);
        if the file is still here, move it to the Bin from here."""
        t = self.find(tid)
        p = os.path.join(self.out_dir, t['file'])
        if os.path.exists(p):
            trash = os.path.expanduser('~/.Trash')
            dest, i = os.path.join(trash, t['file']), 2
            while os.path.exists(dest):
                dest = os.path.join(trash, f'{t["file"][:-4]} ({i}).wav'); i += 1
            try:
                os.rename(p, dest)
            except OSError:
                os.remove(p)
        self.takes = [x for x in self.takes if x['id'] != tid]
        self._save_takes()

    # ---- voice samples and word tests (kept in a cache, not the clips folder) ----
    def sample(self, voice, mix_voice='', mix=0.0):
        cache = os.path.join(DATA_DIR, 'samples')
        os.makedirs(cache, exist_ok=True)
        blend = mix_voice and mix_voice != voice and mix > 0
        p = os.path.join(cache, f'{voice}+{mix_voice}-{round(mix * 100)}.wav' if blend else f'{voice}.wav')
        if not os.path.exists(p):
            v = next((x for x in self.voices if x['id'] == voice), None)
            name = v['name'] if v else 'this voice'
            line = {
                'es': f'Hola, soy {name}. Así es como sueno.', 'fr-fr': f'Bonjour, je suis {name}. Voici ma voix.',
                'hi': f'नमस्ते, मैं {name} हूँ। मेरी आवाज़ ऐसी है।', 'it': f'Ciao, sono {name}. Questa è la mia voce.',
                'pt-br': f'Olá, eu sou {name}. É assim que eu falo.',
            }.get(self.voice_lang(voice), f"Hi, I'm {name}. This is how I sound when I read your script.")
            if blend:
                line = "Hi there. This is how this blend sounds when it reads your script."
            a, sr = self.synth(line, voice, mix_voice=mix_voice if blend else '', mix=mix if blend else 0)
            sf.write(p, a, sr, subtype='PCM_16')
        return p

    def test_word(self, word, say, voice):
        cache = os.path.join(DATA_DIR, 'samples')
        os.makedirs(cache, exist_ok=True)
        p = os.path.join(cache, '_word.wav')
        saved = self.lexicon
        self.lexicon = [{'word': word, 'say': say}] + [e for e in saved if e.get('word', '').lower() != word.lower()]
        try:
            a, sr = self.synth(word, voice)
        finally:
            self.lexicon = saved
        sf.write(p, a, sr, subtype='PCM_16')
        return p

    # ---- saving settings -------------------------------------------------
    def update_settings(self, patch):
        old_out = self.out_dir
        for k in DEFAULT_SETTINGS:
            if k in patch:
                self.settings[k] = patch[k]
        _write_json(os.path.join(DATA_DIR, 'settings.json'), self.settings)
        if self.out_dir != old_out:
            self._load_takes()

    def set_lexicon(self, entries):
        self.lexicon = [{'word': str(e.get('word', '')).strip(), 'say': str(e.get('say', '')).strip()} for e in entries]
        _write_json(os.path.join(DATA_DIR, 'pronunciations.json'), self.lexicon)
