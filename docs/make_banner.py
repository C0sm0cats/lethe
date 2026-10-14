# The README banner: python3 docs/make_banner.py writes docs/banner.svg, then
# rsvg-convert -w 2560 docs/banner.svg -o docs/banner.png
import math, random
random.seed(7)
W, H = 1280, 320
o = []
o.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
o.append('''<defs>
<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#0b0f17"/><stop offset="1" stop-color="#111827"/>
</linearGradient>
<linearGradient id="river" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#2dd4bf" stop-opacity="0.05"/>
  <stop offset="0.35" stop-color="#38bdf8" stop-opacity="0.55"/>
  <stop offset="0.7" stop-color="#818cf8" stop-opacity="0.35"/>
  <stop offset="1" stop-color="#818cf8" stop-opacity="0.04"/>
</linearGradient>
<linearGradient id="fade" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#cbd5e1" stop-opacity="0.55"/>
  <stop offset="0.6" stop-color="#cbd5e1" stop-opacity="0.12"/>
  <stop offset="1" stop-color="#cbd5e1" stop-opacity="0"/>
</linearGradient>
<filter id="glow" x="-10%" y="-50%" width="120%" height="200%"><feGaussianBlur stdDeviation="6"/></filter>
<filter id="soft"><feGaussianBlur stdDeviation="1.2"/></filter>
</defs>''')
o.append(f'<rect width="{W}" height="{H}" fill="url(#sky)"/>')
# stars
for _ in range(70):
    x, y = random.uniform(0, W), random.uniform(0, H * 0.55)
    r = random.choice([0.6, 0.8, 1.0, 1.3])
    o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="#e2e8f0" opacity="{random.uniform(0.15, 0.6):.2f}"/>')
# river: flowing bands
def band(y0, amp, phase, width, op, blur=False):
    pts = []
    for i in range(0, 41):
        x = W * i / 40
        y = y0 + amp * math.sin(i / 40 * 2 * math.pi * 1.3 + phase)
        pts.append((x, y))
    d = f'M{pts[0][0]:.1f},{pts[0][1]:.1f} ' + ' '.join(f'L{x:.1f},{y:.1f}' for x, y in pts[1:])
    extra = ' filter="url(#glow)"' if blur else ''
    return f'<path d="{d}" fill="none" stroke="url(#river)" stroke-width="{width}" stroke-linecap="round" opacity="{op}"{extra}/>'
o.append(band(250, 14, 0.4, 40, 0.5, True))
for k, (dy, amp, ph, w, op) in enumerate([(-14, 12, 0.2, 1.4, 0.7), (-4, 14, 0.5, 2.2, 0.9), (6, 13, 0.8, 1.2, 0.6),
                                            (16, 15, 1.1, 1.8, 0.5), (26, 12, 1.5, 1.0, 0.35), (-24, 10, 0.0, 0.8, 0.35)]):
    o.append(band(250 + dy, amp, ph, w, op))
# sparkles on the water
for _ in range(60):
    x = random.uniform(80, W - 40)
    y = 250 + 14 * math.sin(x / W * 2 * math.pi * 1.3 + 0.5) + random.uniform(-26, 30)
    o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{random.choice([0.7,1,1.2])}" fill="#bae6fd" opacity="{random.uniform(0.2,0.7):.2f}"/>')
# fragments of sessions, dissolving as they drift towards the water
frags = ['Fix the token refresh race in auth', 'run the test suite', 'Refactor parser',
         '{"type":"user","message":', 'Add dark mode to the settings page', 'subagent Kepler',
         'Migrate the blog to Astro', 'codex resume 01a1…', 'claude --resume 7f3a…', 'Plan the Q4 roadmap',
         'Profile the renderer', '"role":"assistant"', 'Benchmark JSON parsers', '⑂ 2 abandoned branches']
rows = [(60, 52), (120, 88), (40, 124), (180, 160), (90, 196)]
i = 0
for (x0, y), n in zip(rows, [3, 3, 3, 3, 2]):
    x = x0
    for _ in range(n):
        t = frags[i % len(frags)]; i += 1
        dist = (y - 40) / 170  # lower = closer to the river = more forgotten
        op = max(0.05, 0.6 - 0.45 * dist - 0.25 * x / W)
        o.append(f'<text x="{x:.0f}" y="{y}" font-family="JetBrains Mono, DejaVu Sans Mono, monospace" font-size="13" '
                 f'fill="#cbd5e1" opacity="{op:.2f}"{" filter=\"url(#soft)\"" if dist > 0.6 else ""}>{t}</text>')
        x += len(t) * 8 + random.randint(40, 90)
        if x > 640: break
# letters dissolving into the river
for _ in range(45):
    x = random.uniform(120, 700); y = random.uniform(205, 238)
    ch = random.choice('abcdefghijklmnopqrstuvwxyz{}":,.')
    o.append(f'<text x="{x:.0f}" y="{y:.0f}" font-family="DejaVu Sans Mono, monospace" font-size="{random.choice([9,10,11])}" '
             f'fill="#a5f3fc" opacity="{random.uniform(0.08,0.3):.2f}">{ch}</text>')
# wordmark
o.append('<text x="1010" y="138" text-anchor="middle" font-family="Cormorant Garamond, Georgia, DejaVu Serif, serif" '
         'font-size="92" letter-spacing="10" fill="#f1f5f9">lethe</text>')
o.append('<text x="1010" y="174" text-anchor="middle" font-family="Georgia, DejaVu Serif, serif" font-size="17" '
         'letter-spacing="5" fill="#7dd3fc" opacity="0.85">ΛΗΘΗ · THE RIVER OF FORGETTING</text>')
o.append('<text x="1010" y="204" text-anchor="middle" font-family="DejaVu Sans, Helvetica, Arial, sans-serif" font-size="14" '
         'fill="#94a3b8">Browse, resume and forget your Claude Code and Codex sessions</text>')
# Greek meander (key pattern) along the bottom edge
y = 296; path = [f'M20,{y+14} H{W-20}']
x = 24
while x + 18 < W - 20:
    path.append(f'M{x},{y+14} V{y} H{x+14} V{y+10} H{x+5} V{y+5} H{x+9}')
    x += 20
o.append(f'<path d="{" ".join(path)}" fill="none" stroke="#38bdf8" stroke-width="1.3" opacity="0.2"/>')
o.append('</svg>')
open('docs/banner.svg', 'w').write('\n'.join(o))
