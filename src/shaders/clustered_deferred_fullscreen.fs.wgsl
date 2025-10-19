// TODO-3: implement the Clustered Deferred fullscreen fragment shader

// Similar to the Forward+ fragment shader, but with vertex information coming from the G-buffer instead.

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

@group(${bindGroup_scene}) @binding(0) var<uniform> camera: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read> clusters: array<ClusterSet>;

@group(1) @binding(0) var gBufferPosition: texture_2d<f32>;
@group(1) @binding(1) var gBufferNormal: texture_2d<f32>;
@group(1) @binding(2) var gBufferAlbedo: texture_2d<f32>;

// Debug toggles
const SHOW_ALBEDO   : bool = false; 
const SHOW_NORMAL   : bool = false; 
const SHOW_POSITION : bool = false; 

// Convert view-space depth to slice index using logarithmic distribution
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

@fragment
fn main(@builtin(position) fragCoord: vec4f) -> @location(0) vec4f {
    // Sample G-buffer textures to get geometry information
    let pixelCoord = vec2i(floor(fragCoord.xy));
    let position = textureLoad(gBufferPosition, pixelCoord, 0).xyz;
    let normal = textureLoad(gBufferNormal, pixelCoord, 0).xyz;
    let albedo = textureLoad(gBufferAlbedo, pixelCoord, 0).rgb;

    // Early exit if this pixel wasn't written (background)
    if (length(normal) < 0.1) {
        return vec4f(0.0, 0.0, 0.0, 1.0);
    }

    // Debug: visualize individual G-buffer channels
    if (SHOW_ALBEDO) {
        return vec4f(albedo, 1.0);
    }
    if (SHOW_NORMAL) {
        let N = normalize(normal);
        return vec4f(0.5 * N + vec3f(0.5), 1.0);
    }
    if (SHOW_POSITION) {
        // visualize view-space depth using world position and camera.viewMat
        let viewZ = abs((camera.viewMat * vec4f(position, 1.0)).z);
        let nearZ = camera.params0.x;
        let farZ  = camera.params0.y;
        let depthLin = clamp((viewZ - nearZ) / (farZ - nearZ), 0.0, 1.0);
        return vec4f(vec3f(depthLin), 1.0);
    }

    // Determine which cluster this fragment belongs to
    let screenW = camera.params0.z;
    let screenH = camera.params0.w;
    let tilesX = u32(camera.params1.x);
    let tilesY = u32(camera.params1.y);

    // Calculate tile indices from screen coordinates
    let tileW = screenW / f32(tilesX);
    let tileH = screenH / f32(tilesY);
    let tileX = u32(clamp(i32(floor(fragCoord.x / tileW)), 0, i32(tilesX) - 1));
    let tileY = u32(clamp(i32(floor(fragCoord.y / tileH)), 0, i32(tilesY) - 1));

    // Calculate depth slice from view-space Z
    let viewPos = (camera.viewMat * vec4f(position, 1.0)).xyz;
    let slice = u32(clamp(z_to_slice(abs(viewPos.z)), 0, i32(camera.params1.z) - 1));

    // Calculate flat cluster index
    let clusterId = slice * tilesY * tilesX + tileY * tilesX + tileX;

    // Perform clustered lighting
    let cnt = clusters[clusterId].numLights;
    var totalLightContrib = vec3f(0.0, 0.0, 0.0);
    let N = normalize(normal);

    // Accumulate lighting from all lights in this cluster
    for (var i: u32 = 0u; i < cnt; i = i + 1u) {
        let Lidx = clusters[clusterId].lights[i];
        let light = lightSet.lights[Lidx];
        totalLightContrib += calculateLightContrib(light, position, N);
    }

    let finalColor = albedo * totalLightContrib;
    return vec4f(finalColor, 1.0);
}
