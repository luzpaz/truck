struct VertexOutput {
    [[builtin(position)]] position: vec4<f32>;
    [[location(0)]] uv: vec2<f32>;
};

[[block]]
struct Lights {
    lights: [[stride(48)]] array<Light>;
};

[[group(0), binding(1)]]
var<storage> lights: Lights;

let PI: f32 = 3.141592653;
let EPS: f32 = 1.0e-6;

struct Camera {
    position: vec3<f32>;
    direction: vec3<f32>;
    up: vec3<f32>;
    fov: f32;
    aspect: f32;
};

struct Ray {
    origin: vec3<f32>;
    direction: vec3<f32>;
};

fn test_camera() -> Camera {
    var camera: Camera;
    camera.position = vec3<f32>(-1.0, 2.5, 2.0);
    camera.direction = normalize(vec3<f32>(0.25) - camera.position);
    camera.up = vec3<f32>(0.0, 1.0, 0.0);
    camera.fov = PI / 4.0;
    camera.aspect = 4.0 / 3.0;
    return camera;
}

fn nontex_material() -> Material {
    var mat: Material;
    mat.albedo = vec4<f32>(1.0);
    mat.roughness = 0.5;
    mat.reflectance = 0.25;
    mat.ambient_ratio = 0.02;
    return mat;
}

fn texture_color(position: vec3<f32>, normal: vec3<f32>) -> vec3<f32> {
    var uv: vec2<f32>;
    for (var i: u32 = 0u; i < 3u; i = i + 1u) {
        if (abs(normal[i]) > 0.5) {
            uv = vec2<f32>(position[(i + 1u) % 3u], position[(i + 2u) % 3u]);
        }
    }
    uv = 2.0 * uv - vec2<f32>(1.0);

    let r = length(uv) / sqrt(2.0);
    let l = 1.0 - r;
    let col0 = vec3<f32>(r, r * r, r * r * r);
    let col1 = vec3<f32>(l * l * l, l, l * l);
    return clamp(col0 + col1, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn tex_material(position: vec3<f32>, normal: vec3<f32>) -> Material {
    var mat: Material;
    mat.albedo = vec4<f32>(texture_color(position, normal), 1.0);
    mat.roughness = 0.5;
    mat.reflectance = 0.25;
    mat.ambient_ratio = 0.02;
    return mat;
}

fn camera_ray(camera: Camera, uv: vec2<f32>) -> Ray {
    var ray: Ray;
    ray.origin = camera.position;
    let camera_dir = camera.direction;
    let x_axis = normalize(cross(camera.direction, camera.up));
    let y_axis = normalize(cross(x_axis, camera.direction));
    ray.direction = camera_dir / tan(camera.fov / 2.0);
    ray.direction = ray.direction + uv.x * camera.aspect * x_axis + uv.y * y_axis;
    ray.direction = normalize(ray.direction);
    return ray;
}

struct RayTraceResult {
    collide: bool;
    position: vec3<f32>;
    normal: vec3<f32>;
};

fn ray_tracing(ray: Ray) -> RayTraceResult {
    var t: f32 = 1000.0;
    var position: vec3<f32>;
    var normal: vec3<f32>;
    for (var i: u32 = 0u; i < 3u; i = i + 1u) {
        let tmp = -ray.origin[i] / ray.direction[i];
        let pos = ray.origin + tmp * ray.direction;
        let flag = vec3<f32>(-EPS) <= pos && pos < vec3<f32>(1.0 + EPS);
        if (0.0 < tmp && tmp < t && all(flag)) {
            t = tmp;
            position = pos;
            normal = vec3<f32>(0.0);
            normal[i] = -1.0;
        }
    }
    for (var i: u32 = 0u; i < 3u; i = i + 1u) {
        let tmp = (1.0 - ray.origin[i]) / ray.direction[i];
        let pos = ray.origin + tmp * ray.direction;
        let flag = vec3<f32>(-EPS) <= pos && pos < vec3<f32>(1.0 + EPS);
        if (0.0 < tmp && tmp < t && all(flag)) {
            t = tmp;
            position = pos;
            normal = vec3<f32>(0.0);
            normal[i] = 1.0;
        }
    }
    var res: RayTraceResult;
    res.collide = t < 900.0;
    res.position = position;
    res.normal = normal;
    return res;
}


[[stage(vertex)]]
fn vs_main([[location(0)]] idx: u32) -> VertexOutput {
    var vertex: array<vec2<f32>, 4>;
    vertex[0] = vec2<f32>(-1.0, -1.0);
    vertex[1] = vec2<f32>(1.0, -1.0);
    vertex[2] = vec2<f32>(-1.0, 1.0);
    vertex[3] = vec2<f32>(1.0, 1.0);

    var output: VertexOutput;
    output.position = vec4<f32>(vertex[idx], 0.0, 1.0);
    output.uv = vertex[idx];
    return output;
}

[[stage(fragment)]]
fn nontex_raytracing([[location(0)]] uv: vec2<f32>) -> [[location(0)]] vec4<f32> {
    let camera = test_camera();
    let ray = camera_ray(camera, uv);
    let res = ray_tracing(ray);
    
    if(!res.collide) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    let light = lights.lights[0];
    let mat = nontex_material();
    
    var pre_color: vec3<f32> = microfacet_color(res.position, res.normal, light, -ray.direction, mat);
    pre_color = clamp(pre_color, vec3<f32>(0.0), vec3<f32>(1.0));
    pre_color = ambient_correction(pre_color, mat);
    return vec4<f32>(pre_color, 1.0);
}

[[stage(fragment)]]
fn tex_raytracing([[location(0)]] uv: vec2<f32>) -> [[location(0)]] vec4<f32> {
    let camera = test_camera();
    let ray = camera_ray(camera, uv);
    let res = ray_tracing(ray);
    
    if(!res.collide) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    let light = lights.lights[0];
    let mat = tex_material(res.position, res.normal);
    
    var pre_color: vec3<f32> = microfacet_color(res.position, res.normal, light, -ray.direction, mat);
    pre_color = clamp(pre_color, vec3<f32>(0.0), vec3<f32>(1.0));
    pre_color = ambient_correction(pre_color, mat);
    return vec4<f32>(pre_color, 1.0);
}