#include <stdio.h>
#include <sys/time.h>
#include <cuda.h>
#include "cuPrintf.cu"
#include "cuPrintf.cuh"
#include <cfloat>

//VERSION 1.4 MODIFIED 7/8 13:08 by Jack

// The number of threads per blocks in the kernel
// (if we define it here, then we can use its value in the kernel,
//  for example to statically declare an array in shared memory)
const int threads_per_block = 256;


// Forward function declarations
float GPU_vector_max(float *A, int N, int kernel_code);
float CPU_vector_max(float *A, int N);
float *get_random_vector(int N);
float *get_increasing_vector(int N);
long long start_timer();
long long stop_timer(long long start_time, char *name);
void die(char *message);
void checkError();

int main(int argc, char **argv) {

    //default kernel
    int kernel_code = 1;
    
    // Parse vector length and kernel options
    int N;
    if(argc == 2) {
        N = atoi(argv[1]); // user-specified value
    } else if (argc == 4 && !strcmp(argv[2], "-k")) {
        N = atoi(argv[1]); // user-specified value
        kernel_code = atoi(argv[3]); 
        printf("KERNEL_CODE %d\n", kernel_code);
    } else {
        die("USAGE: ./vector_max <vector_length> -k <kernel_code>");
    }

    // Seed the random generator (use a constant here for repeatable results)
    srand(10);

    // Generate a random vector
    // You can use "get_increasing_vector()" for debugging
    long long vector_start_time = start_timer();
    //float *vec = get_random_vector(N);
    float *vec = get_increasing_vector(N);
    stop_timer(vector_start_time, "Vector generation");
	
    // Compute the max on the GPU
    long long GPU_start_time = start_timer();
    float result_GPU = GPU_vector_max(vec, N, kernel_code);
    long long GPU_time = stop_timer(GPU_start_time, "\t            Total");
	
    // Compute the max on the CPU
    long long CPU_start_time = start_timer();
    float result_CPU = CPU_vector_max(vec, N);
    long long CPU_time = stop_timer(CPU_start_time, "\nCPU");
    
    // Free vector
    free(vec);

    // Compute the speedup or slowdown
    if (GPU_time > CPU_time) printf("\nCPU outperformed GPU by %.2fx\n", (float) GPU_time / (float) CPU_time);
    else                     printf("\nGPU outperformed CPU by %.2fx\n", (float) CPU_time / (float) GPU_time);
	
    // Check the correctness of the GPU results
    int wrong = result_CPU != result_GPU;
	
    // Report the correctness results
    if(wrong) printf("GPU output %f did not match CPU output %f\n", result_GPU, result_CPU);
        
}


// A GPU kernel that computes the maximum value of a vector
// (each lead thread (threadIdx.x == 0) computes a single value
__global__ void vector_max_kernel(float *in, float *out, int N) {

    // Determine the "flattened" block id and thread id
    int block_id = blockIdx.x + gridDim.x * blockIdx.y;
    int thread_id = blockDim.x * block_id + threadIdx.x;
    //cuPrintf("block_id = %d\n", block_id);
    //cuPrintf("thread_id = %d\n", thread_id);
    //cuPrintf("blockIdx.x = %d\n", blockIdx.x);
    //cuPrintf("blockIdx.y = %d\n", blockIdx.y);
    cuPrintf("threadIdx.x = %d\n", threadIdx.x);
    //cuPrintf("threadIdx.y = %d\n", threadIdx.y);

    // A single "lead" thread in each block finds the maximum value over a range of size threads_per_block
    float max = 0.0;
    if (threadIdx.x == 0) {

        //calculate out of bounds guard
        //our block size will be 256, but our vector may not be a multiple of 256!
        int end = threads_per_block;
        if(thread_id + threads_per_block > N)
            end = N - thread_id;

        //grab the lead thread's value
        max = in[thread_id];

        //grab values from all other threads' locations
        for(int i = 1; i < end; i++) {
                
            //if larger, replace
            if(max < in[thread_id + i])
                max = in[thread_id + i];
        }

        out[block_id] = max;

    }
}



__global__ void vector_max_kernel2(float *in, float *out, int N) {

    // Determine the "flattened" block id and thread id
    int block_id = blockIdx.x + gridDim.x * blockIdx.y;
    int thread_id = blockDim.x * block_id + threadIdx.x;
    //cuPrintf("block_id = %d\n", block_id);
    //cuPrintf("thread_id = %d\n", thread_id);
    //cuPrintf("blockIdx.x = %d\n", blockIdx.x);
    //cuPrintf("blockIdx.y = %d\n", blockIdx.y);
    cuPrintf("threadIdx.x = %d\n", threadIdx.x);
    //cuPrintf("threadIdx.y = %d\n", threadIdx.y);

	_shared_ int sharemem[N];
        sharemem = in; 

    // A single "lead" thread in each block finds the maximum value over a range of size threads_per_block
    float max = 0.0;
    if (threadIdx.x == 0) {

        //calculate out of bounds guard
        //our block size will be 256, but our vector may not be a multiple of 256!
        int end = threads_per_block;
        if(thread_id + threads_per_block > N)
            end = N - thread_id;

        //grab the lead thread's value
        max = sharemem[thread_id];

        //grab values from all other threads' locations
        for(int i = 1; i < end; i++) {

            //if larger, replace
            if(max < thread_id + i])
                max = [thread_id + i];
        }

        out[block_id] = max;

    }





// Returns the maximum value within a vector of length N
float GPU_vector_max(float *in_CPU, int N, int kernel_code) {

    int vector_size = N * sizeof(float);

    // Allocate CPU memory for the result
    float *out_CPU = (float *) malloc(vector_size);
    if (out_CPU == NULL) die("Error allocating CPU memory");

    // Allocate GPU memory for the inputs and the result
    long long memory_start_time = start_timer();

    float *in_GPU, *out_GPU;
    if (cudaMalloc((void **) &in_GPU, vector_size) != cudaSuccess) die("Error allocating GPU memory");
    if (cudaMalloc((void **) &out_GPU, vector_size) != cudaSuccess) die("Error allocating GPU memory");
	
    // Transfer the input vectors to GPU memory
    cudaMemcpy(in_GPU, in_CPU, vector_size, cudaMemcpyHostToDevice);
    cudaDeviceSynchronize();  // this is only needed for timing purposes
    stop_timer(memory_start_time, "\nGPU:\t  Transfer to GPU");
	
    // Determine the number of thread blocks in the x- and y-dimension
    int num_blocks = (int) ((float) (N + threads_per_block - 1) / (float) threads_per_block);
    int max_blocks_per_dimension = 65535;
    int num_blocks_y = (int) ((float) (num_blocks + max_blocks_per_dimension - 1) / (float) max_blocks_per_dimension);
    int num_blocks_x = (int) ((float) (num_blocks + num_blocks_y - 1) / (float) num_blocks_y);
    dim3 grid_size(num_blocks_x, num_blocks_y, 1);
    printf("num_blocks: %d\n", num_blocks);
    printf("num_blocks_y: %d\n", num_blocks_y);
    printf("num_blocks_x: %d\n", num_blocks_x);
	
    // Execute the kernel to compute the vector sum on the GPU
    long long kernel_start_time;
    kernel_start_time = start_timer();

    switch(kernel_code){
    case 1 : 
        cudaPrintfInit();
        vector_max_kernel <<< grid_size , threads_per_block >>> (in_GPU, out_GPU, N);
    	cudaPrintfDisplay(stdout,true);
    	cudaPrintfEnd();
        
        break;
    case 2 :
        //LAUNCH KERNEL FROM PROBLEM 2 HERE
        die("KERNEL NOT IMPLEMENTED YET\n");
        break;
    case 3 :
        //LAUNCH KERNEL FROM PROBLEM 3 HERE
        die("KERNEL NOT IMPLEMENTED YET\n");
        break;
    case 4 :
        //LAUNCH KERNEL FROM PROBLEM 4 HERE
        die("KERNEL NOT IMPLEMENTED YET\n");
        break;
    default :
        die("INVALID KERNEL CODE\n");
    }
    
    cudaDeviceSynchronize();  // this is only needed for timing purposes
    stop_timer(kernel_start_time, "\t Kernel execution");
    
    checkError();
    
    // Transfer the result from the GPU to the CPU
    memory_start_time = start_timer();
    
    //copy C back
    cudaMemcpy(out_CPU, out_GPU, vector_size, cudaMemcpyDeviceToHost);
    checkError();
    cudaDeviceSynchronize();  // this is only needed for timing purposes
    stop_timer(memory_start_time, "\tTransfer from GPU");
    			    
    // Free the GPU memory
    cudaFree(in_GPU);
    cudaFree(out_GPU);

    float max = out_CPU[0];
    free(out_CPU);

    //return a single statistic
    return max;
}


// Returns the maximum value within a vector of length N
float CPU_vector_max(float *vec, int N) {	

    // find the max
    float max;
    max = vec[0];
    for (int i = 1; i < N; i++) {
        if(max < vec[i]) {
            max = vec[i];
        }
    }
	
    // Return a single statistic
    return max;
}


// Returns a randomized vector containing N elements
float *get_random_vector(int N) {
    if (N < 1) die("Number of elements must be greater than zero");
	
    // Allocate memory for the vector
    float *V = (float *) malloc(N * sizeof(float));
    if (V == NULL) die("Error allocating CPU memory");
	
    // Populate the vector with random numbers
    for (int i = 0; i < N; i++) V[i] = (float) rand() / (float) rand();
	
    // Return the randomized vector
    return V;
}

float *get_increasing_vector(int N) {
    if (N < 1) die("Number of elements must be greater than zero");
	
    // Allocate memory for the vector
    float *V = (float *) malloc(N * sizeof(float));
    if (V == NULL) die("Error allocating CPU memory");
	
    // Populate the vector with random numbers
    for (int i = 0; i < N; i++) V[i] = (float) i;
	
    // Return the randomized vector
    return V;
}

void checkError() {
    // Check for kernel errors
    cudaError_t error = cudaGetLastError();
    if (error) {
        char message[256];
        sprintf(message, "CUDA error: %s", cudaGetErrorString(error));
        die(message);
    }
}

// Returns the current time in microseconds
long long start_timer() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000000 + tv.tv_usec;
}


// Prints the time elapsed since the specified time
long long stop_timer(long long start_time, char *name) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    long long end_time = tv.tv_sec * 1000000 + tv.tv_usec;
    printf("%s: %.5f sec\n", name, ((float) (end_time - start_time)) / (1000 * 1000));
    return end_time - start_time;
}


// Prints the specified message and quits
void die(char *message) {
    printf("%s\n", message);
    exit(1);
}
