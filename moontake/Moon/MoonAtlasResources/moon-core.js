// Runs in the native background JavaScriptCore engine and Node regression tests.
globalThis.MoonAtlasCore = (() => {
// Pure image registration. All positions use image Y down.
const radians = Math.PI / 180;
const dot = (a, b) => a.reduce((sum, x, i) => sum + x * b[i], 0);

function gray(rgba) {
  const out = new Float32Array(rgba.length / 4);
  for (let i = 0; i < out.length; i++) out[i] = (rgba[4*i] * .2126 + rgba[4*i+1] * .7152 + rgba[4*i+2] * .0722) / 255;
  return out;
}

function sample(data, width, height, x, y) {
  if (x < 0 || y < 0 || x >= width - 1 || y >= height - 1) return 0;
  const ix = Math.floor(x), iy = Math.floor(y), dx = x - ix, dy = y - iy, i = iy * width + ix;
  return (data[i]*(1-dx)+data[i+1]*dx)*(1-dy)+(data[i+width]*(1-dx)+data[i+width+1]*dx)*dy;
}

function highpass(data, width, height, radius) {
  const stride = width + 1, integral = new Float64Array(stride * (height + 1)), out = new Float32Array(data.length);
  for (let y = 0; y < height; y++) {
    let row = 0;
    for (let x = 0; x < width; x++) {
      row += data[y * width + x];
      integral[(y+1)*stride+x+1] = integral[y*stride+x+1]+row;
    }
  }
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const l = Math.max(0,x-radius), r = Math.min(width,x+radius+1), t = Math.max(0,y-radius), b = Math.min(height,y+radius+1);
    const mean = (integral[b*stride+r]-integral[t*stride+r]-integral[b*stride+l]+integral[t*stride+l])/((r-l)*(b-t));
    out[y*width+x] = data[y*width+x]-mean;
  }
  return out;
}

function renderMoon(texture, surface, size = 192) {
  const pixels = new Uint8ClampedArray(size*size*4), luminance = new Float32Array(size*size), lit = new Float32Array(size*size);
  const m = surface.bodyToView, sun = surface.sunDirection;
  for (let j = 0; j < size; j++) for (let i = 0; i < size; i++) {
    const x = (i+.5)*2/size-1, y = 1-(j+.5)*2/size, r2 = x*x+y*y;
    if (r2 >= 1) continue;
    const z = Math.sqrt(1-r2), body = [0,1,2].map(k => m[0][k]*x+m[1][k]*y+m[2][k]*z);
    const u = ((Math.atan2(body[1],body[0])/(2*Math.PI)+.5)*texture.width + texture.width) % texture.width;
    const v = (.5-Math.asin(Math.max(-1,Math.min(1,body[2])))/Math.PI)*(texture.height-1);
    const tx = Math.min(texture.width-1,Math.floor(u)), ty = Math.floor(v), src = (ty*texture.width+tx)*4;
    const mu = dot(body,sun), brightness = mu > 0 ? Math.pow(2*mu/(mu+z),.65) : 0;
    const dst = (j*size+i)*4;
    for (let c = 0; c < 3; c++) pixels[dst+c] = Math.min(255,texture.data[src+c]*brightness);
    pixels[dst+3] = 255;
    luminance[j*size+i] = (pixels[dst]*.2126+pixels[dst+1]*.7152+pixels[dst+2]*.0722)/255;
    lit[j*size+i] = mu;
  }
  return { pixels, luminance, lit, size };
}

function circleThrough(a,b,c) {
  const d = 2*(a[0]*(b[1]-c[1])+b[0]*(c[1]-a[1])+c[0]*(a[1]-b[1]));
  if (Math.abs(d)<1e-6) return null;
  const aa=dot(a,a), bb=dot(b,b), cc=dot(c,c);
  const x=(aa*(b[1]-c[1])+bb*(c[1]-a[1])+cc*(a[1]-b[1]))/d;
  const y=(aa*(c[0]-b[0])+bb*(a[0]-c[0])+cc*(b[0]-a[0]))/d;
  return { x, y, radius:Math.hypot(x-a[0],y-a[1]) };
}

/** Finds a bright disc/crescent. This is only a proposal, not proof of lunar identity. */
function detectDisc(data,width,height) {
  const direct=detectSilhouette(data,width,height);
  if(direct && direct.radius>=24)return direct;
  // Bright skies can join the Moon to a huge foreground region. Subtract a local
  // background only to locate the limb; registration still uses the original photo.
  const contrast=highpass(data,width,height,Math.max(32,Math.round(Math.min(width,height)/16)));
  for(let i=0;i<contrast.length;i++)contrast[i]=Math.max(0,contrast[i]);
  const local=detectSilhouette(contrast,width,height);
  return local && local.radius>=24 ? local : direct ?? local;
}

function detectSilhouette(data,width,height) {
  let peak=0, mean=0;
  for (const p of data) {peak=Math.max(peak,p);mean+=p;}
  mean/=data.length;
  if (peak-mean<.06) return null;
  const backgroundSamples=[];
  for(let i=0;i<data.length;i+=Math.max(1,Math.floor(data.length/4096)))backgroundSamples.push(data[i]);
  backgroundSamples.sort((a,b)=>a-b);
  const background=backgroundSamples[Math.floor(backgroundSamples.length*.1)];
  const threshold = background+(peak-background)*.16;
  const visited=new Uint8Array(data.length), queue=new Int32Array(data.length), components=[];
  for (let start=0;start<data.length;start++) {
    if (visited[start] || data[start]<threshold) continue;
    let head=0,tail=1;queue[0]=start;visited[start]=1;
    const boundary=[]; let minX=width,maxX=0,minY=height,maxY=0,localPeak=background;
    const rowMin=new Int32Array(height).fill(width),rowMax=new Int32Array(height).fill(-1);
    const colMin=new Int32Array(width).fill(height),colMax=new Int32Array(width).fill(-1);
    while(head<tail) {
      const p=queue[head++],x=p%width,y=Math.floor(p/width);
      minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);
      localPeak=Math.max(localPeak,data[p]);
      for (const n of [x>0?p-1:-1,x<width-1?p+1:-1,y>0?p-width:-1,y<height-1?p+width:-1]) {
        if(n<0 || data[n]<threshold)continue;
        if(!visited[n]){visited[n]=1;queue[tail++]=n;}
      }
    }
    // A soft halo is not the limb. Measure the silhouette relative to this
    // component's brightness to reduce sensitivity to a white export footer.
    const limbThreshold=Math.max(threshold,background+(localPeak-background)*.35);
    for(let i=0;i<tail;i++) {
      const p=queue[i];if(data[p]<limbThreshold)continue;
      const x=p%width,y=Math.floor(p/width);
      rowMin[y]=Math.min(rowMin[y],x);rowMax[y]=Math.max(rowMax[y],x);
      colMin[x]=Math.min(colMin[x],y);colMax[x]=Math.max(colMax[x],y);
    }
    // Use the silhouette, not the thousands of internal crater/mare edges.
    for(let y=minY;y<=maxY;y++)if(rowMax[y]>=0){boundary.push([rowMin[y],y],[rowMax[y],y]);}
    for(let x=minX;x<=maxX;x++)if(colMax[x]>=0){boundary.push([x,colMin[x]],[x,colMax[x]]);}
    if(tail>80 && maxX-minX>10 && maxY-minY>10) components.push({boundary,area:tail,minX,maxX,minY,maxY});
  }
  components.sort((a,b)=>b.area-a.area);
  let best=null, seed=123456789;
  const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296;};
  for(const component of components.slice(0,5)) {
    // Odd stride keeps both left/right and top/bottom silhouette samples.
    const stride=Math.max(1,Math.floor(component.boundary.length/600))|1;
    const points=component.boundary.filter((_,i)=>i%stride===0);
    const extent=Math.max(component.maxX-component.minX,component.maxY-component.minY);
    for(let k=0;k<450;k++) {
      const circle=circleThrough(points[Math.floor(random()*points.length)],points[Math.floor(random()*points.length)],points[Math.floor(random()*points.length)]);
      if(!circle || circle.radius<extent*.43 || circle.radius>extent*.85 || circle.radius<8)continue;
      if(circle.x-circle.radius<0 || circle.y-circle.radius<0 || circle.x+circle.radius>=width || circle.y+circle.radius>=height)continue;
      const tolerance=Math.max(1.4,circle.radius*.016);let count=0;const bins=new Set();
      for(const [x,y] of points)if(Math.abs(Math.hypot(x-circle.x,y-circle.y)-circle.radius)<tolerance){count++;bins.add(Math.floor((Math.atan2(y-circle.y,x-circle.x)+Math.PI)*12/Math.PI)%24);}
      const coverage=bins.size/24, score=count/points.length;
      if(coverage<.42 || score<.46)continue;
      const rank=score*Math.sqrt(component.area)*coverage;
      if(!best || rank>best.rank)best={...circle,rank,edgeScore:score,coverage};
    }
  }
  return best;
}

// Keep the maria's broad outlines while suppressing pixel noise and illumination gradients.
// Both images use the same filter widths relative to the lunar radius, not file resolution.
function structureBand(data, width, height, lunarRadius) {
  const noise = highpass(data, width, height, Math.max(1, Math.round(lunarRadius * .028)));
  const smooth = Float32Array.from(data, (value, i) => value - noise[i]);
  return highpass(smooth, width, height, Math.round(lunarRadius * .17));
}

/** Correlates maria outlines and finer texture at a shared center, scale and orientation. */
function registerMoon(photo,width,height,disc,model,mirror=false) {
  if(disc.radius<24)return {...disc,rotation:0,score:0,accepted:false,reason:'small'};
  const n=192, span=disc.radius*2.7, crop=new Float32Array(n*n);
  for(let y=0;y<n;y++)for(let x=0;x<n;x++)crop[y*n+x]=sample(photo,width,height,disc.x+((x+.5)/n-.5)*span,disc.y+((y+.5)/n-.5)*span);
  const filtered=highpass(crop,n,n,7), template=highpass(model.luminance,model.size,model.size,Math.round(model.size*.05));
  const points=[];const radius=n/2.7;
  const structure=structureBand(crop,n,n,radius);
  const modelStructure=structureBand(model.luminance,model.size,model.size,model.size/2);
  for(let y=0;y<model.size;y+=2)for(let x=0;x<model.size;x+=2) {
    const nx=(x+.5)*2/model.size-1,ny=(y+.5)*2/model.size-1,i=y*model.size+x;
    if(nx*nx+ny*ny<.78 && model.lit[i]>.18)points.push([nx*(mirror?-1:1),ny,template[i],modelStructure[i]]);
  }
  if(points.length<100)return {...disc,rotation:0,score:0,accepted:false,reason:'phase'};
  function score(rotation,dx=0,dy=0,scale=1) {
    const a=rotation*radians,c=Math.cos(a),s=Math.sin(a);
    let sx=0,sy=0,sxx=0,syy=0,sxy=0,count=0,clipped=0;
    let bx=0,by=0,bxx=0,byy=0,bxy=0;
    for(const [px,py,v,b] of points) {
      // Mirror follows rotation in image space, so unmirror before and after rotation.
      const sign=mirror?-1:1, x=n/2-.5+dx+radius*scale*(px*c-py*s*sign),y=n/2-.5+dy+radius*scale*(px*s*sign+py*c);
      const raw=sample(crop,n,n,x,y);if(raw>.985)clipped++;
      const w=sample(filtered,n,n,x,y);
      sx+=v;sy+=w;sxx+=v*v;syy+=w*w;sxy+=v*w;count++;
      const broad=sample(structure,n,n,x,y);
      bx+=b;by+=broad;bxx+=b*b;byy+=broad*broad;bxy+=b*broad;
    }
    const variance=syy-sy*sy/count, denominator=Math.sqrt((sxx-sx*sx/count)*variance);
    const broadVariance=Math.max(0,byy-by*by/count);
    const broadDenominator=Math.sqrt(Math.max(0,bxx-bx*bx/count)*broadVariance);
    const textureScore=denominator>1e-7?(sxy-sx*sy/count)/denominator:0;
    const structureScore=broadDenominator>1e-7?(bxy-bx*by/count)/broadDenominator:0;
    return {score:.35*textureScore+.65*structureScore,textureScore,structureScore,
      detail:Math.sqrt(broadVariance/count),clipped:clipped/count,rotation,dx,dy,scale};
  }
  const coarse=[];
  for(let angle=0;angle<360;angle+=3)coarse.push(score(angle));
  coarse.sort((a,b)=>b.score-a.score);
  function refine(initial) {
    let best=initial;
    // Coordinate descent refines the limb estimate without allowing a wildly different disc.
    for(const step of [1.5,.6,.2]) {
      for(let iteration=0;iteration<2;iteration++) {
        for(const dimension of ['rotation','dx','dy','scale']) {
          const start=best;
          for(const direction of [-2,-1,1,2]) {
            const candidate={...start};candidate[dimension]+=direction*step*(dimension==='scale'?.009:1);
            if(Math.abs(candidate.dx)>radius*.08 || Math.abs(candidate.dy)>radius*.08 || candidate.scale<.93 || candidate.scale>1.07)continue;
            const result=score(candidate.rotation,candidate.dx,candidate.dy,candidate.scale);
            if(result.score>best.score)best=result;
          }
        }
      }
    }
    return best;
  }
  // Give competing orientations the same position/scale refinement before measuring
  // ambiguity. Comparing a refined winner to unrefined alternatives inflates confidence.
  const angleDistance=(a,b)=>Math.abs(((a-b+540)%360)-180), seeds=[];
  for(const candidate of coarse) {
    if(seeds.every(seed=>angleDistance(candidate.rotation,seed.rotation)>25))seeds.push(candidate);
    if(seeds.length===4)break;
  }
  const refined=seeds.map(refine).sort((a,b)=>b.score-a.score), best=refined[0];
  const alternate=refined.find(c=>angleDistance(c.rotation,best.rotation)>25);
  const margin=best.score-(alternate?.score??0);
  // Broad shapes alone can resemble random patches; require supporting finer texture
  // at the SAME alignment, plus a distinct orientation and measurable contrast.
  const accepted=best.score>.45 && best.structureScore>.5 && best.textureScore>.2 &&
    margin>.08 && best.detail>.008 && best.clipped<.55;
  return {x:disc.x+best.dx*span/n,y:disc.y+best.dy*span/n,radius:disc.radius*best.scale,
    rotation:(best.rotation+360)%360,mirror,score:best.score,structureScore:best.structureScore,textureScore:best.textureScore,margin,detail:best.detail,clipped:best.clipped,accepted,
    reason:accepted?'matched':best.clipped>=.55?'clipped':best.detail<=.008?'detail':'uncertain'};
}

return { gray, sample, renderMoon, detectDisc, registerMoon };
})();
