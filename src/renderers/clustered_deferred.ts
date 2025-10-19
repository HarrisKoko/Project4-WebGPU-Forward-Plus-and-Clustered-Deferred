import * as renderer from '../renderer';
import * as shaders from '../shaders/shaders';
import { Stage } from '../stage/stage';

export class ClusteredDeferredRenderer extends renderer.Renderer {
    // TODO-3: add layouts, pipelines, textures, etc. needed for Forward+ here
    // you may need extra uniforms such as the camera view matrix and the canvas resolution

    // G-buffer textures
    gBufferPosition: GPUTexture;
    gBufferPositionView: GPUTextureView;
    gBufferNormal: GPUTexture;
    gBufferNormalView: GPUTextureView;
    gBufferAlbedo: GPUTexture;
    gBufferAlbedoView: GPUTextureView;
    depthTexture: GPUTexture;
    depthTextureView: GPUTextureView;

    // Bind groups and layouts
    sceneUniformsBindGroupLayout: GPUBindGroupLayout;
    sceneUniformsBindGroup: GPUBindGroup;
    gBufferBindGroupLayout: GPUBindGroupLayout;
    gBufferBindGroup: GPUBindGroup;

    // Pipelines
    gBufferPipeline: GPURenderPipeline;
    fullscreenPipeline: GPURenderPipeline;

    constructor(stage: Stage) {
        super(stage);

        // TODO-3: initialize layouts, pipelines, textures, etc. needed for Forward+ here
        // you'll need two pipelines: one for the G-buffer pass and one for the fullscreen pass

        // Create G-buffer textures (position, normal, albedo)
        this.gBufferPosition = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: 'rgba16float',  // Need float for world-space positions
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        });
        this.gBufferPositionView = this.gBufferPosition.createView();

        this.gBufferNormal = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: 'rgba16float',  // Float for precise normals
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        });
        this.gBufferNormalView = this.gBufferNormal.createView();

        this.gBufferAlbedo = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: 'rgba8unorm',  // 8-bit is fine for color
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        });
        this.gBufferAlbedoView = this.gBufferAlbedo.createView();

        this.depthTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: 'depth24plus',
            usage: GPUTextureUsage.RENDER_ATTACHMENT
        });
        this.depthTextureView = this.depthTexture.createView();

        // Scene uniforms bind group layout (camera, lights, clusters)
        this.sceneUniformsBindGroupLayout = renderer.device.createBindGroupLayout({
            label: "clustered deferred scene uniforms bind group layout",
            entries: [
                {
                    binding: 0,
                    visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
                    buffer: { type: "uniform" }  // Camera uniforms
                },
                {
                    binding: 1,
                    visibility: GPUShaderStage.FRAGMENT,
                    buffer: { type: "read-only-storage" }  // Light set
                },
                {
                    binding: 2,
                    visibility: GPUShaderStage.FRAGMENT,
                    buffer: { type: "read-only-storage" }  // Cluster light indices
                }
            ]
        });

        this.sceneUniformsBindGroup = renderer.device.createBindGroup({
            label: "clustered deferred scene uniforms bind group",
            layout: this.sceneUniformsBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: { buffer: this.camera.uniformsBuffer }
                },
                {
                    binding: 1,
                    resource: { buffer: this.lights.lightSetStorageBuffer }
                },
                {
                    binding: 2,
                    resource: { buffer: this.lights.clusterLightIndicesBuffer }
                }
            ]
        });

        // G-buffer bind group layout for fullscreen pass
        this.gBufferBindGroupLayout = renderer.device.createBindGroupLayout({
            label: "g-buffer bind group layout",
            entries: [
                {
                    binding: 0,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: { sampleType: 'unfilterable-float' }  // Position texture
                },
                {
                    binding: 1,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: { sampleType: 'unfilterable-float' }  // Normal texture
                },
                {
                    binding: 2,
                    visibility: GPUShaderStage.FRAGMENT,
                    texture: { sampleType: 'float' }  // Albedo texture
                }
            ]
        });

        this.gBufferBindGroup = renderer.device.createBindGroup({
            label: "g-buffer bind group",
            layout: this.gBufferBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: this.gBufferPositionView
                },
                {
                    binding: 1,
                    resource: this.gBufferNormalView
                },
                {
                    binding: 2,
                    resource: this.gBufferAlbedoView
                }
            ]
        });

        // G-buffer pass pipeline
        this.gBufferPipeline = renderer.device.createRenderPipeline({
            layout: renderer.device.createPipelineLayout({
                label: "g-buffer pipeline layout",
                bindGroupLayouts: [
                    this.sceneUniformsBindGroupLayout,
                    renderer.modelBindGroupLayout,
                    renderer.materialBindGroupLayout
                ]
            }),
            depthStencil: {
                depthWriteEnabled: true,
                depthCompare: "less",
                format: "depth24plus"
            },
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "g-buffer vert shader",
                    code: shaders.naiveVertSrc  // Same vertex shader as naive/forward+
                }),
                buffers: [renderer.vertexBufferLayout]
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "g-buffer frag shader",
                    code: shaders.clusteredDeferredFragSrc
                }),
                targets: [
                    { format: 'rgba16float' },  // Position
                    { format: 'rgba16float' },  // Normal
                    { format: 'rgba8unorm' }    // Albedo
                ]
            }
        });

        // Fullscreen pass pipeline
        this.fullscreenPipeline = renderer.device.createRenderPipeline({
            layout: renderer.device.createPipelineLayout({
                label: "fullscreen pipeline layout",
                bindGroupLayouts: [
                    this.sceneUniformsBindGroupLayout,
                    this.gBufferBindGroupLayout
                ]
            }),
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "fullscreen vert shader",
                    code: shaders.clusteredDeferredFullscreenVertSrc
                })
                // No vertex buffers needed for fullscreen quad
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "fullscreen frag shader",
                    code: shaders.clusteredDeferredFullscreenFragSrc
                }),
                targets: [
                    { format: renderer.canvasFormat }
                ]
            }
        });
    }

    override draw() {
        // TODO-3: run the Forward+ rendering pass:
        // - run the clustering compute shader
        // - run the G-buffer pass, outputting position, albedo, and normals
        // - run the fullscreen pass, which reads from the G-buffer and performs lighting calculations

        const encoder = renderer.device.createCommandEncoder();

        // Run compute shader to assign lights to clusters
        this.lights.doLightClustering(encoder);

        // G-buffer pass: render geometry to textures
        const gBufferPass = encoder.beginRenderPass({
            label: "g-buffer pass",
            colorAttachments: [
                {
                    view: this.gBufferPositionView,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                },
                {
                    view: this.gBufferNormalView,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                },
                {
                    view: this.gBufferAlbedoView,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                }
            ],
            depthStencilAttachment: {
                view: this.depthTextureView,
                depthClearValue: 1.0,
                depthLoadOp: "clear",
                depthStoreOp: "store"
            }
        });

        gBufferPass.setPipeline(this.gBufferPipeline);
        gBufferPass.setBindGroup(shaders.constants.bindGroup_scene, this.sceneUniformsBindGroup);

        // Draw all geometry to G-buffer
        this.scene.iterate(node => {
            gBufferPass.setBindGroup(shaders.constants.bindGroup_model, node.modelBindGroup);
        }, material => {
            gBufferPass.setBindGroup(shaders.constants.bindGroup_material, material.materialBindGroup);
        }, primitive => {
            gBufferPass.setVertexBuffer(0, primitive.vertexBuffer);
            gBufferPass.setIndexBuffer(primitive.indexBuffer, 'uint32');
            gBufferPass.drawIndexed(primitive.numIndices);
        });

        gBufferPass.end();

        // Fullscreen pass: perform lighting using G-buffer data
        const canvasTextureView = renderer.context.getCurrentTexture().createView();

        const fullscreenPass = encoder.beginRenderPass({
            label: "fullscreen deferred lighting pass",
            colorAttachments: [
                {
                    view: canvasTextureView,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                }
            ]
        });

        fullscreenPass.setPipeline(this.fullscreenPipeline);
        fullscreenPass.setBindGroup(0, this.sceneUniformsBindGroup);
        fullscreenPass.setBindGroup(1, this.gBufferBindGroup);

        fullscreenPass.draw(6);

        fullscreenPass.end();

        renderer.device.queue.submit([encoder.finish()]);
    }
}