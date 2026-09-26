import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import '../../moontake/Moon/MoonAtlasResources/moon-core.js';

const {gray,detectDisc,renderMoon,registerMoon,sample}=globalThis.MoonAtlasCore;

const root=new URL('./output/',import.meta.url);
function asset(name){const [width,height]=JSON.parse(fs.readFileSync(new URL(name+'-size.json',root)));return {width,height,data:new Uint8ClampedArray(fs.readFileSync(new URL(name+'.rgba',root)))};}
const photo=asset('example-nasa'),texture=asset('moon-color');
const surface=JSON.parse(fs.readFileSync(new URL('./surface-2026-01-01.json',import.meta.url)));
const pixels=gray(photo.data), model=renderMoon(texture,surface,160);
const degrees=(a,b)=>Math.abs(((a-b+540)%360)-180);

test('independent NASA reference: recover limb and orientation',()=>{
  const disc=detectDisc(pixels,photo.width,photo.height);assert.ok(disc);
  const fit=registerMoon(pixels,photo.width,photo.height,disc,model);
  assert.equal(fit.accepted,true);assert.ok(fit.score>.65);
  assert.ok(Math.abs(fit.x-364.5)<4);assert.ok(Math.abs(fit.y-364.5)<4);
  assert.ok(Math.abs(fit.radius-347)<4);assert.ok(degrees(fit.rotation,0)<2);
});

for(const mirror of [false,true])test(`rotated, reduced, off-center reference; mirror=${mirror}`,()=>{
  const width=640,height=520,angle=73*Math.PI/180,c=Math.cos(angle),s=Math.sin(angle),r=126,cx=370,cy=235;
  const image=new Float32Array(width*height);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++) {
    const dx=(x-cx)*(mirror?-1:1),dy=y-cy;
    const src=sample(pixels,photo.width,photo.height,364.5+(dx*c+dy*s)*347/r,364.5+(-dx*s+dy*c)*347/r);
    image[y*width+x]=Math.min(.98,Math.max(0,src*.72+.035+Math.sin(x*13.1+y*71.7)*.009));
  }
  const disc=detectDisc(image,width,height);assert.ok(disc);
  const fit=registerMoon(image,width,height,disc,model,mirror);
  assert.equal(fit.accepted,true,JSON.stringify(fit));assert.ok(degrees(fit.rotation,73)<3,JSON.stringify(fit));
  assert.ok(Math.hypot(fit.x-cx,fit.y-cy)<4);assert.ok(Math.abs(fit.radius-r)<4);
});

test('blank, uniform overexposed disc, and tiny Moon never produce accepted labels',()=>{
  const width=300,black=new Float32Array(width*width);assert.equal(detectDisc(black,width,width),null);
  const white=new Float32Array(width*width);
  for(let y=0;y<width;y++)for(let x=0;x<width;x++)if(Math.hypot(x-150,y-150)<80)white[y*width+x]=1;
  const disc=detectDisc(white,width,width);assert.ok(disc);
  assert.equal(registerMoon(white,width,width,disc,model).accepted,false);
  assert.equal(registerMoon(white,width,width,{x:150,y:150,radius:12},model).reason,'small');
});

const softPhoto=asset('soft-full-moon');
const softPixels=gray(softPhoto.data);
const softSurface=JSON.parse(fs.readFileSync(new URL('./surface-2026-06-30.json',import.meta.url)));
const softModel=renderMoon(texture,softSurface,160);

test('real soft full Moon: maria outlines identify orientation without sharp crater detail',()=>{
  const disc=detectDisc(softPixels,softPhoto.width,softPhoto.height);assert.ok(disc);
  const fit=registerMoon(softPixels,softPhoto.width,softPhoto.height,disc,softModel);
  assert.equal(fit.accepted,true,JSON.stringify(fit));
  assert.ok(degrees(fit.rotation,292)<5,JSON.stringify(fit));
  assert.ok(Math.hypot(fit.x-64,fit.y-64)<3);
  assert.ok(Math.abs(fit.radius-39)<3);
  assert.ok(fit.structureScore>.7);
  assert.equal(registerMoon(softPixels,softPhoto.width,softPhoto.height,disc,softModel,true).accepted,false);
});

for(const mirror of [false,true])test(`real soft Moon with changed roll, exposure and off-center placement; mirror=${mirror}`,()=>{
  const width=480,height=420,cx=280,cy=170,r=52,angle=67*Math.PI/180;
  const image=new Float32Array(width*height);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++) {
    const dx=(x-cx)*(mirror?-1:1),dy=y-cy;
    const src=sample(softPixels,128,128,64+(dx*Math.cos(angle)+dy*Math.sin(angle))*39/r,
      64+(-dx*Math.sin(angle)+dy*Math.cos(angle))*39/r);
    image[y*width+x]=src*.8+.015;
  }
  // An exported photo's bright footer must not replace the Moon as the candidate.
  image.fill(1,width*(height-35));
  const disc=detectDisc(image,width,height);assert.ok(disc);
  const fit=registerMoon(image,width,height,disc,softModel,mirror);
  assert.equal(fit.accepted,true,JSON.stringify(fit));
  assert.ok(degrees(fit.rotation,292+67)<5,JSON.stringify(fit));
  assert.ok(Math.hypot(fit.x-cx,fit.y-cy)<4);
  assert.ok(Math.abs(fit.radius-r)<4);
});

test('smooth, shaded, concentric and unrelated patchy discs do not identify as the Moon',()=>{
  let seed=42;
  const random=()=>((seed=(Math.imul(seed,1664525)+1013904223)>>>0)/4294967296);
  const width=240,radius=75;
  for(let trial=0;trial<60;trial++) {
    const pixels=new Float32Array(width*width);
    const spots=Array.from({length:5+trial%7},()=>({x:(random()-.5)*120,y:(random()-.5)*120,
      radius:5+random()*25,value:(random()-.5)*.6}));
    for(let y=0;y<width;y++)for(let x=0;x<width;x++) {
      const dx=x-120,dy=y-120,rho=Math.hypot(dx,dy)/radius;if(rho>=1)continue;
      let value=.55;
      if(trial===0)value=.8;
      else if(trial===1)value=.55+dx*.002;
      else if(trial===2)value=.55+.15*Math.cos(rho*9);
      else for(const spot of spots)value+=spot.value*Math.exp(-((dx-spot.x)**2+(dy-spot.y)**2)/(2*spot.radius**2));
      pixels[y*width+x]=value;
    }
    const disc=detectDisc(pixels,width,width);assert.ok(disc);
    const fit=registerMoon(pixels,width,width,disc,softModel);
    assert.equal(fit.accepted,false,`pattern ${trial}: ${JSON.stringify(fit)}`);
  }
});

for(const illumination of [.2,.5,.8])test(`limb and texture still match a synthetic phase at illumination ${illumination}`,()=>{
  // This isolates phase/limb handling; identity is covered by the independent NASA
  // image and the real phone crop above, rather than this self-rendered fixture.
  const z=illumination*2-1,viewSun=[Math.sqrt(1-z*z),0,z];
  const phase={...surface,sunDirection:[0,1,2].map(k=>surface.bodyToView.reduce((sum,row,i)=>sum+row[k]*viewSun[i],0))};
  const source=renderMoon(texture,phase,320),model=renderMoon(texture,phase,160);
  const width=480,height=400,r=105,cx=260,cy=180,angle=75*Math.PI/180,image=new Float32Array(width*height);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++) {
    const dx=x-cx,dy=y-cy;
    image[y*width+x]=sample(source.luminance,320,320,159.5+(dx*Math.cos(angle)+dy*Math.sin(angle))*160/r,
      159.5+(-dx*Math.sin(angle)+dy*Math.cos(angle))*160/r)*.7+.02;
  }
  const disc=detectDisc(image,width,height);assert.ok(disc);
  const fit=registerMoon(image,width,height,disc,model);
  assert.equal(fit.accepted,true,JSON.stringify(fit));
  assert.ok(degrees(fit.rotation,75)<4,JSON.stringify(fit));
  assert.ok(Math.hypot(fit.x-cx,fit.y-cy)<4);
  assert.ok(Math.abs(fit.radius-r)<4);
});

for(const fixture of [
  {name:'soft-gibbous-moon-may',date:'2026-05-25',x:62.5,y:64.3,radius:28.6,rotation:344.5},
  {name:'soft-gibbous-moon-september',date:'2026-09-21',x:62.8,y:64.7,radius:31.4,rotation:337.9},
]) {
  const photo=asset(fixture.name),pixels=gray(photo.data);
  const surface=JSON.parse(fs.readFileSync(new URL(`./surface-${fixture.date}.json`,import.meta.url)));
  const model=renderMoon(texture,surface,160);
  test(`real ${fixture.name}: recover the full disc from its lit arc and maria`,()=>{
    const disc=detectDisc(pixels,photo.width,photo.height);assert.ok(disc);
    const fit=registerMoon(pixels,photo.width,photo.height,disc,model);
    assert.equal(fit.accepted,true,JSON.stringify(fit));
    assert.ok(degrees(fit.rotation,fixture.rotation)<5,JSON.stringify(fit));
    assert.ok(Math.hypot(fit.x-fixture.x,fit.y-fixture.y)<3);
    assert.ok(Math.abs(fit.radius-fixture.radius)<3);
    assert.equal(registerMoon(pixels,photo.width,photo.height,disc,model,true).accepted,false);
  });
  for(const mirror of [false,true])test(`real ${fixture.name} transformed with white footer; mirror=${mirror}`,()=>{
    const width=480,height=420,cx=280,cy=170,radius=40,angle=67*Math.PI/180;
    const image=new Float32Array(width*height);
    for(let y=0;y<height;y++)for(let x=0;x<width;x++) {
      const dx=(x-cx)*(mirror?-1:1),dy=y-cy;
      const src=sample(pixels,128,128,fixture.x+(dx*Math.cos(angle)+dy*Math.sin(angle))*fixture.radius/radius,
        fixture.y+(-dx*Math.sin(angle)+dy*Math.cos(angle))*fixture.radius/radius);
      image[y*width+x]=src*.85+.015;
    }
    image.fill(1,width*(height-35));
    const disc=detectDisc(image,width,height);assert.ok(disc);
    const fit=registerMoon(image,width,height,disc,model,mirror);
    assert.equal(fit.accepted,true,JSON.stringify(fit));
    assert.ok(degrees(fit.rotation,fixture.rotation+67)<5,JSON.stringify(fit));
    assert.ok(Math.hypot(fit.x-cx,fit.y-cy)<3);
    assert.ok(Math.abs(fit.radius-radius)<3);
  });
}

const daylight=asset('daylight-moon'),dayPixels=gray(daylight.data);
const daySurface=JSON.parse(fs.readFileSync(new URL('./surface-2026-04-28.json',import.meta.url)));
const dayModel=renderMoon(texture,daySurface,160);

test('real daylight sky: find the Moon amid clouds and a bright background',()=>{
  const disc=detectDisc(dayPixels,daylight.width,daylight.height);assert.ok(disc);
  const fit=registerMoon(dayPixels,daylight.width,daylight.height,disc,dayModel);
  assert.equal(fit.accepted,true,JSON.stringify(fit));
  assert.ok(Math.hypot(fit.x-554.6,fit.y-738.8)<3);
  assert.ok(Math.abs(fit.radius-37.4)<3);
  assert.ok(degrees(fit.rotation,299.8)<5,JSON.stringify(fit));
  assert.equal(registerMoon(dayPixels,daylight.width,daylight.height,disc,dayModel,true).accepted,false);
});

for(const mirror of [false,true])test(`daylight sky rotated, exposure changed, with white footer; mirror=${mirror}`,()=>{
  const width=daylight.height,height=daylight.width+80,image=new Float32Array(width*height);
  for(let y=0;y<daylight.height;y++)for(let x=0;x<daylight.width;x++) {
    const rx=mirror?y:daylight.height-1-y,ry=x;
    image[ry*width+rx]=dayPixels[y*daylight.width+x]*.75+.12;
  }
  image.fill(1,width*daylight.width);
  const disc=detectDisc(image,width,height);assert.ok(disc);
  const fit=registerMoon(image,width,height,disc,dayModel,mirror);
  assert.equal(fit.accepted,true,JSON.stringify(fit));
  const expectedX=mirror?738.8:daylight.height-1-738.8;
  assert.ok(Math.hypot(fit.x-expectedX,fit.y-554.6)<3,JSON.stringify(fit));
  assert.ok(Math.abs(fit.radius-37.4)<3);
  assert.ok(degrees(fit.rotation,29.8)<5,JSON.stringify(fit));
});

test('the real clouds and sky, with the Moon replaced by neighboring sky, never produce accepted labels',()=>{
  // Remove only the Moon from the test input; retain the original cloud shapes
  // and brightness gradient instead of relying solely on synthetic negatives.
  const sky=new Float32Array(dayPixels);
  for(let y=678;y<806;y++)for(let x=490;x<618;x++)sky[y*daylight.width+x]=dayPixels[y*daylight.width+x+240];
  const disc=detectDisc(sky,daylight.width,daylight.height);
  if(disc)assert.equal(registerMoon(sky,daylight.width,daylight.height,disc,dayModel).accepted,false);
});
