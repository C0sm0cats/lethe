# The README banner: python3 docs/make_banner.py writes docs/banner.svg, then
# rsvg-convert -w 2560 docs/banner.svg -o docs/banner.png && zopflipng -y -m docs/banner.png docs/banner.png
import math, os, random, sys

# The wordmark stands on the river and is mirrored in it. Old session titles drift in on
# the current from the left and, as they reach Lethe, break apart into glints of light.
random.seed(3)
W, H, RX = 1280, 320, 24
HZ = 172           # waterline
CX = 640           # wordmark axis
MONO = 'JetBrains Mono, DejaVu Sans Mono, monospace'
SERIF = 'Noto Serif Display, Georgia, DejaVu Serif, serif'
SANS = 'Noto Sans, DejaVu Sans, Helvetica, Arial, sans-serif'
out = []
e = out.append
def esc(t): return t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

e(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
e(f'''<defs>
<clipPath id="card"><rect width="{W}" height="{H}" rx="{RX}"/></clipPath>
<linearGradient id="sky" x1="0" y1="0" x2="0" y2="{HZ}" gradientUnits="userSpaceOnUse">
 <stop offset="0" stop-color="#04060d"/><stop offset="0.65" stop-color="#0a1126"/><stop offset="1" stop-color="#14254f"/>
</linearGradient>
<linearGradient id="water" x1="0" y1="{HZ}" x2="0" y2="{H}" gradientUnits="userSpaceOnUse">
 <stop offset="0" stop-color="#0e3448"/><stop offset="0.3" stop-color="#0a2236"/><stop offset="0.75" stop-color="#060d1c"/><stop offset="1" stop-color="#04060d"/>
</linearGradient>
<radialGradient id="halo" cx="{CX}" cy="{HZ}" r="460" gradientUnits="userSpaceOnUse" gradientTransform="translate(0 {HZ}) scale(1 0.3) translate(0 -{HZ})">
 <stop offset="0" stop-color="#5eead4" stop-opacity="0.32"/><stop offset="0.45" stop-color="#38bdf8" stop-opacity="0.10"/><stop offset="1" stop-color="#38bdf8" stop-opacity="0"/>
</radialGradient>
<linearGradient id="refl" x1="0" y1="{HZ}" x2="0" y2="{HZ+100}" gradientUnits="userSpaceOnUse">
 <stop offset="0" stop-color="#fff" stop-opacity="0.45"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
</linearGradient>
<mask id="fadeRefl"><rect x="0" y="{HZ}" width="{W}" height="{H-HZ}" fill="url(#refl)"/></mask>
<linearGradient id="hue" x1="0" y1="0" x2="{W}" y2="0" gradientUnits="userSpaceOnUse">
 <stop offset="0" stop-color="#e0f2fe"/><stop offset="0.28" stop-color="#bae6fd"/>
 <stop offset="0.5" stop-color="#5eead4"/><stop offset="0.75" stop-color="#a78bfa"/><stop offset="1" stop-color="#818cf8"/>
</linearGradient>
<filter id="ripple" x="-5%" y="-5%" width="110%" height="110%">
 <feTurbulence type="fractalNoise" baseFrequency="0.003 0.10" numOctaves="2" seed="4"/>
 <feDisplacementMap in="SourceGraphic" scale="11" xChannelSelector="R" yChannelSelector="G"/>
 <feGaussianBlur stdDeviation="1.0"/>
</filter>
<filter id="b1" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="0.45"/></filter>
<filter id="b2" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="1.0"/></filter>
<filter id="b3" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="1.8"/></filter>
<filter id="bloom" x="-20%" y="-200%" width="140%" height="500%"><feGaussianBlur stdDeviation="2.2"/></filter>
</defs>''')
e('<g clip-path="url(#card)">')
e(f'<rect width="{W}" height="{HZ}" fill="url(#sky)"/><rect y="{HZ}" width="{W}" height="{H-HZ}" fill="url(#water)"/>')
e(f'<rect width="{W}" height="{H}" fill="url(#halo)"/>')

# stars, denser and brighter higher up
for _ in range(130):
    x, y = random.uniform(0, W), random.uniform(0, HZ - 12)
    r = random.choice([0.45, 0.6, 0.75, 0.9, 1.2])
    e(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="#e2e8f0" opacity="{random.uniform(0.1, 0.6) * (0.35 + 0.65 * (1 - y / HZ)):.2f}"/>')

WM = (f'<text x="{CX}" y="{{y}}" text-anchor="middle" font-family="{SERIF}" font-weight="300" '
      f'font-size="134" letter-spacing="6" fill="#f5f8fc">lethe</text>')
e(f'<g mask="url(#fadeRefl)"><g filter="url(#ripple)"><g transform="translate(0 {2*HZ}) scale(1 -1)">{WM.format(y=HZ-4)}</g></g></g>')

# faint long swells across the whole river, so the right bank is water, not void
for _ in range(90):
    y = HZ + 3 + (H - HZ - 40) * random.random() ** 1.4
    d = (y - HZ) / (H - HZ)
    x = random.uniform(0, W); w = random.uniform(20, 120) * (0.5 + d)
    e(f'<ellipse cx="{x:.0f}" cy="{y:.1f}" rx="{w/2:.1f}" ry="{0.4+0.5*d:.2f}" fill="#7dd3fc" opacity="{random.uniform(0.03,0.10):.3f}"/>')

frags = ['Fix the token refresh race in auth', 'run the test suite', 'Add dark mode to the settings page',
         'claude --resume 7f3a2c', 'Migrate the blog to Astro', 'codex resume 019a1e', 'Plan the Q4 roadmap',
         'Profile the renderer', '{"type":"user","message":', 'Benchmark the JSON parsers', 'why is CI red again',
         'Rename the env vars', 'Bisect the flaky test', 'Draft the API spec', 'Write the release notes',
         'subagent: Kepler', '"role":"assistant"', 'Clean up old branches', 'Debug the websocket reconnect',
         'Upgrade to Postgres 17', 'Explain this regex', 'Port the CLI to Rust?', 'Fix flaky e2e login',
         'Summarize the incident', 'Add retries to the uploader', 'Translate the docs', 'Split the monolith',
         'Tune the cache TTLs', 'Review PR #482', 'Why does the build hang', 'Sketch the onboarding flow',
         'Index the session logs', 'Pin the Node version', 'Write a haiku about bash']
random.shuffle(frags)
bins = {0: [], 1: [], 2: [], 3: []}
glints = []
motes = []
# rows of the current, in perspective: further = higher, smaller, fainter
rows = [(185, 8.5, 0.30), (201, 10.0, 0.40), (221, 12.0, 0.50), (247, 14.5, 0.60)]
k = 0
for j, (y0, fs, op0) in enumerate(rows):
    adv = fs * 0.6
    line = ''
    while len(line) * adv < W + 200:
        line += frags[k % len(frags)] + ' ' * 5; k += 1
    x = -random.uniform(0, 120)
    start = 230 + 45 * j + random.uniform(-30, 30)   # where forgetting begins on this row
    span = 540 + random.uniform(-30, 30)
    for ch in line:
        x += adv
        if x > W + 10: break
        if x < -10 or ch == ' ': continue
        t = max(0.0, min(1.0, (x - start) / span))   # 0 remembered .. 1 forgotten
        y = y0 + 1.5 * math.sin(x / 75 + j * 1.7)
        if t > 0.1 and random.random() < t ** 1.5:
            # the letter comes apart: first a soft mote of light, then a thin glint on the water
            if t < 0.5:
                motes.append((x + adv / 2, y - fs * 0.33 - random.uniform(0, 3) * t, adv * 0.6, fs * 0.26, op0 * 0.5))
            elif random.random() < 0.85 - 0.6 * t ** 3:
                gw = adv * random.uniform(0.6, 1.8) * (1 + 1.5 * t)
                gy = y - fs * 0.15 + random.gauss(0, 1) * 3 * t
                go = op0 * 1.3 * (1 - 0.7 * t ** 2)
                glints.append((x + adv / 2 + random.gauss(0, 2) * t, gy, gw / 2, 0.35 + 0.35 * fs / 13, go))
            continue
        dy = random.gauss(0, 1) * 2.5 * t ** 1.4 - 2 * t   # loosened letters bob and lift
        rot = random.gauss(0, 1) * 22 * t ** 1.8
        op = op0 * (1 - 0.55 * t) * min(1, (x + 10) / 90)
        b = 0 if t < 0.04 else 1 if t < 0.28 else 2 if t < 0.55 else 3
        tr = f'translate({x:.1f},{y+dy:.1f})' + (f' rotate({rot:.0f})' if abs(rot) >= 1 else '')
        bins[b].append(f'<text transform="{tr}" font-size="{fs}" opacity="{op:.2f}">{esc(ch)}</text>')
# downstream of Lethe only light is left, thinning out towards the right bank
for _ in range(170):
    x = random.uniform(800, W); y = HZ + 6 + 92 * random.random() ** 1.2
    d = (y - HZ) / 90
    w = random.uniform(3, 16) * (0.6 + d)
    glints.append((x, y, w / 2, 0.35 + 0.45 * d, random.uniform(0.08, 0.4) * (1 - (x - 800) / 560)))
for b, f in [(0, ''), (1, ' filter="url(#b1)"'), (2, ' filter="url(#b2)"'), (3, ' filter="url(#b3)"')]:
    e(f'<g font-family="{MONO}" fill="url(#hue)"{f}>')
    out.extend(bins[b]); e('</g>')
ell = [f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{rx:.1f}" ry="{ry:.2f}" opacity="{min(1, o):.2f}"/>' for x, y, rx, ry, o in glints]
mot = [f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{rx:.1f}" ry="{ry:.2f}" opacity="{min(1, o):.2f}"/>' for x, y, rx, ry, o in motes]
e('<g fill="url(#hue)" filter="url(#bloom)" opacity="0.9">'); out.extend(ell + mot); e('</g>')
e('<g fill="url(#hue)">'); out.extend(ell); e('</g>')

# waterline, brightest beneath the wordmark
e(f'<linearGradient id="line" x1="0" y1="0" x2="{W}" y2="0" gradientUnits="userSpaceOnUse">'
  '<stop offset="0" stop-color="#99f6e4" stop-opacity="0.08"/><stop offset="0.5" stop-color="#99f6e4" stop-opacity="0.55"/>'
  '<stop offset="1" stop-color="#99f6e4" stop-opacity="0.08"/></linearGradient>')
e(f'<rect x="0" y="{HZ-0.4:.1f}" width="{W}" height="0.9" fill="url(#line)"/>')
e(WM.format(y=HZ - 4))
e(f'<text x="{CX}" y="40" text-anchor="middle" font-family="Noto Serif, Georgia, DejaVu Serif, serif" font-size="16" letter-spacing="6.5" '
  f'fill="#8bd8fb">ΛΗΘΗ · THE RIVER OF FORGETTING</text>')
e(f'<text x="{CX}" y="{H-24}" text-anchor="middle" font-family="{SANS}" font-size="21" '
  f'fill="#dbe4ef">Browse, resume and forget your Claude Code and Codex sessions</text>')
e('</g>')
e(f'<rect x="0.5" y="0.5" width="{W-1}" height="{H-1}" rx="{RX-0.5}" fill="none" stroke="#ffffff" stroke-opacity="0.09"/>')
e('</svg>')
dst = sys.argv[1] if len(sys.argv) > 1 else os.path.join('docs', 'banner.svg') if os.path.isdir('docs') else 'banner.svg'
open(dst, 'w').write('\n'.join(out))
