// SCP-173 v2 : modèle organique (mesh) + rendu + export OBJ pour Roblox
const W = 1200, H = 750;
THREE.ColorManagement.legacyMode = false;
const rad = (d) => d * Math.PI / 180;
const V2 = (x, y) => new THREE.Vector2(x, y);
const V3 = (x, y, z) => new THREE.Vector3(x, y, z);

// ---------- bruit pour l'aspect "béton fait main" ----------
function noise(p) {
  return 0.55 * Math.sin(p.x * 2.1 + p.y * 1.3) * Math.sin(p.y * 1.7 - p.z * 2.4) +
    0.30 * Math.sin(p.x * 5.3 - p.z * 4.1 + p.y * 0.7) * Math.sin(p.y * 4.9 + p.x * 1.1) +
    0.15 * Math.sin(p.x * 11.7 + p.y * 13.1) * Math.sin(p.z * 12.3 - p.y * 9.7);
}
function lumpy(geo, amp) {
  geo.computeVertexNormals();
  const pos = geo.attributes.position, nor = geo.attributes.normal, p = V3();
  for (let i = 0; i < pos.count; i++) {
    p.fromBufferAttribute(pos, i);
    const d = noise(p) * amp;
    pos.setXYZ(i, p.x + nor.getX(i) * d, p.y + nor.getY(i) * d, p.z + nor.getZ(i) * d);
  }
  geo.computeVertexNormals();
  return geo;
}

const groups = { Body: [], PaintBlack: [], PaintRed: [], PaintGreen: [], Rebar: [] };
const root = new THREE.Group();
function addMesh(group, geo) {
  const m = new THREE.Mesh(geo);
  m.userData.group = group;
  groups[group].push(m);
  root.add(m);
  return m;
}

// ---------- CORPS ----------
// Tête + cou + torse en un seul profil tourné (silhouette "cacahuète" allongée)
const profile = [
  [0.001, 3.1], [0.62, 3.15], [0.74, 3.5], [0.70, 4.1], [0.62, 4.7], [0.66, 5.2], [0.72, 5.6],
  [0.66, 6.0], [0.50, 6.35], [0.44, 6.6], [0.52, 6.9], [0.70, 7.3], [0.82, 7.8], [0.86, 8.3],
  [0.82, 8.8], [0.70, 9.25], [0.48, 9.6], [0.22, 9.8], [0.001, 9.85],
].map(([r, y]) => V2(r, y));
const trunk = new THREE.LatheGeometry(profile, 48);
trunk.scale(1, 1, 0.82);
// légère inclinaison de la tête vers l'avant
{
  const pos = trunk.attributes.position;
  for (let i = 0; i < pos.count; i++) {
    const y = pos.getY(i);
    if (y > 6.5) pos.setZ(i, pos.getZ(i) - (y - 6.5) * 0.06);
  }
}
const trunkMesh = addMesh('Body', lumpy(trunk, 0.07));

// Jambes fines, légèrement arquées
function limb(points, radius, segs = 28) {
  const curve = new THREE.CatmullRomCurve3(points);
  const g = new THREE.TubeGeometry(curve, segs, radius, 14, false);
  // affinement progressif
  const pos = g.attributes.position, c = V3(), p = V3();
  for (let i = 0; i < pos.count; i++) {
    const t = Math.floor(i / 15) / segs;
    curve.getPointAt(Math.min(t, 1), c);
    p.fromBufferAttribute(pos, i).sub(c).multiplyScalar(1 - 0.25 * t).add(c);
    pos.setXYZ(i, p.x, p.y, p.z);
  }
  return g;
}
for (const s of [-1, 1]) {
  addMesh('Body', lumpy(limb([V3(0.32 * s, 3.4, 0), V3(0.36 * s, 2.2, -0.05), V3(0.30 * s, 1.0, 0.02), V3(0.30 * s, 0.25, 0)], 0.27), 0.03));
  const foot = new THREE.SphereGeometry(0.3, 18, 12); foot.scale(1, 0.55, 1.5); foot.translate(0.3 * s, 0.17, -0.12);
  addMesh('Body', lumpy(foot, 0.03));
  const knee = new THREE.SphereGeometry(0.28, 14, 10); knee.translate(0.35 * s, 3.3, 0);
  addMesh('Body', knee);
}
// Petits bras repliés vers l'avant (le signe distinctif)
for (const s of [-1, 1]) {
  const sh = V3(0.62 * s, 5.55, -0.05);
  const elbow = V3(0.78 * s, 4.75, -0.2);
  const hand = V3(0.55 * s, 4.95, -0.75);
  addMesh('Body', lumpy(limb([sh, V3(0.74 * s, 5.15, -0.1), elbow, V3(0.7 * s, 4.82, -0.5), hand], 0.2, 24), 0.025));
  for (const [p, r] of [[sh, 0.22], [elbow, 0.2]]) { const j = new THREE.SphereGeometry(r, 12, 10); j.translate(p.x, p.y, p.z); addMesh('Body', j); }
  const fist = new THREE.SphereGeometry(0.2, 14, 10); fist.scale(1.1, 0.9, 1.2); fist.translate(hand.x, hand.y, hand.z - 0.08);
  addMesh('Body', lumpy(fist, 0.03));
}

// ---------- PEINTURE (posée sur la surface par lancer de rayons) ----------
root.updateMatrixWorld(true);
const ray = new THREE.Raycaster();
function surface(x, y, front = true) {
  ray.set(V3(x, y, front ? -5 : 5), V3(0, 0, front ? 1 : -1));
  const hit = ray.intersectObject(trunkMesh)[0];
  if (!hit) return null;
  return { p: hit.point, n: hit.face.normal.clone().transformDirection(trunkMesh.matrixWorld) };
}
function blob(group, x, y, sx, sy, thick = 0.02, rot = 0, front = true) {
  const s = surface(x, y, front); if (!s) return;
  const g = new THREE.SphereGeometry(1, 10, 6);
  g.scale(sx, sy, thick);
  const m = new THREE.Matrix4();
  const q = new THREE.Quaternion().setFromUnitVectors(V3(0, 0, 1), s.n);
  m.compose(s.p.clone().addScaledVector(s.n, -thick * 0.35), q.multiply(new THREE.Quaternion().setFromAxisAngle(V3(0, 0, 1), rot)), V3(1, 1, 1));
  g.applyMatrix4(m);
  addMesh(group, g);
}
function stroke(group, pts, w, step = 0.04) {
  for (let i = 0; i < pts.length - 1; i++) {
    const [a, b] = [pts[i], pts[i + 1]];
    const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
    for (let t = 0; t <= len; t += step) {
      const k = t / len;
      blob(group, a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, w, w * 0.8, 0.018);
    }
  }
}
// Yeux : orbites noires creuses, entourées de rouge, qui coulent
for (const s of [-1, 1]) {
  for (let a = 0; a < 360; a += 12) {
    blob('PaintRed', 0.3 * s + Math.cos(rad(a)) * 0.19, 8.15 + Math.sin(rad(a)) * 0.24, 0.085, 0.085, 0.018);
  }
  blob('PaintBlack', 0.3 * s, 8.15, 0.14, 0.18, 0.025);
}
stroke('PaintRed', [[-0.33, 7.92], [-0.35, 7.6], [-0.34, 7.35]], 0.045); // coulure œil gauche
stroke('PaintRed', [[0.27, 7.9], [0.26, 7.72]], 0.04);
// Bouche : fente noire de travers
blob('PaintBlack', 0.03, 7.55, 0.2, 0.06, 0.025, rad(-6));
// Grande balafre verte en diagonale sur le crâne (signature "aérosol")
stroke('PaintGreen', [[-0.55, 9.25], [-0.15, 8.75], [0.2, 8.55], [0.55, 8.1]], 0.075);
// Taches rouges sur le torse et vertes sur le flanc
blob('PaintRed', -0.25, 5.4, 0.22, 0.3, 0.02, rad(20));
stroke('PaintRed', [[-0.25, 5.15], [-0.22, 4.7]], 0.05);
stroke('PaintGreen', [[0.5, 6.0], [0.45, 5.3], [0.5, 4.6]], 0.06);

// ---------- ARMATURE ROUILLÉE (sort du dos) ----------
function rebar(a, b, r = 0.06) {
  const g = new THREE.CylinderGeometry(r, r, a.distanceTo(b), 8);
  const mid = a.clone().add(b).multiplyScalar(0.5);
  const q = new THREE.Quaternion().setFromUnitVectors(V3(0, 1, 0), b.clone().sub(a).normalize());
  g.applyMatrix4(new THREE.Matrix4().compose(mid, q, V3(1, 1, 1)));
  addMesh('Rebar', g);
}
rebar(V3(0.1, 5.9, 0.2), V3(0.55, 6.9, 1.3));
rebar(V3(-0.2, 4.9, 0.2), V3(-0.9, 5.2, 1.2));
rebar(V3(0.0, 9.3, 0.3), V3(0.15, 10.1, 0.75), 0.05);

// ---------- Export OBJ (un objet par groupe => un MeshPart par couleur dans Roblox) ----------
root.updateMatrixWorld(true);
let obj = '# SCP-173 (design original) - unites = studs Roblox, face vers -Z\n';
let vOff = 1;
for (const [name, meshes] of Object.entries(groups)) {
  obj += `o ${name}\ng ${name}\n`;
  for (const m of meshes) {
    const g = m.geometry.clone().applyMatrix4(m.matrixWorld);
    g.computeVertexNormals();
    const pos = g.attributes.position, nor = g.attributes.normal;
    for (let i = 0; i < pos.count; i++) obj += `v ${pos.getX(i).toFixed(4)} ${pos.getY(i).toFixed(4)} ${pos.getZ(i).toFixed(4)}\n`;
    for (let i = 0; i < nor.count; i++) obj += `vn ${nor.getX(i).toFixed(4)} ${nor.getY(i).toFixed(4)} ${nor.getZ(i).toFixed(4)}\n`;
    const idx = g.index ? g.index.array : [...Array(pos.count).keys()];
    for (let i = 0; i < idx.length; i += 3) {
      const [a, b, c] = [idx[i] + vOff, idx[i + 1] + vOff, idx[i + 2] + vOff];
      obj += `f ${a}//${a} ${b}//${b} ${c}//${c}\n`;
    }
    vOff += pos.count;
  }
}
window.OBJ = obj;
let tris = 0; root.traverse(o => { if (o.isMesh) tris += (o.geometry.index ? o.geometry.index.count : o.geometry.attributes.position.count) / 3; });
window.TRIS = tris + ' ' + JSON.stringify(Object.fromEntries(Object.entries(groups).map(([k, ms]) => [k, ms.reduce((n, m) => n + (m.geometry.index ? m.geometry.index.count : m.geometry.attributes.position.count) / 3, 0)])));

// ---------- RENDU ----------
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(window.devicePixelRatio);
renderer.setSize(W, H);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputEncoding = THREE.sRGBEncoding;
document.body.appendChild(renderer.domElement);
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0b0c0d);

// béton beige avec salissures (couleurs par sommet)
function grime(geo, base) {
  const pos = geo.attributes.position, col = [], p = V3(), c = new THREE.Color();
  for (let i = 0; i < pos.count; i++) {
    p.fromBufferAttribute(pos, i);
    const n = noise(p.clone().multiplyScalar(2.2)) * 0.5 + 0.5;
    const dirt = Math.max(0, 1 - p.y / 3) * 0.25; // plus sale en bas
    const blotch = Math.max(0, noise(p.clone().multiplyScalar(0.9).addScalar(3.7))) ;
    c.copy(base).multiplyScalar(0.62 + n * 0.38 - dirt - blotch * 0.25);
    col.push(c.r, c.g, c.b);
  }
  geo.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
}
const BASE = new THREE.Color('#c4b591');
const MATS = {
  Body: new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.95 }),
  PaintBlack: new THREE.MeshStandardMaterial({ color: '#0d0a09', roughness: 0.7 }),
  PaintRed: new THREE.MeshStandardMaterial({ color: '#7a0f0b', roughness: 0.6 }),
  PaintGreen: new THREE.MeshStandardMaterial({ color: '#3d6424', roughness: 0.65 }),
  Rebar: new THREE.MeshStandardMaterial({ color: '#6e3e26', roughness: 0.8, metalness: 0.5 }),
};
root.traverse(o => {
  if (!o.isMesh) return;
  if (o.userData.group === 'Body') grime(o.geometry, BASE);
  o.material = MATS[o.userData.group];
  o.castShadow = o.receiveShadow = true;
});
scene.add(root);

function tex(base, amount, size = 256) {
  const c = document.createElement('canvas'); c.width = c.height = size;
  const g = c.getContext('2d'); g.fillStyle = base; g.fillRect(0, 0, size, size);
  const img = g.getImageData(0, 0, size, size);
  for (let i = 0; i < img.data.length; i += 4) { const n = (Math.random() - 0.5) * amount; img.data[i] += n; img.data[i + 1] += n; img.data[i + 2] += n; }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; t.encoding = THREE.sRGBEncoding; return t;
}
const ft = tex('#4d4a45', 30); ft.repeat.set(6, 6);
const floor = new THREE.Mesh(new THREE.PlaneGeometry(40, 40), new THREE.MeshStandardMaterial({ map: ft, roughness: 1 }));
floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true; scene.add(floor);
const wallMat = new THREE.MeshStandardMaterial({ map: tex('#9a978f', 22), roughness: 1 });
const back = new THREE.Mesh(new THREE.BoxGeometry(40, 18, 1), wallMat); back.position.set(0, 9, 4); back.receiveShadow = true; scene.add(back);
const side = new THREE.Mesh(new THREE.BoxGeometry(1, 18, 40), wallMat); side.position.set(-6, 9, 0); side.receiveShadow = true; scene.add(side);

scene.add(new THREE.HemisphereLight(0xb8c4d0, 0x2a241c, 0.45));
const spot = new THREE.SpotLight(0xfff4e6, 2.0, 60, rad(30), 0.6, 1.1);
spot.position.set(4, 18, -9); spot.target.position.set(0, 5, 0); spot.castShadow = true;
spot.shadow.mapSize.set(2048, 2048); spot.shadow.bias = -0.0004;
scene.add(spot, spot.target);
const fill = new THREE.DirectionalLight(0x8899aa, 0.35); fill.position.set(-6, 6, -8); scene.add(fill);

const camA = new THREE.PerspectiveCamera(34, (W / 2) / H, 0.1, 200);
camA.position.set(4.5, 6.5, -17); camA.lookAt(0, 5.0, 0);
const camB = new THREE.PerspectiveCamera(30, (W / 2) / H, 0.1, 200);
camB.position.set(1.6, 8.4, -6.8); camB.lookAt(0, 8.0, 0);
renderer.setScissorTest(true);
renderer.setScissor(0, 0, W / 2, H); renderer.setViewport(0, 0, W / 2, H); renderer.render(scene, camA);
renderer.setScissor(W / 2, 0, W / 2, H); renderer.setViewport(W / 2, 0, W / 2, H); renderer.render(scene, camB);
window.DONE = true;
