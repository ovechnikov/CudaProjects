// Monte Carlo simulation of a snowball fight:

// system includes
#include <stdio.h>
#define _USE_MATH_DEFINES
#include <math.h>

// CUDA runtime functions and utilities
// This include files are from CUDA 12.1 sample program
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
// Helper functions and utilities to work with CUDA
#include "helper_cuda.h"

// setting the number of trials in the Monte Carlo simulation:
int NUMTRIALS = 4194304;

int BLOCKSIZE = 128;     // number of threads per block

#define NUMBLOCKS	(NUMTRIALS / BLOCKSIZE)

// ranges for the random numbers:
const float TXMIN   = -10.0;	// truck starting location in feet
const float TXMAX   = 10.0;		// truck starting location in feet
const float TXVMIN  = 15.0;		// truck x velocity in feet/sec
const float TXVMAX  = 35.0;		// truck x velocity in feet/sec
const float TYMIN   = 40.0;		// depth distance to truck in feet
const float TYMAX   = 50.0;		// depth distance to truck in feet
const float SVMIN   = 5.0;		// snowball velocity in feet/sec
const float SVMAX   = 30.0;		// snowball velocity in feet/sec
const float STHMIN  = 10.0;		// snowball launch angle in degrees
const float STHMAX  = 70.0;		// snowball launch angle in degrees
const float HALFLENMIN = 15.;	// half length of the truck in feet
const float HALFLENMAX = 30.;	// half length of the truck in feet

// these are here just to be pretty labels, other than that, they do nothing:
#define IN
#define OUT

void
CudaCheckError()
{
    cudaError_t e = cudaGetLastError();
    if (e != cudaSuccess)
    {
        fprintf(stderr, "Cuda failure %s:%d: '%s'\n", __FILE__, __LINE__, cudaGetErrorString(e));
    }
}

// degrees-to-radians:
__device__
float
Radians(float d)
{
    return (M_PI / 180.f) * d;
}

// Random generation functions
float
Ranf(float low, float high)
{
    float r = (float)rand();		// 0 - RAND_MAX
    float t = r / (float)RAND_MAX;	// 0. - 1.

    return low + t * (high - low);
}

int
Ranf(int ilow, int ihigh)
{
    float low = (float)ilow;
    float high = ceil((float)ihigh);

    return (int)Ranf(low, high);
}

void
TimeOfDaySeed()
{
    struct tm y2k = { 0 };
    y2k.tm_hour = 0;   y2k.tm_min = 0; y2k.tm_sec = 0;
    y2k.tm_year = 100; y2k.tm_mon = 0; y2k.tm_mday = 1;

    time_t timer;
    time(&timer);
    double seconds = difftime(timer, mktime(&y2k));
    unsigned int seed = (unsigned int)(1000. * seconds);	// milliseconds
    srand(seed);
}

// Kernel function
__global__
void
MonteCarlo(IN float* dtxs, IN float* dtys, IN float* dtxvs, IN float* dsvs, IN float* dsths, IN float* dhalflens, OUT int* dhits)
{
    unsigned int gid = blockIdx.x * blockDim.x + threadIdx.x;

    dhits[gid] = 0;

    // randomize everything:
    float tx    = dtxs[gid];
    float ty    = dtys[gid];
    float txv   = dtxvs[gid];
    float sv    = dsvs[gid];
    float sthd  = dsths[gid];
    float sthr  = Radians(sthd);
    float svx   = sv * cos(sthr);
    float svy   = sv * sin(sthr);

    // how long until the snowball reaches the y depth:
    float t = ty / svy;

    // how far the truck has moved in x in that amount of time:
    float truckx = tx + txv * t;

    // how far the snowball has moved in x in that amount of time:
    float sbx = svx * t;

    // if the snowball hits, set to 1, otherwise 0
    dhits[gid] = (fabs(sbx - truckx) < dhalflens[gid]) ? 1 : 0;
}

// main program:
int
main(int argc, char* argv[])
{
    // Adding command line parameters support
    if (argc >= 2) {
        NUMTRIALS = atoi(argv[1]);
    }
    if (argc >= 3) {
        BLOCKSIZE = atoi(argv[2]);
    }

    TimeOfDaySeed();

    int dev = findCudaDevice(argc, (const char**)argv);

    float* htxs     = new float[NUMTRIALS];
    float* htys     = new float[NUMTRIALS];
    float* htxvs    = new float[NUMTRIALS];
    float* hsvs     = new float[NUMTRIALS];
    float* hsths    = new float[NUMTRIALS];
    float* hhalflens = new float[NUMTRIALS];

    // fill the random-value arrays:
    for (int n = 0; n < NUMTRIALS; n++)
    {
        htxs[n]     = Ranf(TXMIN, TXMAX);
        htys[n]     = Ranf(TYMIN, TYMAX);
        htxvs[n]    = Ranf(TXVMIN, TXVMAX);
        hsvs[n]     = Ranf(SVMIN, SVMAX);
        hsths[n]    = Ranf(STHMIN, STHMAX);
        hhalflens[n] = Ranf(HALFLENMIN, HALFLENMAX);
    }

    int* hhits = new int[NUMTRIALS];

    // allocate device memory:
    float* dtxs, * dtys, * dtxvs, * dsvs, * dsths, * dhalflens;
    int* dhits;

    //cudaError_t status;
    cudaMalloc((void**)(&dtxs), NUMTRIALS * sizeof(float));
    CudaCheckError();
    cudaMalloc((void**)(&dtys), NUMTRIALS * sizeof(float));
    CudaCheckError();
    cudaMalloc((void**)(&dtxvs), NUMTRIALS * sizeof(float));
    CudaCheckError();
    cudaMalloc((void**)(&dsvs), NUMTRIALS * sizeof(float));
    CudaCheckError();
    cudaMalloc((void**)(&dsths), NUMTRIALS * sizeof(float));
    CudaCheckError();
    cudaMalloc((void**)(&dhalflens), NUMTRIALS * sizeof(float));
    CudaCheckError();
    cudaMalloc((void**)(&dhits), NUMTRIALS * sizeof(float));
    CudaCheckError();

    // copy host memory to the device:
    cudaMemcpy(dtxs, htxs, NUMTRIALS * sizeof(float), cudaMemcpyHostToDevice);
    CudaCheckError();
    cudaMemcpy(dtys, htys, NUMTRIALS * sizeof(float), cudaMemcpyHostToDevice);
    CudaCheckError();
    cudaMemcpy(dtxvs, htxvs, NUMTRIALS * sizeof(float), cudaMemcpyHostToDevice);
    CudaCheckError();
    cudaMemcpy(dsvs, hsvs, NUMTRIALS * sizeof(float), cudaMemcpyHostToDevice);
    CudaCheckError();
    cudaMemcpy(dsths, hsths, NUMTRIALS * sizeof(float), cudaMemcpyHostToDevice);
    CudaCheckError();
    cudaMemcpy(dhalflens, hhalflens, NUMTRIALS * sizeof(float), cudaMemcpyHostToDevice);
    CudaCheckError();

    // setup the execution parameters:
    dim3 threads(BLOCKSIZE, 1, 1);
    dim3 grid(NUMBLOCKS, 1, 1);

    // create and start timer
    cudaDeviceSynchronize();

    // allocate CUDA events that we'll use for timing:
    cudaEvent_t start, stop;
    cudaEventCreate(&start);
    CudaCheckError();
    cudaEventCreate(&stop);
    CudaCheckError();

    // record the start event:
    cudaEventRecord(start, NULL);
    CudaCheckError();

    // execute the kernel:
    MonteCarlo <<< grid, threads >>> (dtxs, dtys, dtxvs, dsvs, dsths, dhalflens, dhits);

    // record the stop event:
    cudaEventRecord(stop, NULL);
    CudaCheckError();

    // wait for the stop event to complete:
    cudaEventSynchronize(stop);
    CudaCheckError();

    float msecTotal = 0.0f;
    cudaEventElapsedTime(&msecTotal, start, stop);
    CudaCheckError();

    // copy result from the device to the host:
    cudaMemcpy(hhits, dhits, NUMTRIALS * sizeof(int), cudaMemcpyDeviceToHost);
    CudaCheckError();

    // compute the sum:
    int numHits = 0;
    for (int i = 0; i < NUMTRIALS; i++) {
        numHits += hhits[i];
    }

    float probability = 100.f * (float)numHits / (float)NUMTRIALS;

    // compute and print:
    double secondsTotal = 0.001 * (double)msecTotal;
    double trialsPerSecond = (float)NUMTRIALS / secondsTotal;
    double megaTrialsPerSecond = trialsPerSecond / 1000000.;
    fprintf(stderr, "Number of Trials = %10d, Blocksize = %8d, MegaTrials/Second = %10.4lf, Probability = %6.2f%%\n",
        NUMTRIALS, BLOCKSIZE, megaTrialsPerSecond, probability);

    // clean up memory:
    delete[] htxs;
    delete[] htys;
    delete[] htxvs;
    delete[] hsvs;
    delete[] hsths;
    delete[] hhits;

    cudaFree(dtxs);
    CudaCheckError();
    cudaFree(dtys);
    CudaCheckError();
    cudaFree(dtxvs);
    CudaCheckError();
    cudaFree(dsvs);
    CudaCheckError();
    cudaFree(dsths);
    CudaCheckError();
    cudaFree(dhits);
    CudaCheckError();

    return 0;
}
