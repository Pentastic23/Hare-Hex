import numpy as np, wave, sys, os
SR=44100
out=sys.argv[1]
rng=np.random.default_rng(7)
def t(d): return np.arange(int(SR*d))/SR
def env(n,a=0.005,d=None,curve=3.0):
    x=np.arange(n)/SR; total=n/SR
    e=np.minimum(1,x/max(a,1e-4))*np.exp(-curve*x/total*1.0)
    return e
def sine(f,d,ph=0): 
    tt=t(d); f=np.broadcast_to(f,tt.shape) if np.isscalar(f) else f
    return np.sin(2*np.pi*np.cumsum(f)/SR+ph)
def sweep(f0,f1,d,exp=True):
    tt=t(d)
    f=f0*(f1/f0)**(tt/d) if exp else f0+(f1-f0)*tt/d
    return np.sin(2*np.pi*np.cumsum(f)/SR)
def noise(d): return rng.uniform(-1,1,int(SR*d))
def lp(x,fc):
    a=np.exp(-2*np.pi*fc/SR); y=np.zeros_like(x); s=0
    for i,v in enumerate(x): s=(1-a)*v+a*s; y[i]=s
    return y
def hp(x,fc): return x-lp(x,fc)
def add(*xs):
    n=max(len(x) for x in xs); return sum(np.pad(x,(0,n-len(x))) for x in xs)
def norm(x,peak=0.8):
    return x/np.max(np.abs(x))*peak
def fade(x,ms=4):
    n=int(SR*ms/1000); x=x.copy(); x[-n:]*=np.linspace(1,0,n); return x
def save(name,x):
    x=fade(norm(x)); 
    with wave.open(os.path.join(out,name+'.wav'),'w') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(SR)
        w.writeframes((x*32767).astype('<i2').tobytes())
def tone(f,d,curve=5,a=0.003,harm=(1,0.4,0.2)):
    n=int(SR*d); x=sum(h*np.sin(2*np.pi*f*(i+1)*t(d)) for i,h in enumerate(harm)); return x*env(n,a,curve=curve)
def at(base,x,start):
    i=int(SR*start); 
    if len(base)<i+len(x): base=np.pad(base,(0,i+len(x)-len(base)))
    base[i:i+len(x)]+=x; return base
def seq(notes,gap,d=0.18,curve=5,harm=(1,0.4,0.2)):
    b=np.zeros(1)
    for k,f in enumerate(notes): b=at(b,tone(f,d,curve,harm=harm),k*gap)
    return b

# UI
save('click',add(tone(1200,0.05,8),0.3*noise(0.05)*env(int(SR*.05),curve=14)))
save('buy',seq([660,990],0.07,0.16)+0.0)
save('sell',seq([880,587,440],0.06,0.14))
save('reroll',add(hp(noise(0.22),2000)*np.sin(np.pi*t(0.22)/0.22)**1.5*0.7,0.4*sweep(500,1400,0.22)*env(int(SR*.22),curve=3)))
save('xp',seq([523,659,784],0.06,0.14,harm=(1,0.5,0.3)))
save('lock',add(tone(220,0.09,10,harm=(1,0.6,0.4)),0.3*noise(0.09)*env(int(SR*.09),curve=18)))
save('unlock',add(tone(330,0.09,10,harm=(1,0.6,0.4)),0.3*noise(0.09)*env(int(SR*.09),curve=18)))
save('error',tone(150,0.18,4,harm=(1,0.8,0.6,0.4))*(1+0.5*np.sign(np.sin(2*np.pi*22*t(0.18)))))
save('pickup',sweep(400,700,0.07)*env(int(SR*.07),curve=5))
save('place',add(lp(noise(0.08),1800)*env(int(SR*.08),0.001,curve=14),tone(140,0.1,12)))
# items: a struck metal clink (inharmonic partials, the high ones dying first)
def metal(f,d,parts=((1,1,1),(2.76,0.6,1.6),(5.4,0.4,2.4),(8.93,0.25,3.2))):
    n=int(SR*d); return sum(a*np.sin(2*np.pi*f*r*t(d))*env(n,0.001,curve=6*k) for r,a,k in parts)
save('equip',add(metal(1400,0.25),0.8*seq([659,988],0.06,0.22,4,harm=(1,0.3,0.15)),0.12*hp(noise(0.05),4000)*env(int(SR*.05),0.001,curve=20)))
save('resonance',add(seq([523,784,1046,1568],0.05,0.5,2.5,harm=(1,0.5,0.25)),0.5*tone(262,0.7,2,0.03,harm=(1,0.5)),0.08*hp(noise(0.6),6000)*np.sin(np.pi*t(0.6)/0.6)))
save('tongs',add(metal(900,0.18),at(np.zeros(1),metal(1250,0.22),0.09),0.3*hp(noise(0.18),3000)*np.sin(np.pi*t(0.18)/0.18)**2))
# progression
save('merge',seq([523,659,784,1046],0.07,0.28,3,harm=(1,0.5,0.25,0.15)))
save('levelup',seq([392,523,659,784,1046],0.09,0.4,3,harm=(1,0.5,0.3)))
save('win',seq([523,659,784,659,784,1046],0.11,0.5,2.5,harm=(1,0.5,0.3,0.1)))
save('lose',seq([392,370,330,262],0.2,0.5,2.5,harm=(1,0.6,0.3)))
save('round',add(tone(110,0.35,3,0.01,harm=(1,0.7,0.5,0.3)),0.5*sweep(80,160,0.35)*env(int(SR*.35),0.02,curve=3)))
# combat
save('swing',hp(noise(0.14),1500)*np.sin(np.pi*t(0.14)/0.14)**2*0.8)
save('hit',add(lp(noise(0.12),2500)*env(int(SR*.12),0.001,curve=12),0.8*sweep(220,70,0.12)*env(int(SR*.12),0.001,curve=7)))
save('crit',add(lp(noise(0.16),4000)*env(int(SR*.16),0.001,curve=9),sweep(300,60,0.16)*env(int(SR*.16),0.001,curve=6),0.4*tone(1500,0.1,10)))
save('death',add(sweep(300,45,0.45)*env(int(SR*.45),0.005,curve=4),0.4*lp(noise(0.45),900)*env(int(SR*.45),curve=5)))
save('cast',add(sweep(300,1300,0.35)*np.sin(np.pi*t(0.35)/0.35)**0.7*0.6,0.3*sweep(450,1950,0.35)*env(int(SR*.35),curve=2)))
save('heal',seq([784,988,1319],0.07,0.3,3.5,harm=(1,0.3)))
