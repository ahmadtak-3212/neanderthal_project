"""Draw a pipeline diagram (one row per instruction, one column per cycle) from a Konata log.
usage: python3 konata_plot.py output.log out.png FIRST_ID COUNT
  output.log  written by the core when konata_debug = True in pipelined.bsv
  FIRST_ID    first instruction id to draw, COUNT how many
needs: pip install pillow capstone   (capstone disassembles the RV32I instruction words)
"""
import sys, re, capstone
md=capstone.Cs(capstone.CS_ARCH_RISCV, capstone.CS_MODE_RISCV32)
def dis(w,pc):
    try:
        for i in md.disasm(int(w,16).to_bytes(4,'little'), int(pc,16)): return f'{i.mnemonic} {i.op_str}'
    except Exception: pass
    return w
from PIL import Image, ImageDraw, ImageFont
log=open(sys.argv[1]).read().split('\n'); out=sys.argv[2]; start=int(sys.argv[3]); n=int(sys.argv[4])
cyc=0; ins={}
for l in log:
    p=l.split('\t')
    if not p or not p[0]: continue
    k=p[0]
    if k=='C': cyc+=int(p[1])
    elif k=='I': i=int(p[1]); ins[i]={'st':[], 'pc':None,'end':None,'flush':False,'asm':''}
    elif k=='S':
        i=int(p[1]); st=p[3].strip()
        if i in ins: ins[i]['st'].append((cyc,st))
    elif k=='L':
        i=int(p[1]); txt=p[3]
        if i in ins:
            m=re.match(r'PC ([0-9a-f]+)',txt)
            if m: ins[i]['pc']=m.group(1)
            m=re.match(r'Instr bits: ([0-9a-f]+)',txt)
            if m: ins[i]['asm']=m.group(1)
    elif k=='R':
        i=int(p[1])
        if i in ins: ins[i]['end']=cyc; ins[i]['flush']=(p[3].strip()=='1')
ids=[i for i in sorted(ins) if i>=start][:n]
c0=min(ins[i]['st'][0][0] for i in ids if ins[i]['st']); c1=max((ins[i]['end'] or c0) for i in ids)+1
CW,RH,LW=26,22,330
W=max(LW+(c1-c0)*CW+20, LW+5*230); H=40+len(ids)*RH+50
im=Image.new('RGB',(W,H),'white'); d=ImageDraw.Draw(im)
try: f=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',13); fb=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',14)
except: f=fb=ImageFont.load_default()
col={'F':(120,170,230),'D':(130,200,140),'E':(240,180,90),'E2':(240,140,60),'W':(200,140,220)}
for c in range(c0,c1):
    x=LW+(c-c0)*CW; d.line([(x,30),(x,H-50)],fill=(235,235,235))
    if (c-c0)%5==0: d.text((x+2,12),str(c),fill='gray',font=f)
for r,i in enumerate(ids):
    y=36+r*RH; I=ins[i]
    d.text((6,y+3),f"{I['pc'] or '?':>8}  {dis(I['asm'],I['pc'] or '0') if I['asm'] else '(not decoded)'}",fill='black',font=f)
    sts=I['st']+[(I['end'] or c1,'END')]
    for (ca,s),(cb,_) in zip(sts,sts[1:]):
        x0=LW+(ca-c0)*CW; x1=LW+(max(cb,ca+1)-c0)*CW
        fill=(220,220,220) if I['flush'] else col.get(s,(180,180,180))
        d.rectangle([x0+1,y+2,x1-1,y+RH-3],fill=fill,outline='white')
        d.text((x0+8,y+3),s,fill='black',font=fb)
lx=LW
for s,t in [('F','fetch'),('D','decode (repeat = stalled)'),('E','execute'),('W','writeback'),('','squashed: wrong-path fetch')]:
    d.rectangle([lx,H-36,lx+18,H-20],fill=col.get(s,(220,220,220))); d.text((lx+24,H-36),t,fill='black',font=f); lx+=230
im.save(out); print(out,len(ids),c0,c1)
