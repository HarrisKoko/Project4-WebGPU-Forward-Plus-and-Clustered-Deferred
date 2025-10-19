// TODO-3: implement the Clustered Deferred G-buffer fragment shader

// This shader should only store G-buffer information and should not do any shading.

@group(${bindGroup_scene}) @binding(0) var<uniform> camera: CameraUniforms;

@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

struct FragmentInput {
    @location(0) pos: vec3f,  // world space
    @location(1) nor: vec3f,
    @location(2) uv: vec2f
};

struct GBufferOutput {
    @location(0) position: vec4f,
    @location(1) normal: vec4f,
    @location(2) albedo: vec4f
};

@fragment
fn main(in: FragmentInput) -> GBufferOutput {
    var output: GBufferOutput;
    
    // Store world-space position
    output.position = vec4f(in.pos, 1.0);
    
    // Store normalized normal
    output.normal = vec4f(normalize(in.nor), 1.0);
    
    // Store albedo color from texture
    let albedo = textureSample(diffuseTex, diffuseTexSampler, in.uv);
    output.albedo = albedo;
    
    return output;
}