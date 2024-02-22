#if !defined(tK)
#error "tK is undefined!  This should be defined as the K dimension of the matrix tiles, which is dependent on the elemement type, likely 16 or 32."
#endif

#if !defined(MM)
#error "MM is undefined!  This should be defined as the number of matrix tiles in the M dimension."
#endif

#if !defined(NN)
#error "NN is undefined!  This should be defined as the number of matrix tiles in the N dimension."
#endif

#if !defined(KK)
#define KK 1
#endif

#if !defined(cl_intel_split_work_group_barrier) || defined(NO_SPLIT_BARRIERS)
#if !defined(cl_intel_split_work_group_barrier)
#warning "Unexpected: cl_intel_split_work_group_barrier is not supported?"
#endif
#define split_barrier_arrive()
#define split_barrier_wait()
#else
#define split_barrier_arrive()  intel_work_group_barrier_arrive(0)
#define split_barrier_wait()    intel_work_group_barrier_wait(0)
#endif

#define MM_KERNEL_NAMEX(PREFIX, tM, tN, MM, NN) PREFIX ## _m ## tM ## _n ## tN ## _ ## MM ## x ## NN
#define MM_KERNEL_NAME(PREFIX, tM, tN, MM, NN)  MM_KERNEL_NAMEX(PREFIX, tM, tN, MM, NN)

#if !defined(SGS_PER_WG)
// Launch four subgroups per work-group, to maximize cache reuse.
#define SGS_PER_WG 4
#endif

__attribute__((intel_reqd_sub_group_size(16))) __attribute__((reqd_work_group_size(16, SGS_PER_WG, 1)))
kernel void MM_KERNEL_NAME(tf32_dpas_rowmajor_tiled, 8, 16, MM, NN)(global float* C, global float* A, global float* B, int K)
{
    const int tM = 8;
    const int tN = 16;
    const int N = get_global_size(0) * NN;
    const int m = compute_m(SGS_PER_WG, tM, MM);
    const int n = get_group_id(0) * tN * NN;

#if 0
    // Initial prefetch:
    const int init_k = 0;
    for (int kk = 0; kk < KK; kk+=2) {
        for (int mm = 0; mm < MM; mm+=2) {
            prefetch_a_rowmajor_d16_m8v2_k16v2_sg16(A, m + mm * tM, init_k + kk * tK, K);
        }
    }
    for (int kk = 0; kk < KK; kk++) {
        for (int nn = 0; nn < NN; nn+=2) {
            prefetch_b_rowmajor_d16_k16_n16v2_sg16(B, init_k + kk * tK, n + nn * tN, N);
        }
    }
#endif

    float8 sum[MM][NN];
    for (int mm = 0; mm < MM; mm++) {
        for (int nn = 0; nn < NN; nn++) {
            sum[mm][nn] = 0;
        }
    }

    split_barrier_arrive();

    for (int k = 0; k < K; k += tK * KK) {
#if 0
        // Next prefetch:
        const int next_k = k + tK * KK;
        for (int kk = 0; kk < KK; kk+=2) {
            for (int mm = 0; mm < MM; mm+=2) {
                prefetch_a_rowmajor_d16_m8v2_k16v2_sg16(A, m + mm * tM, next_k + kk * tK, K);
            }
        }
        for (int kk = 0; kk < KK; kk++) {
            for (int nn = 0; nn < NN; nn+=2) {
                prefetch_b_rowmajor_d16_k16_n16v2_sg16(B, next_k + kk * tK, n + nn * tN, N);
            }
        }
#endif

        float4  aData[KK][MM];
#if 0
        if (KK % 2 == 0) {
            for (int kk = 0; kk < KK; kk+=2) {
                for (int mm = 0; mm < MM; mm++) {
                    short16 aTemp = load_a_rowmajor_d32_m8_k8v2_sg16(A, m + mm * tM, k + kk * tK, K);
                    aData[kk + 0][mm] = aTemp.lo;
                    aData[kk + 1][mm] = aTemp.hi;
                }
            }
        } else {
#endif
            for (int kk = 0; kk < KK; kk++) {
                for (int mm = 0; mm < MM; mm++) {
                    aData[kk][mm] = load_a_rowmajor_d32_m8_k8_sg16(A, m + mm * tM, k + kk * tK, K);
                }
            }
#if 0
        }
#endif

        float8  bData[KK][NN];
        for (int kk = 0; kk < KK; kk++) {
            for (int nn = 0; nn < NN; nn++) {
                bData[kk][nn] = load_b_rowmajor_d32_k8_nx(B, k + kk * tK, n + nn * tN, N);
            }
        }

        for (int kk = 0; kk < KK; kk++) {
            for (int nn = 0; nn < NN; nn++) {
                for (int mm = 0; mm < MM; mm++) {
                    sum[mm][nn] = mat_mul_sg16(aData[kk][mm], bData[kk][nn], sum[mm][nn]);
                }
            }
        }

        split_barrier_wait();
        split_barrier_arrive();
    }

    split_barrier_wait();

    for (int mm = 0; mm < MM; mm++) {
        for (int nn = 0; nn < NN; nn++) {
            store_c_rowmajor_fp32_m8_nx(C, sum[mm][nn], m + mm * tM, n + nn * tN, N);
        }
    }
}

#ifdef cl_intel_subgroup_extended_block_read

__attribute__((intel_reqd_sub_group_size(16))) __attribute__((reqd_work_group_size(16, SGS_PER_WG, 1)))
kernel void MM_KERNEL_NAME(tf32_dpas_blockread_rowmajor_tiled, 8, 16, MM, NN)(global float* C, global float* A, global float* B, int K)
{
    const int tM = 8;
    const int tN = 16;
    const int M = get_global_size(1) * tM * MM;
    const int N = get_global_size(0) * NN;
    const int m = compute_m(SGS_PER_WG, tM, MM);
    const int n = get_group_id(0) * tN * NN;

#if 0
    // Initial prefetch:
    const int init_k = 0;
    for (int kk = 0; kk < KK; kk+=2) {
        for (int mm = 0; mm < MM; mm+=2) {
            prefetch_a_rowmajor_d16_m8v2_k16v2_sg16(A, m + mm * tM, init_k + kk * tK, K);
        }
    }
    for (int kk = 0; kk < KK; kk++) {
        for (int nn = 0; nn < NN; nn+=2) {
            prefetch_b_rowmajor_d16_k16_n16v2_sg16(B, init_k + kk * tK, n + nn * tN, N);
        }
    }
#endif

    float8 sum[MM][NN];
    for (int mm = 0; mm < MM; mm++) {
        for (int nn = 0; nn < NN; nn++) {
            sum[mm][nn] = 0;
        }
    }

    split_barrier_arrive();

    for (int k = 0; k < K; k += tK * KK) {
#if 0
        // Next prefetch:
        const int next_k = k + tK * KK;
        for (int kk = 0; kk < KK; kk+=2) {
            for (int mm = 0; mm < MM; mm+=2) {
                prefetch_a_rowmajor_d16_m8v2_k16v2_sg16(A, m + mm * tM, next_k + kk * tK, K);
            }
        }
        for (int kk = 0; kk < KK; kk++) {
            for (int nn = 0; nn < NN; nn+=2) {
                prefetch_b_rowmajor_d16_k16_n16v2_sg16(B, next_k + kk * tK, n + nn * tN, N);
            }
        }
#endif

        float4  aData[KK][MM];
#if 0
        if (KK % 2 == 0) {
            for (int kk = 0; kk < KK; kk+=2) {
                for (int mm = 0; mm < MM; mm++) {
                    short16 aTemp = as_short16(intel_subgroup_block_read_u16_m8k16v2(A, K * sizeof(ushort), M, K * sizeof(ushort), (int2)(k + kk * tK, m + mm * tM)));
                    aData[kk + 0][mm] = aTemp.lo;
                    aData[kk + 1][mm] = aTemp.hi;
                }
            }
        } else {
#endif
            for (int kk = 0; kk < KK; kk++) {
                for (int mm = 0; mm < MM; mm++) {
                    //aData[kk][mm] = as_float8(intel_subgroup_block_read_u32_m8k16(A, K * sizeof(float), M, K * sizeof(float), (int2)(k + kk * tK, m + mm * tM))); // works
                    //aData[kk][mm] = as_float8(intel_subgroup_block_read_u32_m8k8(A, K * sizeof(float), M, K * sizeof(float), (int2)(k + kk * tK, m + mm * tM))); // doesn't work
                    aData[kk][mm] = as_float4(intel_subgroup_block_read_u32_m8k8(A, K * sizeof(float), M, K * sizeof(float), (int2)(k + kk * tK, m + mm * tM)));
                    //float8 good = load_a_rowmajor_d32_m8_k8v2_sg16(A, m + mm * tM, k + kk * tK, K);
                    //printf("sglid = %u: test = %v8f, good= %v8f\n", get_sub_group_local_id(), aData[kk][mm], good);
                }
            }
#if 0
        }
#endif

        float8  bData[KK][NN];
        for (int kk = 0; kk < KK; kk++) {
            for (int nn = 0; nn < NN; nn++) {
                bData[kk][nn] = as_float8(intel_subgroup_block_read_u32_m8k16(B, N * sizeof(float), K, N * sizeof(float), (int2)(n + nn * tN, k + kk * tK)));
            }
        }

        for (int kk = 0; kk < KK; kk++) {
            for (int nn = 0; nn < NN; nn++) {
                for (int mm = 0; mm < MM; mm++) {
                    sum[mm][nn] = mat_mul_sg16(aData[kk][mm], bData[kk][nn], sum[mm][nn]);
                }
            }
        }

        split_barrier_wait();
        split_barrier_arrive();
    }

    split_barrier_wait();

    for (int mm = 0; mm < MM; mm++) {
        for (int nn = 0; nn < NN; nn++) {
            intel_subgroup_block_write_u32_m8k16(C, N * sizeof(float), M, N * sizeof(float), (int2)(n + nn * tN, m + mm * tM), as_uint8(sum[mm][nn]));
        }
    }
}

#endif // cl_intel_subgroup_extended_block_read