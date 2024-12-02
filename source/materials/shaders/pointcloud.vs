precision highp float;
precision highp int;

#define max_clip_boxes 30

in vec3 position;
in vec3 normal;
in float intensity;
in float classification;
in float returnNumber;
in float numberOfReturns;
in float pointSourceID;
in vec4 indices;

uniform mat4 modelMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat3 normalMatrix;

uniform float pcIndex;

uniform float screenWidth;
uniform float screenHeight;
uniform float fov;
uniform float spacing;

uniform bool useOrthographicCamera;
uniform float orthoWidth;
uniform float orthoHeight;

#if defined use_clip_box
	uniform mat4 clipBoxes[max_clip_boxes];
#endif

uniform float heightMin;
uniform float heightMax;
uniform float size; // pixel size factor
uniform float minSize; // minimum pixel size
uniform float maxSize; // maximum pixel size
uniform float octreeSize;
uniform vec3 bbSize;
uniform vec3 uColor;
uniform float opacity;
uniform float clipBoxCount;
uniform float level;
uniform float vnStart;
uniform bool isLeafNode;

uniform float filterByNormalThreshold;
uniform vec2 intensityRange;
uniform float opacityAttenuation;
uniform float intensityGamma;
uniform float intensityContrast;
uniform float intensityBrightness;
uniform float rgbGamma;
uniform float rgbContrast;
uniform float rgbBrightness;
uniform float transition;
uniform float wRGB;
uniform float wIntensity;
uniform float wElevation;
uniform float wClassification;
uniform float wReturnNumber;
uniform float wSourceID;
uniform float groundPlane;

uniform sampler2D visibleNodes;
uniform sampler2D gradient;
uniform sampler2D classificationLUT;
uniform sampler2D depthMap;

#ifdef highlight_point
	uniform vec3 highlightedPointCoordinate;
	uniform bool enablePointHighlighting;
	uniform float highlightedPointScale;
#endif

#ifdef new_format
	in vec4 rgba;
	out vec4 vColor;
#else
	in vec3 color;
	out vec3 vColor;
#endif

#if !defined(color_type_point_index)
	out float vOpacity;
#endif

#if defined(weighted_splats)
	out float vLinearDepth;
#endif

#ifdef use_edl
	out float vLogDepth;
#endif

out vec3 vViewPosition;

#if defined(weighted_splats) || defined(paraboloid_point_shape)
	out float vRadius;
#endif

#if defined(color_type_phong) && (MAX_POINT_LIGHTS > 0 || MAX_DIR_LIGHTS > 0)
	out vec3 vNormal;
#endif

#ifdef highlight_point
	out float vHighlight;
#endif
 
// ---------------------
// OCTREE
// ---------------------

#if (defined(adaptive_point_size) || defined(color_type_lod)) && defined(tree_type_octree)

/**
 * Gets the number of 1-bits up to inclusive index position.
 * 
 * number is treated as if it were an integer in the range 0-255
 */
int numberOfOnes(int number, int index) {
	int numOnes = 0;
	int tmp = 128;
	for (int i = 7; i >= 0; i--) {

		if (number >= tmp) {
			number = number - tmp;

			if (i <= index) {
				numOnes++;
			}
		}

		tmp = tmp / 2;
	}

	return numOnes;
}

/**
 * Checks whether the bit at index is 1.0
 *
 * number is treated as if it were an integer in the range 0-255
 */
bool isBitSet(int number, int index){

	// weird multi else if due to lack of proper array, int and bitwise support in WebGL 1.0
	int powi = 1;
	if (index == 0) {
		powi = 1;
	} else if (index == 1) {
		powi = 2;
	} else if (index == 2) {
		powi = 4;
	} else if (index == 3) {
		powi = 8;
	} else if (index == 4) {
		powi = 16;
	} else if (index == 5) {
		powi = 32;
	} else if (index == 6) {
		powi = 64;
	} else if (index == 7) {
		powi = 128;
	}

	int ndp = number / powi;

	return mod(float(ndp), 2.0) != 0.0;
}

/**
 * Gets the the LOD at the point position.
 */
float getLOD() {
	vec3 offset = vec3(0.0, 0.0, 0.0);
	int iOffset = int(vnStart);
	float depth = level;

	for (float i = 0.0; i <= 30.0; i++) {
		float nodeSizeAtLevel = octreeSize  / pow(2.0, i + level + 0.0);
		
		vec3 index3d = (position-offset) / nodeSizeAtLevel;
		index3d = floor(index3d + 0.5);
		int index = int(round(4.0 * index3d.x + 2.0 * index3d.y + index3d.z));
		
		vec4 value = texture(visibleNodes, vec2(float(iOffset) / 2048.0, 0.0));
		int mask = int(round(value.r * 255.0));

		if (isBitSet(mask, index)) {
			// there are more visible child nodes at this position
			int advanceG = int(round(value.g * 255.0)) * 256;
			int advanceB = int(round(value.b * 255.0));
			int advanceChild = numberOfOnes(mask, index - 1);
			int advance = advanceG + advanceB + advanceChild;

			iOffset = iOffset + advance;

			depth++;
		} else {
			return value.a * 255.0; // no more visible child nodes at this position
		}
		
		offset = offset + (vec3(1.0, 1.0, 1.0) * nodeSizeAtLevel * 0.5) * index3d;  
	}
		
	return depth;
}

float getPointSizeAttenuation() {
	return 0.5 * pow(2.0, getLOD());
}

#endif

// ---------------------
// KD-TREE
// ---------------------

#if (defined(adaptive_point_size) || defined(color_type_lod)) && defined(tree_type_kdtree)

float getLOD() {
	vec3 offset = vec3(0.0, 0.0, 0.0);
	float intOffset = 0.0;
	float depth = 0.0;
			
	vec3 size = bbSize;	
	vec3 pos = position;
		
	for (float i = 0.0; i <= 1000.0; i++) {
		
		vec4 value = texture(visibleNodes, vec2(intOffset / 2048.0, 0.0));
		
		int children = int(value.r * 255.0);
		float next = value.g * 255.0;
		int split = int(value.b * 255.0);
		
		if (next == 0.0) {
		 	return depth;
		}
		
		vec3 splitv = vec3(0.0, 0.0, 0.0);
		if (split == 1) {
			splitv.x = 1.0;
		} else if (split == 2) {
		 	splitv.y = 1.0;
		} else if (split == 4) {
		 	splitv.z = 1.0;
		}
		
		intOffset = intOffset + next;
		
		float factor = length(pos * splitv / size);
		if (factor < 0.5) {
		 	// left
			if (children == 0 || children == 2) {
				return depth;
			}
		} else {
			// right
			pos = pos - size * splitv * 0.5;
			if (children == 0 || children == 1) {
				return depth;
			}
			if (children == 3) {
				intOffset = intOffset + 1.0;
			}
		}
		size = size * ((1.0 - (splitv + 1.0) / 2.0) + 0.5);
		
		depth++;
	}
		
		
	return depth;	
}

float getPointSizeAttenuation() {
	return 0.5 * pow(1.3, getLOD());
}

#endif

// formula adapted from: http://www.dfstudios.co.uk/articles/programming/image-programming-algorithms/image-processing-algorithms-part-5-contrast-adjustment/
float getContrastFactor(float contrast) {
	return (1.0158730158730156 * (contrast + 1.0)) / (1.0158730158730156 - contrast);
}

#ifndef new_format

vec3 getRGB() {
	#if defined(use_rgb_gamma_contrast_brightness)
	  vec3 rgb = color;
		rgb = pow(rgb, vec3(rgbGamma));
		rgb = rgb + rgbBrightness;
		rgb = (rgb - 0.5) * getContrastFactor(rgbContrast) + 0.5;
		rgb = clamp(rgb, 0.0, 1.0);
		return rgb;
	#else
		return color;
	#endif
}

#endif

vec3 getIntensity() {
	float w = (intensity - intensityRange.x) / (intensityRange.y - intensityRange.x);
	w = pow(w, intensityGamma);
	w = w + intensityBrightness;
	w = (w - 0.5) * getContrastFactor(intensityContrast) + 0.5;
	w = clamp(w, 0.0, 1.0);
	
	// Map w to one of 30 colors
	if (w < 0.0333) return vec3(0.267, 0.004, 0.329);      // #440154
	else if (w < 0.0666) return vec3(0.278, 0.054, 0.380); // #470e61 
	else if (w < 0.1) return vec3(0.282, 0.106, 0.427);    // #481b6d
	else if (w < 0.1333) return vec3(0.282, 0.145, 0.463); // #482576
	else if (w < 0.1666) return vec3(0.275, 0.188, 0.494); // #46307e
	else if (w < 0.2) return vec3(0.267, 0.231, 0.518);    // #443b84
	else if (w < 0.2333) return vec3(0.251, 0.275, 0.533); // #404688
	else if (w < 0.2666) return vec3(0.235, 0.314, 0.545); // #3c508b
	else if (w < 0.3) return vec3(0.220, 0.349, 0.549);    // #38598c
	else if (w < 0.3333) return vec3(0.200, 0.384, 0.553); // #33628d
	else if (w < 0.3666) return vec3(0.184, 0.420, 0.557); // #2f6b8e
	else if (w < 0.4) return vec3(0.173, 0.451, 0.557);    // #2c738e
	else if (w < 0.4333) return vec3(0.157, 0.486, 0.557); // #287c8e
	else if (w < 0.4666) return vec3(0.145, 0.514, 0.557); // #25838e
	else if (w < 0.5) return vec3(0.133, 0.549, 0.553);    // #228c8d
	else if (w < 0.5333) return vec3(0.122, 0.580, 0.549); // #1f948c
	else if (w < 0.5666) return vec3(0.118, 0.616, 0.537); // #1e9d89
	else if (w < 0.6) return vec3(0.125, 0.643, 0.525);    // #20a486
	else if (w < 0.6333) return vec3(0.149, 0.678, 0.506); // #26ad81
	else if (w < 0.6666) return vec3(0.192, 0.710, 0.482); // #31b57b
	else if (w < 0.7) return vec3(0.247, 0.737, 0.451);    // #3fbc73
	else if (w < 0.7333) return vec3(0.314, 0.769, 0.416); // #50c46a
	else if (w < 0.7666) return vec3(0.376, 0.792, 0.376); // #60ca60
	else if (w < 0.8) return vec3(0.459, 0.816, 0.329);    // #75d054
	else if (w < 0.8333) return vec3(0.545, 0.839, 0.275); // #8bd646
	else if (w < 0.8666) return vec3(0.635, 0.855, 0.216); // #a2da37
	else if (w < 0.9) return vec3(0.729, 0.871, 0.157);    // #bade28
	else if (w < 0.9333) return vec3(0.816, 0.882, 0.110); // #d0e11c
	else if (w < 0.9666) return vec3(0.906, 0.894, 0.098); // #e7e419
	else return vec3(0.992, 0.906, 0.145);                 // #fde725
}

vec3 getElevation() {
	vec4 world = modelMatrix * vec4( position, 1.0 );
	float w = (world.z - heightMin) / (heightMax-heightMin);
	vec3 cElevation = texture(gradient, vec2(w,1.0-w)).rgb;
	
	return cElevation;
}

vec4 getClassification() {
	vec2 uv = vec2(classification / 255.0, 0.5);
	vec4 classColor = texture(classificationLUT, uv);
	
	return classColor;
}

vec3 getReturnNumber() {
	if (numberOfReturns == 1.0) {
		return vec3(1.0, 1.0, 0.0);
	} else {
		if (returnNumber == 1.0) {
			return vec3(1.0, 0.0, 0.0);
		} else if (returnNumber == numberOfReturns) {
			return vec3(0.0, 0.0, 1.0);
		} else {
			return vec3(0.0, 1.0, 0.0);
		}
	}
}

vec3 getSourceID() {
	float w = mod(pointSourceID, 10.0) / 10.0;
	return texture(gradient, vec2(w, 1.0 - w)).rgb;
}

#ifndef new_format

vec3 getCompositeColor() {
	vec3 c;
	float w;

	c += wRGB * getRGB();
	w += wRGB;
	
	c += wIntensity * getIntensity().x * vec3(1.0, 1.0, 1.0);
	w += wIntensity;
	
	c += wElevation * getElevation();
	w += wElevation;
	
	c += wReturnNumber * getReturnNumber();
	w += wReturnNumber;
	
	c += wSourceID * getSourceID();
	w += wSourceID;
	
	vec4 cl = wClassification * getClassification();
	c += cl.a * cl.rgb;
	w += wClassification * cl.a;

	c = c / w;
	
	if (w == 0.0) {
		gl_Position = vec4(100.0, 100.0, 100.0, 0.0);
	}
	
	return c;
}

#endif

#ifdef new_format
	vec4 fromLinear(vec4 linearRGB) {
		bvec4 cutoff = lessThan(linearRGB, vec4(0.0031308));
		vec4 higher = vec4(1.055)*pow(linearRGB, vec4(1.0/2.4)) - vec4(0.055);
		vec4 lower = linearRGB * vec4(12.92);
		return mix(higher, lower, cutoff);
	} 
	vec4 toLinear(vec4 sRGB) {
		bvec4 cutoff = lessThan(sRGB, vec4(0.04045));
		vec4 higher = pow((sRGB + vec4(0.055))/vec4(1.055), vec4(2.4));
		vec4 lower = sRGB/vec4(12.92);
		return mix(higher, lower, cutoff);
	}
#else
	vec3 fromLinear(vec3 linearRGB) {
		bvec3 cutoff = lessThan(linearRGB, vec3(0.0031308));
		vec3 higher = vec3(1.055)*pow(linearRGB, vec3(1.0/2.4)) - vec3(0.055);
		vec3 lower = linearRGB * vec3(12.92);
		return mix(higher, lower, cutoff);
	}
	vec3 toLinear(vec3 sRGB) {
		bvec3 cutoff = lessThan(sRGB, vec3(0.04045));
		vec3 higher = pow((sRGB + vec3(0.055))/vec3(1.055), vec3(2.4));
		vec3 lower = sRGB/vec3(12.92);
		return mix(higher, lower, cutoff);
	}
#endif

void main() {
	vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);

	gl_Position = projectionMatrix * mvPosition;

	vViewPosition = mvPosition.xyz;

	#if defined weighted_splats
		vLinearDepth = gl_Position.w;
	#endif

	#if defined(color_type_phong) && (MAX_POINT_LIGHTS > 0 || MAX_DIR_LIGHTS > 0)
		vNormal = normalize(normalMatrix * normal);
	#endif

	#ifdef use_edl
		vLogDepth = log2(-mvPosition.z);
	#endif

	// ---------------------
	// POINT SIZE
	// ---------------------

	float pointSize = 1.0;
	float slope = tan(fov / 2.0);
	float projFactor =  -0.5 * screenHeight / (slope * mvPosition.z);
	float scale = length(
		modelViewMatrix * vec4(0, 0, 0, 1) -
		modelViewMatrix * vec4(spacing, 0, 0, 1)
	) / spacing;
	projFactor = projFactor * scale;

	#if defined fixed_point_size
		pointSize = size;
	#elif defined attenuated_point_size
		// if (useOrthographicCamera){
		// 	pointSize = size;
		// } else {
		// pointSize = size * spacing * projFactor;
		pointSize = size * spacing * projFactor;
		// }
	#elif defined adaptive_point_size
		float worldSpaceSize = 2.0 * size * spacing / getPointSizeAttenuation();
		if(useOrthographicCamera) {
			pointSize = (worldSpaceSize / orthoWidth) * screenWidth;
		} else {
			pointSize = worldSpaceSize * projFactor;
		}
	#endif

	pointSize = max(minSize, pointSize);
	pointSize = min(maxSize, pointSize);

	#if defined(weighted_splats) || defined(paraboloid_point_shape)
		vRadius = pointSize / projFactor;
	#endif

	gl_PointSize = pointSize;

	// ---------------------
	// HIGHLIGHTING
	// ---------------------

	// #ifdef highlight_point
	// 	vec4 mPosition = modelMatrix * vec4(position, 1.0);
	// 	if (enablePointHighlighting && abs(mPosition.x - highlightedPointCoordinate.x) < 0.0001 &&
	// 		abs(mPosition.y - highlightedPointCoordinate.y) < 0.0001 &&
	// 		abs(mPosition.z - highlightedPointCoordinate.z) < 0.0001) {
	// 		vHighlight = 1.0;
	// 		gl_PointSize = pointSize * highlightedPointScale;
	// 	} else {
	// 		vHighlight = 0.0;
	// 	}
	// #endif

	// ---------------------
	// OPACITY
	// ---------------------

	// #ifndef color_type_point_index
	// 	#ifdef attenuated_opacity
	// 		vOpacity = opacity * exp(-length(-mvPosition.xyz) / opacityAttenuation);
	// 	#else
	// 		vOpacity = opacity;
	// 	#endif
	// #endif

	// ---------------------
	// FILTERING
	// ---------------------

	// #ifdef use_filter_by_normal
	// 	if(abs((modelViewMatrix * vec4(normal, 0.0)).z) > filterByNormalThreshold) {
	// 		// Move point outside clip space space to discard it.
	// 		gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
	// 	}
	// #endif

		// 	vec3 rgbColor = vec3(1.0, 1.0, 1.0);
        // #ifdef color_type_rgb
        //     rgbColor = rgba;
        // #elif defined color_type_intensity
        //     float w = getIntensity();
        //     rgbColor = vec3(w, w, w);
		// #endif
		// vColor = vec4(rgbColor, 1.0);

	// ---------------------
	// POINT COLOR
	// ---------------------	
	#ifdef color_type_intensity
		vec3 intensity = getIntensity();
		vColor = vec4(intensity, 1.0);	
	#elif defined color_type_classification
	 	vec4 cl = getClassification(); 
		vColor = cl;
	#elif defined new_format
		vec4 pointColor;
		if (rgba.r == 0.0 && rgba.g == 0.0 && rgba.b == 0.0) {
			pointColor = vec4(1.0, 1.0, 1.0, 1.0);
		} else {
			pointColor = rgba;
		}
		
		vec4 world = modelMatrix * vec4(position, 1.0);
		if (world.z < groundPlane) {
			// Ground points color
			vColor = vec4(0.1, 1.0, 1.0, 1.0);
		} else {
			vColor = pointColor;
		}
	#elif defined color_type_rgb
		vColor = getRGB();
	#elif defined color_type_height
		vColor = getElevation();
	#elif defined color_type_rgb_height
		vec3 cHeight = getElevation();
		vColor = (1.0 - transition) * getRGB() + transition * cHeight;
	#elif defined color_type_depth
		float linearDepth = -mvPosition.z ;
		float expDepth = (gl_Position.z / gl_Position.w) * 0.5 + 0.5;
		vColor = vec3(linearDepth, expDepth, 0.0);
	// #elif defined color_type_intensity_gradient
	// 	float w = getIntensity();
	// 	vColor = texture(gradient, vec2(w, 1.0 - w)).rgb;
	#elif defined color_type_color
		vColor = uColor;
	#elif defined color_type_lod
	float w = getLOD() / 10.0;
	vColor = texture(gradient, vec2(w, 1.0 - w)).rgb;
	#elif defined color_type_point_index
		vColor = indices.rgb;

	#elif defined color_type_return_number
		vColor = getReturnNumber();
	#elif defined color_type_source
		vColor = getSourceID();
	#elif defined color_type_normal
		vColor = (modelMatrix * vec4(normal, 0.0)).xyz;
	#elif defined color_type_phong
		vColor = color;
	#elif defined color_type_composite
		vColor = getCompositeColor();
	#endif
	
	#if !defined color_type_composite && defined color_type_classification
		if (cl.a == 0.0) {
			gl_Position = vec4(100.0, 100.0, 100.0, 0.0);
			return;
		}
	#endif

	// ---------------------
	// CLIPPING
	// ---------------------

	// #if defined use_clip_box
	// 	bool insideAny = false;
	// 	for (int i = 0; i < max_clip_boxes; i++) {
	// 		if (i == int(clipBoxCount)) {
	// 			break;
	// 		}
		
	// 		vec4 clipPosition = clipBoxes[i] * modelMatrix * vec4(position, 1.0);
	// 		bool inside = -0.5 <= clipPosition.x && clipPosition.x <= 0.5;
	// 		inside = inside && -0.5 <= clipPosition.y && clipPosition.y <= 0.5;
	// 		inside = inside && -0.5 <= clipPosition.z && clipPosition.z <= 0.5;
	// 		insideAny = insideAny || inside;
	// 	}

	// 	#if defined clip_outside
	// 		if (!insideAny) {
	// 			gl_Position = vec4(1000.0, 1000.0, 1000.0, 1.0);
	// 		}
	// 	#elif defined clip_inside
	// 		if (insideAny) {
	// 			gl_Position = vec4(1000.0, 1000.0, 1000.0, 1.0);
	// 		}
	// 	#elif defined clip_highlight_inside && !defined(color_type_depth)
	// 		if (!insideAny) {
	// 			float c = (vColor.r + vColor.g + vColor.b) / 6.0;
	// 		}
	// 	#endif

	// 	#if defined clip_highlight_inside
	// 		if (insideAny) {
	// 			vColor.r += 0.5;
	// 		}
	// 	#endif
	// #endif

	// #ifdef color_encoding_sRGB
	// 	#ifdef new_format
	// 		vColor = fromLinear(vColor);
	// 	#endif
	// #endif

	// #if defined(output_color_encoding_sRGB) && defined(input_color_encoding_linear)
	// 	vColor = toLinear(vColor);
	// #endif

	// #if defined(output_color_encoding_linear) && defined(input_color_encoding_sRGB)
	// 	vColor = fromLinear(vColor);
	// #endif
}
