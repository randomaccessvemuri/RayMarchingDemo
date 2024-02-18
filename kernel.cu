#include <cuda_runtime.h>
#include <math.h>
#include <device_launch_parameters.h>
#include <stdio.h>
#include <SFML/Graphics.hpp>
#include <imgui-SFML.h>
#include <imgui.h>

#define IMAGE_X 1920
#define IMAGE_Y 1080

__device__ __host__ float length(const float3& v)
{
	return sqrtf(v.x * v.x + v.y * v.y + v.z * v.z);
}

__device__ __host__ float3 operator-(const float3& a, const float3& b)
{
	return make_float3(a.x - b.x, a.y - b.y, a.z - b.z);
}

__device__ __host__ float3 operator+(const float3& a, const float3& b)
{
	return make_float3(a.x + b.x, a.y + b.y, a.z + b.z);
}

__device__ __host__ float3 operator*(const float3& a, const float3& b)
{
	return make_float3(a.x * b.x, a.y * b.y, a.z * b.z);
}

__device__ __host__ float3 operator*(const float3& a, float b)
{
	return make_float3(a.x * b, a.y * b, a.z * b);
}

__device__ __host__ float3 operator/(const float3& a, float b)
{
	return make_float3(a.x / b, a.y / b, a.z / b);
}

__device__ __host__ float3 unitVector(const float3& v)
{
	return v / length(v);
}


__interface IHittable
{
	//Get distance from query point to the surface of the object
	__device__ __host__ float SDF(const float3& pos) const;

};

class Sphere : public IHittable
{
public:
	float3 center;
	float radius;

	__device__ __host__ Sphere(float3 center, float radius) : center(center), radius(radius) {}

	__device__ __host__ float SDF(const float3& pos) const override
	{
		return length(pos - center) - radius;
	}


};

__global__ void renderSphereOnly(Sphere sphereIn, int3* image, float3 cameraLookAt, float3 cameraLocation) {
	int x = blockIdx.x * blockDim.x + threadIdx.x;
	int y = blockIdx.y * blockDim.y + threadIdx.y;
	if (x >= IMAGE_X || y >= IMAGE_Y) return;

	float u = float(x) / IMAGE_X;
	float v = float(y) / IMAGE_Y;

	float3 cameraRayDir = unitVector(cameraLookAt - cameraLocation);
	//Displace the ray based on the pixel position
	float aspectRatio = float(IMAGE_X) / float(IMAGE_Y);

	cameraRayDir.x = cameraRayDir.x + (2 * u - 1) * aspectRatio * 0.1;
	cameraRayDir.y = cameraRayDir.y + (2 * v - 1) * 0.1;

	//Normalize the ray direction (NECESSARY OTHERWISE IT CAUSES ALL KINDS OF WEIRD DISTORTIONS)
	cameraRayDir = unitVector(cameraRayDir);


	float3 pos = cameraLocation;
	float t = 0;
	float dist = sphereIn.SDF(pos);



	int maxIter = 1000;
	
	for (int i = 0; i < maxIter; i++) {
		//printf("Distance to sphere: %f\n", dist);
		if (x==250 && y==250) printf("Distance to sphere: %f\n", dist);
			if (dist < 0.001) {
				image[y * IMAGE_X + x] = make_int3(255, 255, 255);
				return;
			} else if (t > 100) {
				image[y * IMAGE_X + x] = make_int3(0, 0, 0);
				return;
			}
			t += dist;
			pos = cameraLocation + cameraRayDir * t;
			dist = sphereIn.SDF(pos);
			
	}
}

void writeImageToFile(int3* image, int width, int height) {
	FILE* file = fopen("image.ppm", "w");
	fprintf(file, "P3\n%d %d\n%d\n", width, height, 255);
	for (int i = 0; i < width * height; i++) {
		fprintf(file, "%d %d %d ", image[i].x, image[i].y, image[i].z);
	}
	fclose(file);
}




int main() {
	int3* image = new int3[IMAGE_X * IMAGE_Y];
	int3* d_image;

	cudaMalloc(&d_image, IMAGE_X * IMAGE_Y * sizeof(int3));
	Sphere sphere(make_float3(0, 1, -1.2), 1.19);

	//Camera
	float3 cameraLocation = make_float3(2.98, -0.8, 1.3);
	float3 cameraLookAt = make_float3(-0.226, 0.972, 0.122);
	

	

	

	//Display image
	sf::RenderWindow window(sf::VideoMode(IMAGE_X, IMAGE_Y), "Raymarching");
	ImGui::SFML::Init(window);
	sf::Texture texture;
	texture.create(IMAGE_X, IMAGE_Y);
	sf::Sprite sprite(texture);
	sf::Uint8* pixels = new sf::Uint8[IMAGE_X * IMAGE_Y * 4];
	sf::Clock deltaClock;



while (window.isOpen()) {
		sf::Event event;
		while (window.pollEvent(event)) {
			ImGui::SFML::ProcessEvent(window, event);
			if (event.type == sf::Event::Closed) {
				window.close();
			}
		}
		ImGui::SFML::Update(window, deltaClock.restart());


		ImGui::Begin("Hello, world!");

		//Set sphere center
		ImGui::DragFloat3("Center", &sphere.center.x, 0.01f, -10.0f, 10.0f);
		ImGui::DragFloat("Radius", &sphere.radius, 0.01f, 0.0f, 10.0f);

		//Set camera location
		ImGui::DragFloat3("Camera Location: ", &cameraLocation.x, 0.01f, -100.f, 100.0f);
		ImGui::DragFloat3("Camera Look At: ", &cameraLookAt.x, 0.01f, -10.0f, 10.0f);
		if (ImGui::Button("Render")) {
			dim3 blockSize(16, 16);
			dim3 numBlocks((IMAGE_X + blockSize.x - 1) / blockSize.x, (IMAGE_Y + blockSize.y - 1) / blockSize.y);
			renderSphereOnly << <numBlocks, blockSize >> > (sphere, d_image, cameraLookAt, cameraLocation);
			cudaMemcpy(image, d_image, IMAGE_X * IMAGE_Y * sizeof(int3), cudaMemcpyDeviceToHost);
			for (int i = 0; i < IMAGE_X * IMAGE_Y; i++) {
				pixels[i * 4] = image[i].x;
				pixels[i * 4 + 1] = image[i].y;
				pixels[i * 4 + 2] = image[i].z;
				pixels[i * 4 + 3] = 255;
			}
			printf("Rendered!");
			texture.update(pixels);
		}
		
		ImGui::End();

		

		window.clear();
		window.draw(sprite);
		ImGui::SFML::Render(window);
		window.display();
	}


	writeImageToFile(image, IMAGE_X, IMAGE_Y);

	//SDF TEST
	float3 pos = make_float3(0, 1, -1.2);
	float dist = sphere.SDF(pos);
	printf("Distance to sphere: %f\n", dist);

	
}