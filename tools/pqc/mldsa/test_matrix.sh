#!/bin/bash
#
# Builds the ISA/implementation variant matrix and, unless RUN=0, runs each
# variant under Spike (needs pk). RUN=0 just leaves the binaries next to the
# Makefile for copying to a board.

make obj-clean
make VK_KECCAK=0 MLDSA_RVV=0 RVKISA=rv64gc
cp xmldsa xmldsa.rv64gc
[ "${RUN:-1}" = 0 ] || make run | tee xmldsa.rv64gc.log

make obj-clean
make VK_KECCAK=0 MLDSA_RVV=0 RVKISA=rv64gc_zbb
cp xmldsa xmldsa.rv64gc_zbb
[ "${RUN:-1}" = 0 ] || make run | tee xmldsa.rv64gc_zbb.log

make obj-clean
make VK_KECCAK=0 MLDSA_RVV=0 RVKISA=rv64gcv
cp xmldsa xmldsa.rv64gcv
[ "${RUN:-1}" = 0 ] || make run | tee xmldsa.rv64gcv.log

make obj-clean
make VK_KECCAK=0 MLDSA_RVV=0 RVKISA=rv64gcv_zbb
cp xmldsa xmldsa.rv64gcv_zbb
[ "${RUN:-1}" = 0 ] || make run | tee xmldsa.rv64gcv_zbb.log

make obj-clean
make VK_KECCAK=0 MLDSA_RVV=1 RVKISA=rv64gcv_zbb
cp xmldsa xmldsa.rv64gcv_intr_zbb
[ "${RUN:-1}" = 0 ] || make run | tee xmldsa.rv64gcv_intr_zbb.log

make obj-clean
make VK_KECCAK=1 MLDSA_RVV=0 RVKISA=rv64gcv
cp xmldsa xmldsa.rv64gcv_vkec
[ "${RUN:-1}" = 0 ] || make run | tee xmldsa.rv64gcv_vkec.log

make obj-clean
make VK_KECCAK=1 MLDSA_RVV=1 RVKISA=rv64gcv
cp xmldsa xmldsa.rv64gcv_intr_vkec
[ "${RUN:-1}" = 0 ] || make run | tee xmldsa.rv64gcv_intr_vkec.log
