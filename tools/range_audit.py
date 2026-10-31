"""R0 range audit (Track R). Run from the project root: python3 tools/range_audit.py
Reads every attack and skill .tres under Weapons/ and Data/ and prints each one's range values. Read-only; changes nothing.
R2: also prints each one's get_reach() and a MISMATCH line when a shape that follows the reach (Fan, Line, CircleSelf) is more
than 1 px away from it; the last line says how many there are. Exit code 1 when there is any, so it can gate a check."""
import re, glob, os, sys
FOLLOWS = ('Fan', 'Line', 'CircleSelf')
TOLERANCE_PX = 1.0
DEFAULTS_SHAPE = {'max_range':120.0}
def parse(path):
    txt = open(path).read()
    ext = dict(re.findall(r'\[ext_resource [^\]]*path="([^"]+)" id="([^"]+)"\]', txt)[::1] and [(m[1], m[0]) for m in re.findall(r'\[ext_resource [^\]]*path="([^"]+)"[^\]]* id="([^"]+)"\]', txt)])
    blocks = re.split(r'\n(?=\[(?:sub_resource|resource)\b)', txt)
    subs = {}; main = None
    for b in blocks:
        head = b.split('\n',1)[0]
        props = dict(re.findall(r'^(\w+) = (.+)$', b, re.M))
        m = re.match(r'\[sub_resource type="Resource" id="([^"]+)"', head)
        if m: subs[m.group(1)] = props
        elif head.startswith('[resource]'): main = props
    def script_of(p):
        s = p.get('script','')
        m = re.search(r'ExtResource\("([^"]+)"\)', s)
        return os.path.basename(ext.get(m.group(1),'')) if m else ''
    return main, subs, script_of, ext
def f(p, k, d=0.0):
    v = p.get(k)
    if v is None: return d
    m = re.match(r'-?[\d.]+', v)
    return float(m.group(0)) if m else d
def vec(p,k):
    v=p.get(k); 
    if not v: return (None,None)
    n=re.findall(r'-?[\d.]+',v.split('(',1)[1]); return (float(n[0]),float(n[1]))
def shape(subs, script_of, ref):
    m = re.search(r'SubResource\("([^"]+)"\)', ref or '')
    if not m: return None
    p = subs[m.group(1)]; kind = script_of(p).replace('AimShape2D.gd','')
    d = {'kind':kind,'max_range':f(p,'max_range',120.0)}
    if kind=='Fan': d['angle']=f(p,'angle_degrees',60.0)
    if kind=='Line': d['width']=f(p,'width',24.0); d['style']='ARROW' if f(p,'style',0)==1 else 'RECT'
    if kind in('GroundCircle',): d['area_radius']=f(p,'radius',f(p,'area_radius',40.0))
    return d
rows_a=[]; rows_s=[]
for path in sorted(glob.glob('Weapons/**/*.tres', recursive=True)+glob.glob('Data/**/*.tres', recursive=True)):
    main, subs, script_of, ext = parse(path)
    if not main: continue
    sc = script_of(main)
    if sc=='AttackDefinition2D.gd':
        eff = re.search(r'effect_scene = ExtResource\("([^"]+)"\)', open(path).read())
        eff = os.path.basename(ext.get(eff.group(1),'')) if eff else ''
        sh = shape(subs, script_of, main.get('aim_shape'))
        hs = vec(main,'hitbox_size'); ho = vec(main,'hitbox_offset')
        rows_a.append(dict(path=path,id=main.get('id','').replace('&"','').strip('"'),eff=eff,attack_range=f(main,'attack_range'),shape=sh,
            hitbox=(hs if hs[0] is not None else (16.0,16.0)), offset=(ho if ho[0] is not None else (0.0,0.0)), speed=f(main,'projectile_speed'), pierce=main.get('pierce','true'), max_targets=int(f(main,'max_targets'))))
    elif sc=='SkillDefinition2D.gd':
        att=None
        m=re.search(r'SubResource\("([^"]+)"\)', main.get('attack','') or '')
        if m:
            ap=subs[m.group(1)]
            eff=re.search(r'effect_scene = ExtResource\("([^"]+)"\)', '\n'.join(f'{k} = {v}' for k,v in ap.items()))
            hs=vec(ap,'hitbox_size'); ho=vec(ap,'hitbox_offset')
            att=dict(eff=os.path.basename(ext.get(eff.group(1),'')) if eff else '', hitbox=hs if hs[0] is not None else (16.0,16.0), offset=ho if ho[0] is not None else (0.0,0.0), speed=f(ap,'projectile_speed'))
        beh=['PROJECTILE','AREA','DASH','BUFF','NONE'][int(f(main,'behavior',0))]
        tgt='SELF' if f(main,'targeting',0)==1 else 'AIM'
        sh=shape(subs, script_of, main.get('aim_shape'))
        rows_s.append(dict(path=path,id=main.get('id','').replace('&"','').strip('"'),behavior=beh,targeting=tgt,max_range=f(main,'max_range'),area_radius=f(main,'area_radius'),shape=sh,attack=att,dash_speed=f(main,'dash_speed',700.0)))
def attack_reach(r):
    if r['attack_range'] > 0: return r['attack_range']
    return r['shape']['max_range'] if r['shape'] else 0.0
def strike(r):
    if r['area_radius'] > 0: return r['area_radius']
    return r['attack']['hitbox'][0] * 0.5 if r['attack'] else 0.0
def skill_reach(r):
    b = r['behavior']; sh = r['shape']; att = r['attack']
    if b == 'PROJECTILE':
        return r['max_range'] if r['max_range'] > 0 else (sh['max_range'] if sh else 0.0)
    if b == 'DASH': return r['max_range'] + (strike(r) if att else 0.0)
    if b == 'AREA':
        if sh and sh['kind'] == 'GroundCircle': return sh['max_range'] + sh.get('area_radius', 0.0)
        if not att: return 0.0
        off = 0.0 if r['targeting'] == 'SELF' else (att['offset'][0]**2 + att['offset'][1]**2) ** 0.5
        return off + strike(r)
    return 0.0
mismatches = []
print("ATTACKS");
for r in rows_a:
    reach = attack_reach(r)
    print(r['id'],r['eff'],'attack_range',r['attack_range'],'reach',reach,'shape',r['shape'],'hitbox',r['hitbox'],'off',r['offset'],'speed',r['speed'])
    if r['shape'] and r['shape']['kind'] in FOLLOWS and r['attack_range'] > 0 and abs(r['shape']['max_range'] - reach) > TOLERANCE_PX:
        mismatches.append('attack %s: shape %s px, reach %s px' % (r['id'], r['shape']['max_range'], reach))
print("SKILLS")
for r in rows_s:
    reach = skill_reach(r)
    print(r['id'],r['behavior'],r['targeting'],'max',r['max_range'],'area_r',r['area_radius'],'reach',reach,'shape',r['shape'],'att',r['attack'],'dash',r['dash_speed'])
    if r['shape'] and r['shape']['kind'] in FOLLOWS and reach > 0 and abs(r['shape']['max_range'] - reach) > TOLERANCE_PX:
        mismatches.append('skill %s: shape %s px, reach %s px' % (r['id'], r['shape']['max_range'], reach))
    if r['attack'] and r['behavior'] in ('PROJECTILE', 'AREA', 'DASH') and not r['shape']:
        mismatches.append('skill %s: damage skill has no aim_shape' % r['id'])
for m in mismatches: print('MISMATCH', m)
print('MISMATCHES', len(mismatches))
sys.exit(1 if mismatches else 0)
