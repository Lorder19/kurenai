#!/usr/bin/env python3
"""Builds docs/index.html, docs/ru/index.html and docs/zh/index.html from strings.py and style.css.
Run from anywhere: python3 site/build.py"""
import html, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
import sys; sys.path.insert(0, str(ROOT / "site"))
from strings import LANGS

CSS = (ROOT / "site/style.css").read_text()
KANJI = re.search(r'<path fill="#b3121f"[^>]* d="([^"]+)"', (ROOT / "Icon/logo/icon.svg").read_text()).group(1)
BASE = "https://lorder19.github.io/kurenai/"
APPLE = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.4 12.6c0-2.4 2-3.6 2.1-3.7-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.9-3.2-.8-1.6 0-3.1 1-4 2.4-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.8 2.5 3 2.4 1.2 0 1.7-.8 3.1-.8 1.5 0 1.9.8 3.2.8 1.3 0 2.1-1.2 2.9-2.4.9-1.4 1.3-2.7 1.3-2.8 0 0-2.4-.9-2.4-3.9zM14 5.4c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1.1.1 2.1-.6 2.8-1.4z"/></svg>'
DL = "https://github.com/Lorder19/kurenai/releases/latest"


def page(t):
    p = t["p"]
    langs = "".join(
        f'<a href="{p}{o["dir"]}"' + (' aria-current="page"' if o["lang"] == t["lang"] else "") + f'>{ {"en": "EN", "ru": "RU", "zh-Hans": "中文"}[o["lang"]] }</a>'
        for o in LANGS)
    hreflang = "\n".join(f'<link rel="alternate" hreflang="{o["lang"]}" href="{BASE}{o["dir"]}">' for o in LANGS)
    keys = "".join(f'<div class="cap"><kbd>{k}</kbd>{v}</div>' for k, v in t["keys"])
    src = "".join(f"<li>{html.escape(s)}</li>" for s in t["src"])
    priv = "".join(f"<li>{s}</li>" for s in t["priv"])
    steps = "".join(f"<li>{s}</li>" for s in t["steps"])
    faq = "".join(f"<details><summary>{q}</summary><p>{a}</p></details>" for q, a in t["faq"])
    c = t["chips"]
    return f"""<!doctype html>
<html lang="{t['lang']}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{t['title']}</title>
<meta name="description" content="{t['desc']}">
{hreflang}
<link rel="alternate" hreflang="x-default" href="{BASE}">
<link rel="canonical" href="{BASE}{t['dir']}">
{t['extra_meta']}
<link rel="icon" href="{p}icon.png">
<meta name="theme-color" content="#f5f1ea" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0f0e0e" media="(prefers-color-scheme: dark)">
<meta property="og:title" content="Kurenai">
<meta property="og:description" content="{t['og']}">
<meta property="og:image" content="{BASE}social.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="preload" as="image" href="{p}mascot/kurenai.png">
<style>
{CSS}</style>
</head>
<body>
<nav class="nav" id="nav"><div class="wrap">
  <a class="brand" href="{p}{t['dir']}"><img src="{p}icon.png" alt="">Kurenai</a>
  <div class="links"><a href="#features">{t['nav_features']}</a><a href="#privacy">{t['nav_privacy']}</a><a href="#install">{t['nav_install']}</a><a href="#faq">{t['nav_faq']}</a></div>
  <div class="langs">{langs}</div>
  <a class="btn sm" href="{DL}">{t['download']}</a>
</div></nav>

<header class="hero">
  <div class="glow a"></div><div class="glow b"></div>
  <div class="wrap herogrid">
    <div class="copy">
      <span class="eyebrow"><i></i>{t['eyebrow']}</span>
      <h1>{t['headline']}</h1>
      <p class="lede">{t['lede']}</p>
      <div class="actions">
        <a class="btn" href="{DL}">{APPLE}{t['cta']}</a>
        <a class="ghost" href="#play">{t['try_it']} <span>→</span></a>
      </div>
      <div class="brew"><code>brew install --cask <b>lorder19/tap/kurenai</b></code><button id="brew" data-ok="{t['copied']}">Copy</button></div>
      <p class="meta">{t['meta']}</p>
    </div>
    <div class="stage" id="stage" aria-hidden="false">
      <svg class="kanji" viewBox="190 180 650 670" aria-hidden="true"><path fill="currentColor" d="{KANJI}"/></svg>
      <div class="say" id="say" aria-live="polite"><span id="say-t"></span><span class="cur"></span></div>
      <div class="girl" id="girl"><img src="{p}mascot/kurenai.png" width="519" height="1000" alt="{t['alt_mascot']}"></div>
      <div class="chip c1"><b>1</b>{html.escape(c[0])}</div>
      <div class="chip c2"><span class="sw"></span>{html.escape(c[1])}</div>
      <div class="chip c3"><b>3</b>{html.escape(c[2])}</div>
    </div>
  </div>
  <div class="wrap"><div class="keys" id="keys">{keys}</div></div>
</header>

<main>
  <div class="wrap">
    <div class="window demo reveal"><div class="bar"><i></i><i></i><i></i><span>Kurenai</span></div>
      <img src="{p}demo.gif" width="800" alt="{t['demo_alt']}"></div>
    <div class="note reveal"><img src="{p}mascot/neutral.jpg" alt=""><p>{t['note']}<small>— {t['note_by']}</small></p></div>
  </div>

  <section id="play"><div class="wrap">
    <div class="play reveal">
      <div class="play-head"><b>{t['play_title']}</b><span>{t['play_hint_head']}</span></div>
      <div class="play-body">
        <div class="col"><h3>{t['col_src']}</h3><ul class="src" id="src">{src}</ul></div>
        <div class="col stagebox">
          <h3>{t['col_doc']}</h3>
          <div class="panel" id="panel" role="dialog" aria-label="{t['panel_label']}">
            <input id="q" placeholder="{t['search']}" autocomplete="off"><ol id="hist"></ol>
          </div>
          <textarea id="doc" placeholder="{t['doc_ph']}"></textarea>
          <div class="row"><button id="b-hist">{t['b_hist']}</button><button id="b-queue" aria-pressed="false">{t['b_queue']}</button><button id="b-clear">{t['b_clear']}</button></div>
          <ol class="queue" id="queue"></ol>
          <p class="hint" id="hint">{t['hint']}</p>
          <div class="kr" aria-live="polite"><img id="kr-face" src="{p}mascot/neutral.jpg" alt=""><span id="kr-say">{t['kr']['start']}</span></div>
        </div>
      </div>
    </div>
  </div></section>

  <section id="features"><div class="wrap">
    <div class="reveal"><div class="kicker">{t['feat_kicker']}</div><h2>{t['feat_title']}</h2></div>
    <div class="grid">
      <div class="card reveal"><span class="k">⌘;</span><h3>{t['f_hist']}</h3><p>{t['f_hist_t']}</p></div>
      <div class="card reveal" style="--d:.08s"><span class="k">⌘I</span><h3>{t['f_list']}</h3><p>{t['f_list_t']}</p></div>
      <div class="card reveal" style="--d:.16s"><span class="k">⌘'</span><h3>{t['f_queue']}</h3><p>{t['f_queue_t']}</p></div>
      <div class="card wide reveal"><div><span class="k">⇧⌘C</span><h3>{t['f_split']}</h3><p>{t['f_split_t']}</p></div>
        <img src="{p}split.gif" width="800" height="450" loading="lazy" alt="{t['split_alt']}"></div>
    </div>
    <div class="shots reveal">
      <img src="{p}screenshots/history.png" width="560" loading="lazy" alt="{t['shot_hist']}">
      <img src="{p}screenshots/queue.png" width="260" loading="lazy" alt="{t['shot_queue']}">
    </div>
  </div></section>

  <section class="dark" id="privacy"><div class="wrap">
    <div class="reveal"><div class="kicker">{t['priv_kicker']}</div><h2>{t['priv_title']}</h2><ul class="checks">{priv}</ul></div>
    <figure class="portrait reveal" style="--d:.1s"><img src="{p}mascot/glare.jpg" loading="lazy" alt=""><figcaption>{t['priv_say']}</figcaption></figure>
  </div></section>

  <section id="install"><div class="wrap">
    <div class="reveal"><div class="kicker">{t['inst_kicker']}</div><h2>{t['inst_title']}</h2></div>
    <div class="brewline reveal">{t['brew_label']}: <div class="brew" style="margin:0"><code>brew install --cask <b>lorder19/tap/kurenai</b></code><button class="brew2" data-ok="{t['copied']}">Copy</button></div> {t['hand']}:</div>
    <ol class="steps">{steps.replace('<li>', '<li class="reveal">', 1).replace('<li>', '<li class="reveal" style="--d:.08s">', 1).replace('<li>', '<li class="reveal" style="--d:.16s">', 1)}</ol>
  </div></section>

  <section id="faq"><div class="wrap faq reveal"><h2>{t['faq_title']}</h2>{faq}</div></section>

  <div class="end wrap reveal">
    <img src="{p}mascot/smile.jpg" alt="">
    <h2>{t['end_title']}</h2><p>{t['end_sub']}</p>
    <a class="btn" href="{DL}">{APPLE}{t['cta']}</a>
  </div>
</main>

<footer><div class="wrap"><span>{t['footer']}</span><a href="https://github.com/Lorder19/kurenai">{t['source']}</a></div></footer>

<script>
{script(t)}
</script>
</body>
</html>
"""


def script(t):
    p = t["p"]
    data = json.dumps(dict(says=t["says"], kr=t["kr"], hint_win=t["hint_win"], nothing=t["nothing"], copy_first=t["copy_first"]), ensure_ascii=False)
    return f"""(() => {{
  const T = {data}, P = '{p}';
  const mac = /Mac|iPhone|iPad/.test(navigator.platform);
  const keyfix = s => mac ? s : s.replace(/⌘/g, 'Ctrl+');
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // nav turns solid once you scroll
  const nav = document.getElementById('nav');
  const onScroll = () => nav.classList.toggle('solid', scrollY > 8);
  addEventListener('scroll', onScroll, {{ passive: true }}); onScroll();

  // scroll reveal
  const io = new IntersectionObserver(es => es.forEach(e => {{ if (e.isIntersecting) {{ e.target.classList.add('in'); io.unobserve(e.target); }} }}), {{ rootMargin: '0px 0px -8% 0px' }});
  document.querySelectorAll('.reveal').forEach(el => io.observe(el));

  // the speech bubble types out a few lines in turn
  const sayT = document.getElementById('say-t');
  let si = 0;
  function typeLine() {{
    const text = keyfix(T.says[si++ % T.says.length]);
    if (still) {{ sayT.textContent = text; return setTimeout(typeLine, 4000); }}
    let i = 0;
    const tick = () => {{ sayT.textContent = text.slice(0, ++i); i < text.length ? setTimeout(tick, 38) : setTimeout(erase, 2600); }};
    const erase = () => {{ sayT.textContent = text.slice(0, --i); i > 0 ? setTimeout(erase, 16) : setTimeout(typeLine, 300); }};
    tick();
  }}
  setTimeout(typeLine, 900);

  // the mascot leans a little toward the pointer
  const girl = document.getElementById('girl'), stage = document.getElementById('stage');
  if (!still && matchMedia('(min-width: 901px) and (pointer: fine)').matches) {{
    addEventListener('pointermove', e => {{
      const x = e.clientX / innerWidth - .5, y = e.clientY / innerHeight - .5;
      girl.style.transform = `translate(${{x * -14}}px, ${{y * -8}}px)`;
      stage.querySelector('.kanji').style.transform = `translate(${{x * 18}}px, ${{y * 12}}px)`;
    }}, {{ passive: true }});
  }}

  // keycaps press themselves one by one
  const caps = [...document.querySelectorAll('.cap')];
  if (!still) {{ let k = 0; setInterval(() => {{ const c = caps[k++ % caps.length]; c.classList.add('down'); setTimeout(() => c.classList.remove('down'), 220); }}, 1100); }}
  if (!mac) caps.forEach(c => c.querySelector('kbd').textContent = keyfix(c.querySelector('kbd').textContent));

  // copy the brew command
  document.querySelectorAll('#brew, .brew2').forEach(b => b.onclick = () => {{
    navigator.clipboard?.writeText('brew install --cask lorder19/tap/kurenai').catch(() => {{}});
    const was = b.textContent; b.textContent = b.dataset.ok; b.classList.add('ok');
    setTimeout(() => {{ b.textContent = was; b.classList.remove('ok'); }}, 1400);
  }});

  // playground
  if (!mac) {{ document.getElementById('k-hist').textContent = 'Ctrl+;'; document.getElementById('hint').textContent = T.hint_win; }}
  const doc = document.getElementById('doc'), panel = document.getElementById('panel'), q = document.getElementById('q');
  const histEl = document.getElementById('hist'), queueEl = document.getElementById('queue'), qBtn = document.getElementById('b-queue');
  const krFace = document.getElementById('kr-face'), krSay = document.getElementById('kr-say');
  let history = [], queue = [], cursor = 0, sel = 0, queueOn = false;
  function react(face, text) {{
    krFace.src = P + 'mascot/' + face + '.jpg'; krSay.textContent = keyfix(text);
    krFace.classList.remove('pop'); void krFace.offsetWidth; krFace.classList.add('pop');
    setTimeout(() => krFace.classList.remove('pop'), 220);
  }}
  function copy(text, el) {{
    history = [text, ...history.filter(t => t !== text)].slice(0, 30);
    if (queueOn) queue.push(text);
    navigator.clipboard?.writeText(text).catch(() => {{}});
    if (el) {{ el.classList.remove('copied'); void el.offsetWidth; el.classList.add('copied'); }}
    renderQueue();
    react('smirk', queueOn ? T.kr.left.replace('{{n}}', queue.length - cursor) : T.kr.copied);
  }}
  function filtered() {{ const s = q.value.trim().toLowerCase(); return s ? history.filter(t => t.toLowerCase().includes(s)) : history; }}
  function renderHist() {{
    const items = filtered();
    sel = Math.min(sel, Math.max(items.length - 1, 0));
    histEl.innerHTML = '';
    if (!items.length) {{ histEl.innerHTML = '<li class="empty">' + (history.length ? T.nothing : T.copy_first) + '</li>'; return; }}
    items.forEach((t, i) => {{
      const li = document.createElement('li'); if (i === sel) li.className = 'sel';
      const n = document.createElement('i'); n.textContent = i < 9 ? i + 1 : '';
      li.append(n, document.createTextNode(t)); li.onclick = () => pick(t); histEl.append(li);
    }});
  }}
  function renderQueue() {{
    queueEl.innerHTML = '';
    if (!queueOn) return;
    queue.forEach((t, i) => {{ const li = document.createElement('li'); li.textContent = t; li.className = i < cursor ? 'used' : i === cursor ? 'next' : ''; queueEl.append(li); }});
  }}
  function insert(text) {{ const a = doc.selectionStart, b = doc.selectionEnd; doc.value = doc.value.slice(0, a) + text + doc.value.slice(b); doc.selectionStart = doc.selectionEnd = a + text.length; }}
  function openPanel() {{ q.value = ''; sel = 0; renderHist(); panel.classList.add('open'); q.focus(); }}
  function closePanel() {{ panel.classList.remove('open'); doc.focus(); }}
  function pick(t) {{ closePanel(); insert(t + '\\n'); copy(t); }}
  document.querySelectorAll('#src li').forEach(li => li.onclick = () => copy(li.textContent, li));
  document.getElementById('b-hist').onclick = openPanel;
  document.getElementById('b-clear').onclick = () => {{ doc.value = ''; queue = []; cursor = 0; renderQueue(); react('calm', T.kr.clear); }};
  qBtn.onclick = () => {{ queueOn = !queueOn; qBtn.setAttribute('aria-pressed', queueOn); queue = []; cursor = 0; renderQueue(); if (queueOn) react('neutral', T.kr.qon); }};
  const isMod = e => mac ? e.metaKey : e.ctrlKey;
  doc.addEventListener('keydown', e => {{
    if (isMod(e) && e.key === ';') {{ e.preventDefault(); openPanel(); }}
    if (isMod(e) && e.key.toLowerCase() === 'v' && queueOn && queue.length) {{
      e.preventDefault();
      if (cursor >= queue.length) cursor = 0;
      insert(queue[cursor] + '\\n'); cursor++; renderQueue();
      const n = queue.length - cursor;
      n ? react('smirk', T.kr.left.replace('{{n}}', n)) : react('smile', T.kr.done);
    }} else if (isMod(e) && e.key.toLowerCase() === 'v' && !queueOn && history.length) react('unimpressed', T.kr.qoff);
  }});
  q.addEventListener('input', () => {{ sel = 0; renderHist(); if (q.value.trim() && !filtered().length) react('unimpressed', T.kr.none); }});
  q.addEventListener('keydown', e => {{
    const items = filtered();
    if (e.key === 'Escape') {{ e.preventDefault(); closePanel(); }}
    else if (e.key === 'ArrowDown') {{ e.preventDefault(); sel = Math.min(sel + 1, items.length - 1); renderHist(); }}
    else if (e.key === 'ArrowUp') {{ e.preventDefault(); sel = Math.max(sel - 1, 0); renderHist(); }}
    else if (e.key === 'Enter' && items[sel]) {{ e.preventDefault(); pick(items[sel]); }}
    else if (isMod(e) && /^[1-9]$/.test(e.key) && items[+e.key - 1]) {{ e.preventDefault(); pick(items[+e.key - 1]); }}
  }});
  document.addEventListener('click', e => {{ if (panel.classList.contains('open') && !panel.contains(e.target) && e.target.id !== 'b-hist') closePanel(); }});
}})();"""


for t in LANGS:
    out = ROOT / "docs" / t["dir"] / "index.html"
    out.write_text(page(t))
    print("wrote", out.relative_to(ROOT))
