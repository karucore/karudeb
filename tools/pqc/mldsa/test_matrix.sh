#!/bin/bash

make obj-clean
make VK_KECCAK=0 MLDSA_RVV=0 RVKISA=rv64gc
cp xmldsa xmldsa.rv64gc
make run | tee xmldsa.rv64gc.log

make obj-clean
make VK_KECCAK=0 MLDSA_RVV=0 RVKISA=rv64gc_zbb
cp xmldsa xmldsa.rv64gc_zbb
make run | tee xmldsa.rv64gc_zbb.log

make obj-clean
make VK_KECCAK=0 MLDSA_RVV=0 RVKISA=rv64gcv
cp xmldsa xmldsa.rv64gcv
make run | tee xmldsa.rv64gcv.log

make obj-clean
make VK_KECCAK=0 MLDSA_RVV=0 RVKISA=rv64gcv_zbb
cp xmldsa xmldsa.rv64gcv_zbb
make run | tee xmldsa.rv64gcv_zbb.log

make obj-clean
make VK_KECCAK=0 MLDSA_RVV=1 RVKISA=rv64gcv_zbb
cp xmldsa xmldsa.rv64gcv_intr_zbb
make run | tee xmldsa.rv64gcv_intr_zbb.log

make obj-clean
make VK_KECCAK=1 MLDSA_RVV=0 RVKISA=rv64gcv
cp xmldsa xmldsa.rv64gcv_vkec
make run | tee xmldsa.rv64gcv_vkec.log

make obj-clean
make VK_KECCAK=1 MLDSA_RVV=1 RVKISA=rv64gcv
cp xmldsa xmldsa.rv64gcv_intr_vkec
make run | tee xmldsa.rv64gcv_intr_vkec.log
