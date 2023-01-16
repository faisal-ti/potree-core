# Potree Core

[![npm version](https://badge.fury.io/js/potree-core.svg)](https://badge.fury.io/js/potree-core)
[![GitHub version](https://badge.fury.io/gh/tentone%2Fpotree-core.svg)](https://badge.fury.io/gh/tentone%2Fpotree-core)

 - This project was originally based on [Potree Viewer 1.6](https://github.com/potree/potree) and is now since version 2.0 based on the [shiukaheng fork](https://github.com/shiukaheng/potree-loader) of the [Potree-Loader](https://github.com/pnext/three-loader).
 - Potree is a web based pouint cloud visualizer project created by Markus Schütz.
 - This project contains only the main parts of the potree project adapted to be more easily used as a independent library, the code was adapted from the original repositorys.
 - Support for pointclouds from LAS, LAZ, Binary files and Greyhound server.

 ### TODO
 - Supports logarithmic depth buffer (just by enabling it on the threejs renderer), useful for large scale visualization.
 - Point clouds are automatically updated, frustum culling is used to avoid unnecessary updates (better update performance for multiple point clouds).


## How to use
 - Download the custom potree build from the build folder or add it to your project using NPM.
    - https://www.npmjs.com/package/potree-core
 - Include it alonside the worker folder in your project (can be found on the source folder).
 - Download threejs from github repository.
    - https://github.com/mrdoob/three.js/tree/dev/build
 - The build is a ES module, that can be imported to other projects, it assumes the existence of THREE namespace for threejs dependencies.


## Testing
 - The project can be build running the commands `npm install` and `npm run build`.

## Demo
 - Live demo at https://tentone.github.io/potree-core/
 - Contains the same model multiple times stored in different formats.
 - Double click the models to raycast the scene and create marker points.

<img src="https://raw.githubusercontent.com/tentone/potree-core/master/screenshot.png" width="700">


## Example
 - Bellow its a fully functional example of how to use this wrapper to load potree point clouds to a THREE.js project

```javascript
var scene = new THREE.Scene();
var camera = new THREE.PerspectiveCamera(60, 1, 0.1, 10000);

var canvas = document.createElement("canvas");
canvas.style.position = "absolute";
canvas.style.top = "0px";
canvas.style.left = "0px";
canvas.style.width = "100%";
canvas.style.height = "100%";
document.body.appendChild(canvas);

var renderer = new THREE.WebGLRenderer({canvas:canvas});

var geometry = new THREE.BoxGeometry(1, 1, 1);
var material = new THREE.MeshBasicMaterial({color: 0x00ff00});
var cube = new THREE.Mesh(geometry, material);
scene.add(cube);

var controls = new THREE.OrbitControls(camera, canvas);
camera.position.z = 10;

var points = new Potree.Group();
points.setPointBudget(10000000)
scene.add(points);

Potree.loadPointCloud("data/test/cloud.js", name, function(data)
{
	var pointcloud = data.pointcloud;
	points.add(pointcloud);
});

function loop()
{
	controls.update();
	renderer.render(scene, camera);
	requestAnimationFrame(loop);
};
loop();

document.body.onresize = function()
{
	var width = window.innerWidth;
	var height = window.innerHeight;
	renderer.setSize(width, height);
	camera.aspect = width / height;
	camera.updateProjectionMatrix();
}
document.body.onresize();
```


## Notes
 - Since potree-core is meant to be used as library and not as a full software as potree some features are not available.
 - EDL shading is not supported by potree core.
 - Removed classification and clipping functionality.
 - Removed Arena 4D point cloud support.
 - GUI elements were removed from the library
   - PotreeViewer
   - Controls, Input, GUI, Tools
   - Anotations, Actions, ProfileRequest
   - Potree.startQuery, Potree.endQuery and Potree.resolveQueries
   - Potree.timerQueries
   - Potree.MOUSE, Potree.CameraMode
   - PotreeRenderer, RepRenderer, Potree.Renderer
     - JQuery, TWEEN and Proj4 dependencies


## Potree Converter
 - Use the (Potree Converter)[https://github.com/potree/PotreeConverter/releases] tool to create point cloud data from LAS, ZLAS or BIN point cloud files
 - Potree Converter 1.8 creates a multi file structure with each node as an individual file.
 - Potree Converter 2.1 creates a single file for all points and separates files for hierarchy index, its faster to create files. Requires a HTTP server configured for file streaming.
 - Tool to create hierarquical structure used for point-cloud rendering using potree-core.
 - There are two main versions 2.1 witch generates 4 contained files with point data, hierarchy, 
 - To generate a folder output from a input file run the command `.\PotreeConverter '..\input.laz' -o ../output`

### TXT2LAS
 - The potree converter tool only supports las and laz files, so textural file formats such as .pts, .xyz, have to be first converted into a supported format.
 - The TXT2LAS tool from the (LASTools)[https://github.com/LAStools/LAStools] repository can be used for this effect.
 - To run the tool use the command `.\txt2las64 -i input.pts -ipts -parse xyziRGB  -set_scale 0.001 0.001 0.001 -set_version 1.4 -o output.laz`



## API Reference

 - The project has no generated documentation but bellow are some of the main configuration elements.
 - A example can be found in the repository `index.html` file.



### Potree.BasicGroup

- Container that stores point cloud objects and updates them on render.
- The container supports frustum culling using the point cloud bouding box.
- Automatically stops updating the point cloud if out of view.
- This container only support pointColorType set as RGB, pointSizeType set as FIXED and shape set as SQUARE.



### Potree.Group

- Complete container with support for all potree features.
- Some features require support for the following GL extensions

   - EXT_frag_depth, WEBGL_depth_texture, OES_vertex_array_object

   

### Potree.loadPointCloud

- Method to load a point cloud database file
- `Potree.loadPointCloud(url, name, onLoad)`



### Potree.PointCloudMaterial

- Material used by threejs to draw the point clouds, based on RawShaderMaterial
- shape
   - Defines the shape used to draw points
      - Potree.PointShape.SQUARE
      - Potree.PointShape.CIRCLE
      - Potree.PointShape.PARABOLOID
- pointSizeType
   - Defines how the point cloud points are sized, fixed mode keeps the same size, adaptive resizes points accordingly to their distance to the camera 
   - Possible values are
      - Potree.PointSizeType.FIXED
      - Potree.PointSizeType.ATTENUATED
      - Potree.PointSizeType.ADAPTIVE
- pointColorType
   - Defines how to color the drawn points
   - Possible values are
      - Potree.PointColorType.RGB
      - Potree.PointColorType.COLOR
      - Potree.PointColorType.DEPTH
      - Potree.PointColorType.HEIGHT
      - Potree.PointColorType.INTENSITY
      - Potree.PointColorType.INTENSITY_GRADIENT
      - Potree.PointColorType.LOD
      - Potree.PointColorType.POINT_INDEX
      - Potree.PointColorType.CLASSIFICATION
      - Potree.PointColorType.RETURN_NUMBER
      - Potree.PointColorType.SOURCE
      - Potree.PointColorType.NORMAL
      - Potree.PointColorType.PHONG
      - Potree.PointColorType.RGB_HEIGHT
- logarithmicDepthBuffer
   - Set true to enable logarithmic depth buffer
- weighted
   - If true points are drawn as weighted splats
- treeType
   - Defines the type of point cloud tree being drawn by this material
   - This should be automatically defined by the loader
      - Potree.TreeType.OCTREE
      - Potree.TreeType.KDTREE

 - Potree.PointCloudTree
    - Base Object3D used to store and represent point cloud data.
    - These objects are created by the loader

