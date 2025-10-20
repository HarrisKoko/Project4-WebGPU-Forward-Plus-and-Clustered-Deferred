// TODO-2: implement the light clustering compute shader

// ------------------------------------
// Calculating cluster bounds:
// ------------------------------------
// For each cluster (X, Y, Z):
//     - Calculate the screen-space bounds for this cluster in 2D (XY).
//     - Calculate the depth bounds for this cluster in Z (near and far planes).
//     - Convert these screen and depth bounds into view-space coordinates.
//     - Store the computed bounding box (AABB) for the cluster.

// ------------------------------------
// Assigning lights to clusters:
// ------------------------------------
// For each cluster:
//     - Initialize a counter for the number of lights in this cluster.
//
//     For each light:
//         - Check if the light intersects with the cluster's bounding box (AABB).
//         - If it does, add the light to the cluster's light list.
//         - Stop adding lights if the maximum number of lights is reached.
//
//     - Store the number of lights assigned to this cluster.


// struct Light { pos: vec3f, color: vec3f }
// struct LightSet { numLights: u32, lights: array<Light> }
// struct ClusterSet { numLights: u32, lights: array<u32, ${maxLights}> }
// struct CameraUniforms { viewProjMat, inverseProjMat, viewMat, invViewMat, params0, params1 }
// params0 = (zNear, zFar, screenWidthPx, screenHeightPx)
// params1 = (tilesX, tilesY, tilesZ, k)

@group(0) @binding(0) var<uniform> uCamera : CameraUniforms;
@group(0) @binding(1) var<storage, read> uLightSet : LightSet;
@group(0) @binding(2) var<storage, read_write> uClusters : array<ClusterSet>;

const MAX_LIGHTS_PER_CLUSTER : u32 = ${maxLights}u;
const LIGHT_RADIUS : f32 = f32(2.f);

// Logarithmic depth slicing: returns [near, far] z bounds for this slice.
fn slice_edges_z(slice: u32) -> vec2<f32> {
  let nearZ = uCamera.params0.x;
  let farZ = uCamera.params0.y;
  let slices = uCamera.params1.z;
  let k = max(uCamera.params1.w, 1.0);

  let nz = max(nearZ, 1e-4);
  let fz = max(farZ, nz + 1e-4);
  let denom = log(1.0 + k * fz) - log(1.0 + k * nz);

  let s0 = f32(slice) / slices;
  let s1 = f32(slice + 1u) / slices;

  let A = exp(s0 * denom) * (1.0 + k * nz);
  let B = exp(s1 * denom) * (1.0 + k * nz);

  let z0 = (A - 1.0) / k;
  let z1 = (B - 1.0) / k;
  return vec2<f32>(z0, z1);
}

// Convert pixel coordinates to NDC [-1, 1]. Y is flipped for screen space.
fn ndc_from_px(px: vec2<f32>, screenW: f32, screenH: f32) -> vec2<f32> {
  return vec2<f32>((px.x / screenW) * 2.0 - 1.0, -((px.y / screenH) * 2.0 - 1.0));
}

// Unproject NDC coordinate to get view-space ray direction.
fn view_ray_dir_from_ndc(ndcXY: vec2<f32>) -> vec3<f32> {
  let p4 = uCamera.inverseProjMat * vec4<f32>(ndcXY, 1.0, 1.0);
  let p  = p4.xyz / max(p4.w, 1e-6);
  return normalize(p); 
}

// Build view-space AABB for a tile at a given depth slice.
// We shoot rays from the 4 screen corners and intersect with near/far planes.
fn cluster_aabb_view(tileMinPx: vec2<f32>, tileMaxPx: vec2<f32>, slice: u32, screenW: f32, screenH: f32) -> array<vec3<f32>, 2> {

  let zEdges = slice_edges_z(slice);
  let zNear = zEdges.x;
  let zFar  = zEdges.y;

  // 4 screen corners in pixels
  let c0 = vec2<f32>(tileMinPx.x, tileMinPx.y);
  let c1 = vec2<f32>(tileMaxPx.x, tileMinPx.y);
  let c2 = vec2<f32>(tileMinPx.x, tileMaxPx.y);
  let c3 = vec2<f32>(tileMaxPx.x, tileMaxPx.y);

  // Convert to NDC
  let n0 = ndc_from_px(c0, screenW, screenH);
  let n1 = ndc_from_px(c1, screenW, screenH);
  let n2 = ndc_from_px(c2, screenW, screenH);
  let n3 = ndc_from_px(c3, screenW, screenH);

  // Get ray directions in view space
  let r0 = view_ray_dir_from_ndc(n0);
  let r1 = view_ray_dir_from_ndc(n1);
  let r2 = view_ray_dir_from_ndc(n2);
  let r3 = view_ray_dir_from_ndc(n3);

  // Intersect rays with near and far planes (view-space Z is negative forward)
  let p0n = r0 * (-zNear / min(r0.z, -1e-6));
  let p1n = r1 * (-zNear / min(r1.z, -1e-6));
  let p2n = r2 * (-zNear / min(r2.z, -1e-6));
  let p3n = r3 * (-zNear / min(r3.z, -1e-6));

  let p0f = r0 * (-zFar / min(r0.z, -1e-6));
  let p1f = r1 * (-zFar / min(r1.z, -1e-6));
  let p2f = r2 * (-zFar / min(r2.z, -1e-6));
  let p3f = r3 * (-zFar / min(r3.z, -1e-6));

  // Find AABB containing all 8 points
  var mn = min(min(min(p0n, p1n), min(p2n, p3n)), min(min(p0f, p1f), min(p2f, p3f)));
  var mx = max(max(max(p0n, p1n), max(p2n, p3n)), max(max(p0f, p1f), max(p2f, p3f)));

  return array<vec3<f32>, 2>(mn, mx);
}

// Sphere-AABB intersection test using closest point method.
fn sphere_intersects_aabb(center: vec3<f32>, radius: f32, aabbMin: vec3<f32>, aabbMax: vec3<f32>) -> bool {
  let clamped = clamp(center, aabbMin, aabbMax);
  let d = center - clamped;
  let d2 = dot(d, d);        
  return d2 <= (radius * radius);
}


@compute @workgroup_size(1, 1, 1)
fn main(@builtin(global_invocation_id) gid : vec3<u32>) {
  let tilesX = u32(uCamera.params1.x);
  let tilesY = u32(uCamera.params1.y);
  let tilesZ = u32(uCamera.params1.z);

  if (gid.x >= tilesX || gid.y >= tilesY || gid.z >= tilesZ) { return; }

  let screenW = uCamera.params0.z;
  let screenH = uCamera.params0.w;

  // Calculate pixel bounds for this cluster's screen tile
  let tileW = screenW / f32(tilesX);
  let tileH = screenH / f32(tilesY);

  let tileMinPx = vec2<f32>(f32(gid.x) * tileW, f32(gid.y) * tileH);
  let tileMaxPx = tileMinPx + vec2<f32>(tileW, tileH);

  // Build view-space AABB for this cluster
  let aabb = cluster_aabb_view(tileMinPx, tileMaxPx, gid.z, screenW, screenH);
  let aabbMin = aabb[0];
  let aabbMax = aabb[1];

  // Flat index for this cluster (Z-major ordering)
  let clusterId = gid.z * tilesY * tilesX + gid.y * tilesX + gid.x;

  uClusters[clusterId].numLights = 0u;

  // Test each light against this cluster's AABB
  for (var li: u32 = 0u; li < uLightSet.numLights; li = li + 1u) {
    let L = uLightSet.lights[li];
    let centerVS = (uCamera.viewMat * vec4<f32>(L.pos, 1.0)).xyz;
    let radius = LIGHT_RADIUS;

    if (sphere_intersects_aabb(centerVS, radius, aabbMin, aabbMax)) {
      let idx = uClusters[clusterId].numLights;
      if (idx < MAX_LIGHTS_PER_CLUSTER) {
        // Store light index and increment count
        uClusters[clusterId].lights[idx] = li;
        uClusters[clusterId].numLights = idx + 1u;
      }
    }
  }
}