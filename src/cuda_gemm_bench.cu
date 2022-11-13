#include <chrono>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <tuple>
#include <vector>

#include <cublas_v2.h>
#include <cuda.h>
#include <curand.h>

#include "tensor.h"

#ifndef PAD_KERNELS
#define PAD_KERNELS 1
#endif

// Vector saves m, n, k, a_t, b_t
std::vector<std::tuple<int, int, int, bool, bool>> inference_server_set = {
    std::make_tuple(5124, 700, 2048, false, false),
    std::make_tuple(35, 700, 2048, false, false),
    std::make_tuple(5124, 700, 2560, false, false),
    std::make_tuple(35, 700, 2560, false, false),
    std::make_tuple(5124, 1500, 2048, false, false),
    std::make_tuple(35, 1500, 2048, false, false),
    std::make_tuple(5124, 1500, 2560, false, false),
    std::make_tuple(35, 1500, 2560, false, false),
    std::make_tuple(7680, 1, 2560, false, false),
    std::make_tuple(7680, 2, 2560, false, false),
    std::make_tuple(7680, 4, 2560, false, false),
    std::make_tuple(3072, 1, 1024, false, false),
    std::make_tuple(3072, 2, 1024, false, false),
    std::make_tuple(3072, 4, 1024, false, false),
    std::make_tuple(512, 1, 500000, false, false),
    std::make_tuple(1024, 1, 500000, false, false),
    std::make_tuple(512, 2, 500000, false, false),
    std::make_tuple(1024, 2, 500000, false, false),
    std::make_tuple(512, 4, 500000, false, false),
    std::make_tuple(1024, 4, 500000, false, false),
    std::make_tuple(1024, 700, 512, false, false),
    std::make_tuple(7680, 1500, 2560, false, false),
    std::make_tuple(6144, 1500, 2048, false, false),
    std::make_tuple(4608, 1500, 1536, false, false),
    std::make_tuple(8448, 1500, 2816, false, false),
    std::make_tuple(3072, 1500, 1024, false, false),
    std::make_tuple(7680, 3000, 2560, false, false),
    std::make_tuple(6144, 3000, 2048, false, false),
    std::make_tuple(4608, 3000, 1536, false, false),
    std::make_tuple(8448, 3000, 2816, false, false),
    std::make_tuple(3072, 3000, 1024, false, false),
    std::make_tuple(7680, 6000, 2560, false, false),
    std::make_tuple(6144, 6000, 2048, false, false),
    std::make_tuple(4608, 6000, 1536, false, false),
    std::make_tuple(8448, 6000, 2816, false, false),
    std::make_tuple(3072, 6000, 1024, false, false),
    std::make_tuple(6144, 1, 2048, false, false),
    std::make_tuple(4608, 1, 1536, false, false),
    std::make_tuple(8448, 1, 2816, false, false),
    std::make_tuple(6144, 2, 2048, false, false),
    std::make_tuple(4608, 2, 1536, false, false),
    std::make_tuple(8448, 2, 2816, false, false),
    std::make_tuple(6144, 4, 2048, false, false),
    std::make_tuple(4608, 4, 1536, false, false),
    std::make_tuple(8448, 4, 2816, false, false),
    std::make_tuple(512, 1500, 2816, false, false),
    std::make_tuple(512, 1500, 2048, false, false),
    std::make_tuple(512, 1500, 2560, false, false),
    std::make_tuple(512, 1500, 1536, false, false),
    std::make_tuple(1024, 1500, 2816, false, false),
    std::make_tuple(1024, 1500, 2048, false, false),
    std::make_tuple(1024, 1500, 2560, false, false),
    std::make_tuple(1024, 1500, 1536, false, false),
    std::make_tuple(512, 1, 512, false, false),
    std::make_tuple(1024, 1, 512, false, false),
    std::make_tuple(512, 3000, 2816, false, false),
    std::make_tuple(512, 3000, 2048, false, false),
    std::make_tuple(512, 3000, 2560, false, false),
    std::make_tuple(512, 3000, 1536, false, false),
    std::make_tuple(1024, 3000, 2816, false, false),
    std::make_tuple(1024, 3000, 2048, false, false),
    std::make_tuple(1024, 3000, 2560, false, false),
    std::make_tuple(1024, 3000, 1536, false, false),
    std::make_tuple(512, 2, 512, false, false),
    std::make_tuple(1024, 2, 512, false, false),
    std::make_tuple(512, 6000, 2816, false, false),
    std::make_tuple(512, 6000, 2048, false, false),
    std::make_tuple(512, 6000, 2560, false, false),
    std::make_tuple(512, 6000, 1536, false, false),
    std::make_tuple(1024, 6000, 2816, false, false),
    std::make_tuple(1024, 6000, 2048, false, false),
    std::make_tuple(1024, 6000, 2560, false, false),
    std::make_tuple(1024, 6000, 1536, false, false),
    std::make_tuple(512, 4, 512, false, false),
    std::make_tuple(1024, 4, 512, false, false)};

/*
Usage:

The default precision is set based on the architecture and mode.

By default, the program runs the benchmark in training mode.

bin/gemm_bench

To run inference mode, use the following command:

bin/gemm_bench inference


To change the precision for training/inference, use:

bin/gemm_bench train <precision>
bin/gemm_bench inference <precision>

Supported precision types:

For Maxwell GPUS:
float for training and inference

For Pascal GPUS:
float, half for training
float, half, int8 for inference

*/

template <typename T1, typename T2>
int time_gemm(Tensor<T1> A, Tensor<T1> B, Tensor<T2> C, bool a_t, bool b_t,
              cublasHandle_t cublas_handle, bool use_tensor_core)
{
    const int alpha = 1.f;
    const int beta = 1.f;

    int m = C.dims()[0];
    int k = a_t ? A.dims()[0] : A.dims()[1];
    int n = C.dims()[1];

    int numRepeats = 6;
    cublasStatus_t stat;

    cudaDataType_t A_type = CUDA_R_32F;
    cudaDataType_t B_type = CUDA_R_32F;
    cudaDataType_t C_type = CUDA_R_32F;
    cudaDataType_t compute_type = CUDA_R_32F;
    cublasGemmAlgo_t algo;

    if (std::is_same<T1, uint16_t>::value)
    {
        A_type = CUDA_R_16F;
        B_type = CUDA_R_16F;
        C_type = CUDA_R_16F;
        compute_type = CUDA_R_16F;
    }

    if (std::is_same<T1, uint8_t>::value)
    {
        A_type = CUDA_R_8I;
        B_type = CUDA_R_8I;
        C_type = CUDA_R_32I;
        compute_type = CUDA_R_32I;
    }

    algo = use_tensor_core ? CUBLAS_GEMM_DFALT_TENSOR_OP : CUBLAS_GEMM_DFALT;

    stat =
        cublasGemmEx(cublas_handle, a_t ? CUBLAS_OP_T : CUBLAS_OP_N,
                     b_t ? CUBLAS_OP_T : CUBLAS_OP_N, m, n, k, &alpha, A.begin(),
                     A_type, A.dims()[0], B.begin(), B_type, B.dims()[0], &beta,
                     C.begin(), C_type, C.dims()[0], compute_type, algo);

    if (stat != CUBLAS_STATUS_SUCCESS)
    {
        throw std::runtime_error("sgemm failed");
    }

    cudaDeviceSynchronize();

    auto start = std::chrono::steady_clock::now();

    for (int i = 0; i < numRepeats; ++i)
    {
        stat = cublasGemmEx(cublas_handle, a_t ? CUBLAS_OP_T : CUBLAS_OP_N,
                            b_t ? CUBLAS_OP_T : CUBLAS_OP_N, m, n, k, &alpha,
                            A.begin(), A_type, A.dims()[0], B.begin(), B_type,
                            B.dims()[0], &beta, C.begin(), C_type, C.dims()[0],
                            compute_type, algo);

        if (stat != CUBLAS_STATUS_SUCCESS)
        {
            throw std::runtime_error("sgemm failed");
        }
    }
    cudaDeviceSynchronize();

    auto end = std::chrono::steady_clock::now();

    return static_cast<int>(
        std::chrono::duration<double, std::micro>(end - start).count() /
        numRepeats);
}

int main(int argc, char **argv)
{
    // Get Device Number
    int deviceCount = 0;
    cudaError_t error_id = cudaGetDeviceCount(&deviceCount);

    if (error_id != cudaSuccess)
    {
        printf("cudaGetDeviceCount returned %d\n-> %s\n",
               static_cast<int>(error_id), cudaGetErrorString(error_id));
        printf("Result = FAIL\n");
        exit(EXIT_FAILURE);
    }

    int inference = 1;
    if (argc > 1)
    {
        std::string inf = "inference";
        inference = argv[1] == inf ? 1 : 0;
    }

    if (inference)
    {
        std::cout << "Running inference benchmark " << std::endl;
    }
    else
    {
        std::cout << "Running training benchmark " << std::endl;
    }

    for (int dev = 0; dev < deviceCount; ++dev)
    {
        cudaSetDevice(dev);
        cudaDeviceProp deviceProp;
        cudaGetDeviceProperties(&deviceProp, dev);

        std::cout << "Device " << dev << ": " << deviceProp.name << std::endl;

        curandGenerator_t curand_gen;
        curandCreateGenerator(&curand_gen, CURAND_RNG_PSEUDO_DEFAULT);
        curandSetPseudoRandomGeneratorSeed(curand_gen, 123ULL);

        cublasHandle_t cublas_handle;
        cublasStatus_t status = cublasCreate(&cublas_handle);
        if (status != CUBLAS_STATUS_SUCCESS)
        {
            std::cout << "CUBLAS init failed" << std::endl;
        }

        std::cout << "m\tn\tk\ta_t\tb_t\tfp32 perf\tfp16 perf\tint8 perf\tfp16 tensor core perf\tint8 tensor core perf" << std::endl;

        int pad_kernels_count = 0;

        for (const auto &problem : inference_server_set)
        {
            int m, n, k;
            bool a_t, b_t;
            std::tie(m, n, k, a_t, b_t) = problem;
            int time_ms;

            double flops = (double)m * n * k * 2;
            double perf = 0.f;

            std::cout << m << "\t";
            std::cout << n << "\t";
            std::cout << k << "\t";
            std::cout << "n" << "\t";
            std::cout << "n";

            // set cublas to not use tensor core
            status = cublasSetMathMode(cublas_handle, CUBLAS_DEFAULT_MATH);
            if (status != CUBLAS_STATUS_SUCCESS)
            {
                std::cout << "CUBLAS math mode failed" << std::endl;
            }

            // fp32 benchmark
            {
                auto a = rand<float>({a_t ? k : m, a_t ? m : k}, curand_gen);
                auto b = rand<float>({b_t ? n : k, b_t ? k : n}, curand_gen);
                auto c = zeros<float>({m, n});
                time_ms = time_gemm<float, float>(a, b, c, a_t, b_t, cublas_handle, false);
                perf = flops / (time_ms * 1000.0);
                std::cout << "  " << std::setprecision(6) << perf;
            }

            // fp16 benchmark
            {
                auto a = rand<uint16_t>({a_t ? k : m, a_t ? m : k}, curand_gen);
                auto b = rand<uint16_t>({b_t ? n : k, b_t ? k : n}, curand_gen);
                auto c = zeros<uint16_t>({m, n});
                time_ms = time_gemm<uint16_t, uint16_t>(a, b, c, a_t, b_t, cublas_handle, false);
                perf = flops / (time_ms * 1000.0);
                std::cout << "  " << std::setprecision(6) << perf;
            }

            // int8 benchmark
            {
                int pad_m;
                pad_m = m;
                if (pad_m % 4)
                {
                    pad_kernels_count++;
                    pad_dim(pad_m, 4);
                }

                auto a = rand<uint8_t>({a_t ? k : pad_m, a_t ? pad_m : k}, curand_gen);
                auto b = rand<uint8_t>({b_t ? n : k, b_t ? k : n}, curand_gen);
                auto c = zeros<int>({pad_m, n});
                time_ms = time_gemm<uint8_t, int>(a, b, c, a_t, b_t, cublas_handle, false);
                perf = flops / (time_ms * 1000.0);
                std::cout << "  " << std::setprecision(6) << perf;
            }

            // set cublas to use tensor core
            status = cublasSetMathMode(cublas_handle, CUBLAS_TENSOR_OP_MATH);
            if (status != CUBLAS_STATUS_SUCCESS)
            {
                std::cout << "CUBLAS math mode failed" << std::endl;
            }

            // fp16 tensor core benchmark
            {
                auto a = rand<uint16_t>({a_t ? k : m, a_t ? m : k}, curand_gen);
                auto b = rand<uint16_t>({b_t ? n : k, b_t ? k : n}, curand_gen);
                auto c = zeros<uint16_t>({m, n});
                time_ms = time_gemm<uint16_t, uint16_t>(a, b, c, a_t, b_t, cublas_handle, true);
                perf = flops / (time_ms * 1000.0);
                std::cout << "  " << std::setprecision(6) << perf;
            }

            // int8 tensor core benchmark
            {
                int pad_m;
                pad_m = m;
                if (pad_m % 4)
                {
                    pad_kernels_count++;
                    pad_dim(pad_m, 4);
                }

                auto a = rand<uint8_t>({a_t ? k : pad_m, a_t ? pad_m : k}, curand_gen);
                auto b = rand<uint8_t>({b_t ? n : k, b_t ? k : n}, curand_gen);
                auto c = zeros<int>({pad_m, n});
                time_ms = time_gemm<uint8_t, int>(a, b, c, a_t, b_t, cublas_handle, true);
                perf = flops / (time_ms * 1000.0);
                std::cout << "  " << std::setprecision(6) << perf;
            }

            // std::stringstream ss;
            // ss << "Unsupported precision requested. Precision: " << precision << "
            // Inference: " << inference;

            std::cout << std::endl;
        }

        cublasDestroy(cublas_handle);
        curandDestroyGenerator(curand_gen);
    }

    return 0;
}
