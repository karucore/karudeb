#1/bin/bash

make obj-clean
make VK_KECCAK=0 MLKEM_RVV=0 RVKISA=rv64gc
cp xmlkem xmlkem.rv64gc
make run | tee xmlkem.rv64gc.log

make obj-clean
make VK_KECCAK=0 MLKEM_RVV=0 RVKISA=rv64gc_zbb
cp xmlkem xmlkem.rv64gc_zbb
make run | tee xmlkem.rv64gc_zbb.log

make obj-clean
make VK_KECCAK=0 MLKEM_RVV=0 RVKISA=rv64gcv
cp xmlkem xmlkem.rv64gcv
make run | tee xmlkem.rv64gcv.log

make obj-clean
make VK_KECCAK=0 MLKEM_RVV=0 RVKISA=rv64gcv_zbb
cp xmlkem xmlkem.rv64gcv_zbb
make run | tee xmlkem.rv64gcv_zbb.log

make obj-clean
make VK_KECCAK=0 MLKEM_RVV=1 RVKISA=rv64gcv_zbb
cp xmlkem xmlkem.rv64gcv_intr_zbb
make run | tee xmlkem.rv64gcv_intr_zbb.log

make obj-clean
make VK_KECCAK=1 MLKEM_RVV=0 RVKISA=rv64gcv
cp xmlkem xmlkem.rv64gcv_vkec
make run | tee xmlkem.rv64gcv_vkec.log

make obj-clean
make VK_KECCAK=1 MLKEM_RVV=1 RVKISA=rv64gcv
cp xmlkem xmlkem.rv64gcv_intr_vkec
make run | tee xmlkem.rv64gcv_intr_vkec.log
