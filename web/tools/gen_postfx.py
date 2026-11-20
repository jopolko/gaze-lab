"""Generates web/downhill-three/postfx.js: the Godot post-pass shader source is embedded VERBATIM (web/data/post_psy.gdshader, the runtime source dumped from the game, which is Themes.POST with the HSV helpers expanded; blank lines removed)
and RunRig.PSY_SHADER (the parked ring/spoke overlay) likewise; the JS half converts them to GLSL with a small, fixed list of substitutions, so nothing is transcribed by hand."""
import re, os, sys
W = 'C:/Users/josh/projects/gaze-lab'
post = [l for l in open(W + '/web/data/post_psy.gdshader', encoding='utf-8').read().replace('\r', '').split('\n') if l.strip() != '']
rr = open(W + '/godot/scripts/RunRig.gd', encoding='utf-8').read().replace('\r', '').split('\n')
a = next(i for i, l in enumerate(rr) if l.startswith('const PSY_SHADER := """'))
b = next(i for i in range(a + 1, len(rr)) if rr[i].strip() == '"""')
ripple = [l for l in rr[a + 1:b] if l.strip() != '']
for name, lines in (('post', post), ('ripple', ripple)):
    for l in lines:
        assert '`' not in l and '${' not in l and chr(92) not in l, (name, l)
tpl = open(W + '/web/tools/postfx.template.js', encoding='utf-8').read()
out = tpl.replace('/*@@POST@@*/', '\n'.join(post)).replace('/*@@RIPPLE@@*/', '\n'.join(ripple))
open(W + '/web/downhill-three/postfx.js', 'w', encoding='utf-8').write(out)
print('postfx.js written', len(out), 'bytes; post', len(post), 'lines; ripple', len(ripple), 'lines')
