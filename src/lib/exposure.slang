public module auto_exposure;

RWStructuredBuffer<ExposureBuffer> exposure;

struct ExposureBuffer {
	float average;
}
