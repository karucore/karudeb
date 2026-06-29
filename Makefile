.PHONY: help clean pqc-clean distclean kernel-qemu karu-opensbi karu64-rv64imac-dtb karu64-rv64gc-linux karu64-zvk-linux karu64-rv64gc-dtb karu64-zvk-dtb karu64-rv64gc-tftp karu64-zvk-tftp karu-rv64imac-check karu-rv64imac-image karu-rv64imac-tftp test-vnc test-vnc-stop test-vnc-status

PQC_DIRS := tools/pqc/mlkem tools/pqc/mldsa

.DEFAULT_GOAL := help

help:
	@printf '%s\n' 'Targets:'
	@printf '  %-12s %s\n' clean 'remove local caches, PQC outputs, and QEMU logs'
	@printf '  %-12s %s\n' distclean 'remove build/ as well'
	@printf '  %-12s %s\n' kernel-qemu 'fetch/build Linux 7.1.2 QEMU kernel'
	@printf '  %-12s %s\n' karu-opensbi 'build generic karu64 OpenSBI fw_jump'
	@printf '  %-12s %s\n' karu64-rv64imac-dtb 'build reduced RV64IMAC ROM control DTB'
	@printf '  %-12s %s\n' karu64-rv64gc-linux 'build scalar RV64GC NFS-root kernel'
	@printf '  %-12s %s\n' karu64-zvk-linux 'build RVA23/Zvk NFS-root kernel'
	@printf '  %-12s %s\n' karu64-rv64gc-tftp 'stage scalar RV64GC NFS netboot files'
	@printf '  %-12s %s\n' karu64-zvk-tftp 'stage RVA23/Zvk NFS netboot files'
	@printf '  %-12s %s\n' karu-rv64imac-check 'check tools for karu64 RV64IMAC soft-float image'
	@printf '  %-12s %s\n' karu-rv64imac-image 'build karu64 Linux+BusyBox soft-float image'
	@printf '  %-12s %s\n' karu-rv64imac-tftp 'stage karu64 soft-float Image/initramfs/DTB for U-Boot'
	@printf '  %-12s %s\n' test-vnc 'build/start the QEMU JWM VNC smoke test'
	@printf '  %-12s %s\n' test-vnc-stop 'stop the QEMU JWM VNC smoke test'
	@printf '  %-12s %s\n' test-vnc-status 'show QEMU JWM VNC smoke test status'

clean: pqc-clean
	find scripts -type d -name '__pycache__' -prune -exec rm -rf {} +
	find scripts -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
	rm -f build/*.log

pqc-clean:
	for dir in $(PQC_DIRS); do $(MAKE) -C $$dir clean; done

distclean: clean
	./scripts/clean-build.sh

kernel-qemu:
	./scripts/build-qemu-linux.sh

karu-opensbi:
	./scripts/build-karu64-opensbi.sh build

karu64-rv64imac-dtb:
	DTB_VARIANT=rv64imac-ddr ./scripts/build-karu64-dtb.sh

karu64-rv64gc-linux:
	OUT_DIR=build/linux-riscv64-karu64-rv64gc \
	FRAGMENT=configs/linux-riscv64-karu64-rv64gc-nfsroot.fragment \
	DEFCONFIG=allnoconfig \
	BUILD_TARGETS=Image \
	./scripts/build-karu64-linux.sh

karu64-zvk-linux:
	OUT_DIR=build/linux-riscv64-karu64-zvk \
	FRAGMENT=configs/linux-riscv64-karu64-zvk-nfsroot.fragment \
	DEFCONFIG=allnoconfig \
	BUILD_TARGETS=Image \
	./scripts/build-karu64-linux.sh

karu64-rv64gc-dtb:
	DTB_VARIANT=rv64gc-ddr ./scripts/build-karu64-dtb.sh

karu64-zvk-dtb:
	DTB_VARIANT=zvk-ddr ./scripts/build-karu64-dtb.sh

karu64-rv64gc-tftp: karu64-rv64gc-linux karu64-rv64gc-dtb
	DTB_VARIANT=rv64gc-ddr ./scripts/stage-karu64-tftp.sh

karu64-zvk-tftp: karu64-zvk-linux karu64-zvk-dtb
	DTB_VARIANT=zvk-ddr ./scripts/stage-karu64-tftp.sh

karu-rv64imac-check:
	./scripts/build-karu64-rv64imac-image.sh check

karu-rv64imac-image:
	./scripts/build-karu64-rv64imac-image.sh all

karu-rv64imac-tftp:
	./scripts/build-karu64-rv64imac-image.sh stage-tftp

test-vnc:
	./scripts/test-qemu-vnc.sh start

test-vnc-stop:
	./scripts/test-qemu-vnc.sh stop

test-vnc-status:
	./scripts/test-qemu-vnc.sh status
