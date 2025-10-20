WebGL Forward+ and Clustered Deferred Shading
======================

**University of Pennsylvania, CIS 565: GPU Programming and Architecture, Project 4**

* Harris Kokkinakos
* Tested on: **Google Chrome 141.0.7390.108** on
  Windows 24H2, i9-12900H @ 2.50GHz 16GB, RTX 3070TI Mobile

### Live Demo

[![](img/thumb.png)](http://TODO.github.io/Project4-WebGPU-Forward-Plus-and-Clustered-Deferred)

### Demo Video

https://github.com/user-attachments/assets/c1e57756-2535-4b24-b5bf-dba3b6e8c974

### Introduction

This project implements Forward+ and Clustered Deferred shading in WebGPU using TypeScript and WGSL.  
The goal is to explore modern GPU lighting techniques that scale efficiently with large light counts while remaining Web-friendly. This follows the trend of recent large game titles which require the calculation of lighitng in scenes with large amount of lights.

This README will cover the methods implemented and the performance of each method compared to each other. 

### Clustered Forward+ Rendering

Forward+ builds on traditional forward rendering but makes it much more efficient when lots of lights are in the scene. Instead of checking every single light for every pixel, the screen is split into a grid of small tiles. Instead of checking every light for each pixel, we now only check based on which lights and pixels are in which tiles. In my implementation, I divide the screen 16x9 tiles shown below:

![Forward+ Tiles](img/tiles.png)

Using a compute shader, the renderer figures out which lights actually affect each cluster by checking if a light’s sphere of influence overlaps that cluster’s bounding box. Because the frustum is also sliced in depth, lights are only assigned to clusters within their actual range. For example, a nearby light won’t waste time being processed by fragments far across the scene. The density of lights per tile can be represented in a heatmap which my renderer can show. In this heatmap, the color of each tile is blue when theres a low amount and is interpolated up to red if its at the max number of lights per tile.

![Heatmap](img/heatmap.png)

### Clustered Deferred Rendering

## Performance Analysis

### Credits

- [Vite](https://vitejs.dev/)
- [loaders.gl](https://loaders.gl/)
- [dat.GUI](https://github.com/dataarts/dat.gui)
- [stats.js](https://github.com/mrdoob/stats.js)
- [wgpu-matrix](https://github.com/greggman/wgpu-matrix)
