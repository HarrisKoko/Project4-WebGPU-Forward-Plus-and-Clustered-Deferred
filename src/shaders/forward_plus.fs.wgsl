// TODO-2: implement the Forward+ fragment shader

// See naive.fs.wgsl for basic fragment shader setup; this shader should use light clusters instead of looping over all lights

// ------------------------------------
// Shading process:
// ------------------------------------
// Determine which cluster contains the current fragment.
// Retrieve the number of lights that affect the current fragment from the cluster's data.
// Initialize a variable to accumulate the total light contribution for the fragment.
// For each light in the cluster:
//     Access the light's properties using its index.
//     Calculate the contribution of the light based on its position, the fragment's position, and the surface normal.
//     Add the calculated contribution to the total light accumulation.
// Multiply the fragment's diffuse color by the accumulated light contribution.
// Return the final color, ensuring that the alpha component is set appropriately (typically to 1).

// struct Light { pos: vec3f, color: vec3f }
// struct LightSet { numLights: u32, lights: array<Light> }
// struct ClusterSet { numLights: u32, lights: array<u32, ${maxLights}> }
// struct CameraUniforms { viewProjMat, inverseProjMat, viewMat, invViewMat, params0, params1 }
// params0 = (zNear, zFar, screenWidthPx, screenHeightPx)
// params1 = (tilesX, tilesY, tilesZ, k)

// @group(0) @binding(0) var<uniform> uCamera : CameraUniforms;
// @group(0) @binding(1) var<storage, read> uLightSet : LightSet;
// @group(0) @binding(2) var<storage, read_write> uClusters : array<ClusterSet>;


@group(${bindGroup_scene}) @binding(0) var<uniform> camera : CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read> clusters: array<ClusterSet>;

@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

// Debug toggles
const SHOW_TILES : bool = false; // show tile grid colors
const SHOW_HEATMAP : bool = false; // visualize num lights per cluster

struct FragmentInput {
    @location(0) pos: vec3f, // world space
    @location(1) nor: vec3f,
    @location(2) uv: vec2f
};

// Convert view-space depth to slice index using logarithmic distribution.
fn z_to_slice(zView: f32) -> i32 {
    let nearZ = camera.params0.x;
    let farZ  = camera.params0.y;
    let slices = camera.params1.z;
    let k = max(camera.params1.w, 1.0);

    let nz = max(nearZ, 1e-4);
    let fz = max(farZ, nz + 1e-4);
    let t = clamp((log(1.0 + k * zView) - log(1.0 + k * nz)) /(log(1.0 + k * fz) - log(1.0 + k * nz)), 0.0, 0.9999);
    return i32(floor(t * slices));
}

// Generate pseudo-random color for tile visualization.
fn hash2_to_rgb(x: u32, y: u32) -> vec3f {
    let fx = fract(sin(f32(x) * 12.9898 + f32(y) * 78.233) * 43758.5453);
    let fy = fract(sin(f32(x) * 93.9898 + f32(y) * 47.233) * 12345.6789);
    let fz = fract(sin(f32(x) * 41.1234 + f32(y) * 19.4321) * 98765.4321);
    return vec3f(fx, fy, fz);
}

@fragment
fn main(in: FragmentInput) -> @location(0) vec4f {
    let screenW = camera.params0.z;
    let screenH = camera.params0.w;
    let tilesXf = camera.params1.x;
    let tilesYf = camera.params1.y;

    // Project world position to NDC to find screen pixel coordinates
    let clip = camera.viewProjMat * vec4f(in.pos, 1.0);
    let ndc = clip.xyz / max(clip.w, 1e-6);

    // Convert NDC to pixel coordinates
    let px = vec2f((ndc.x * 0.5 + 0.5) * screenW, (-(ndc.y) * 0.5 + 0.5) * screenH);

    // Determine which tile this pixel belongs to
    let tileW = screenW / tilesXf;
    let tileH = screenH / tilesYf;
    let tileX = u32(clamp(i32(floor(px.x / tileW)), 0, i32(tilesXf) - 1));
    let tileY = u32(clamp(i32(floor(px.y / tileH)), 0, i32(tilesYf) - 1));

    // Determine depth slice from view-space Z
    let viewPos = (camera.viewMat * vec4f(in.pos, 1.0)).xyz;
    let slice = u32(clamp(z_to_slice(abs(viewPos.z)), 0, i32(camera.params1.z) - 1));

    // Calculate flat cluster index
    let tilesX = u32(tilesXf);
    let tilesY = u32(tilesYf);
    let clusterId = slice * tilesY * tilesX + tileY * tilesX + tileX;

    // Debug: visualize tile boundaries with random colors
    if (SHOW_TILES) {
        var color = hash2_to_rgb(tileX, tileY);
        let fx = fract(px.x / tileW);
        let fy = fract(px.y / tileH);
        let gx = min(fx, 1.0 - fx);
        let gy = min(fy, 1.0 - fy);
        let isLine = (gx * tileW < 1.0) || (gy * tileH < 1.0);
        if (isLine) { color = vec3f(0.0, 0.0, 0.0); }
        return vec4f(color, 1.0);
    }

    // Debug: heatmap showing number of lights per cluster
    if (SHOW_HEATMAP) {
        let cnt = clusters[clusterId].numLights;
        let t = clamp(f32(cnt) / f32(${maxLights}), 0.0, 1.0);
        // Blue -> green -> red gradient based on light count
        let color = mix(vec3f(0.0,0.0,0.3), vec3f(0.0,1.0,0.0), t * 2.0)+ mix(vec3f(0.0), vec3f(1.0,0.0,0.0), max(t - 0.5, 0.0) * 2.0);
        return vec4f(color, 1.0);
    }

    // Forward+ shading: only process lights in this cluster
    let diffuseColor = textureSample(diffuseTex, diffuseTexSampler, in.uv);
    let cnt = clusters[clusterId].numLights;

    var totalLightContrib = vec3f(0.0, 0.0, 0.0);
    let N = normalize(in.nor);

    // Accumulate lighting from all lights in this cluster
    for (var i: u32 = 0u; i < cnt; i = i + 1u) {
        let Lidx = clusters[clusterId].lights[i];
        let light = lightSet.lights[Lidx];
        totalLightContrib += calculateLightContrib(light, in.pos, N);
    }

    let finalColor = diffuseColor.rgb * totalLightContrib;
    return vec4f(finalColor, 1.0);
}