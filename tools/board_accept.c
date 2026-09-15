// board_accept.c -- Linux-side acceptance probes for a freshly programmed
// karu64 board: a userspace DDR pattern test and a KVM API smoke test.
//
// Built statically by build-rootfs.sh and installed as
// /usr/local/bin/board_accept; driven by /usr/local/bin/board_accept.sh.
//
//   board_accept mem [MiB]      write/verify three patterns over a MiB-sized
//                               buffer (default 256): address-derived, its
//                               complement, and 0xA5 fill. Reports the first
//                               mismatch. Exit 0 on success.
//   board_accept kvm            open /dev/kvm, read the API version, create a
//                               VM and a vCPU, mmap its run structure. This
//                               exercises the kernel's H-extension setup
//                               (hgatp/hstatus init, hideleg) without a guest
//                               image. Exit 0 if every step succeeds, 2 if
//                               /dev/kvm is absent, 1 on any other failure.

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#ifdef __linux__
#include <linux/kvm.h>
#endif

static int mem_test(size_t mib)
{
	size_t n = mib << 20;
	uint64_t *buf = mmap(NULL, n, PROT_READ | PROT_WRITE,
			     MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);
	size_t words = n / sizeof(uint64_t);
	size_t i, pass;
	const char *names[3] = { "address", "~address", "0xA5 fill" };

	if (buf == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	for (pass = 0; pass < 3; pass++) {
		for (i = 0; i < words; i++) {
			uint64_t v = (uint64_t)(uintptr_t)&buf[i];
			if (pass == 1)
				v = ~v;
			else if (pass == 2)
				v = 0xA5A5A5A5A5A5A5A5ull;
			buf[i] = v;
		}
		for (i = 0; i < words; i++) {
			uint64_t want = (uint64_t)(uintptr_t)&buf[i];
			if (pass == 1)
				want = ~want;
			else if (pass == 2)
				want = 0xA5A5A5A5A5A5A5A5ull;
			if (buf[i] != want) {
				printf("mem: FAIL pattern %s at %p: read %016llx want %016llx\n",
				       names[pass], (void *)&buf[i],
				       (unsigned long long)buf[i],
				       (unsigned long long)want);
				munmap(buf, n);
				return 1;
			}
		}
		printf("mem: ok   %-9s %zu MiB\n", names[pass], mib);
	}
	munmap(buf, n);
	return 0;
}

static int kvm_test(void)
{
#ifndef __linux__
	printf("kvm: skipped (not Linux)\n");
	return 2;
#else
	int kvm, vm, vcpu, ver, mmap_size;
	void *run;

	kvm = open("/dev/kvm", O_RDWR | O_CLOEXEC);
	if (kvm < 0) {
		printf("kvm: /dev/kvm: %s\n", strerror(errno));
		return 2;
	}
	ver = ioctl(kvm, KVM_GET_API_VERSION, 0);
	if (ver != KVM_API_VERSION) {
		printf("kvm: FAIL API version %d (want %d)\n", ver, KVM_API_VERSION);
		return 1;
	}
	printf("kvm: ok   API version %d\n", ver);

	vm = ioctl(kvm, KVM_CREATE_VM, 0);
	if (vm < 0) {
		printf("kvm: FAIL KVM_CREATE_VM: %s\n", strerror(errno));
		return 1;
	}
	printf("kvm: ok   KVM_CREATE_VM\n");

	vcpu = ioctl(vm, KVM_CREATE_VCPU, 0);
	if (vcpu < 0) {
		printf("kvm: FAIL KVM_CREATE_VCPU: %s\n", strerror(errno));
		return 1;
	}
	printf("kvm: ok   KVM_CREATE_VCPU\n");

	mmap_size = ioctl(kvm, KVM_GET_VCPU_MMAP_SIZE, 0);
	if (mmap_size <= 0) {
		printf("kvm: FAIL KVM_GET_VCPU_MMAP_SIZE: %s\n", strerror(errno));
		return 1;
	}
	run = mmap(NULL, (size_t)mmap_size, PROT_READ | PROT_WRITE, MAP_SHARED,
		   vcpu, 0);
	if (run == MAP_FAILED) {
		printf("kvm: FAIL mmap vcpu run: %s\n", strerror(errno));
		return 1;
	}
	printf("kvm: ok   vcpu run area %d bytes\n", mmap_size);
	printf("kvm: ok   (guest execution not exercised; needs a guest image)\n");
	munmap(run, (size_t)mmap_size);
	close(vcpu);
	close(vm);
	close(kvm);
	return 0;
#endif
}

int main(int argc, char **argv)
{
	if (argc >= 2 && strcmp(argv[1], "mem") == 0) {
		size_t mib = 256;
		if (argc >= 3)
			mib = (size_t)strtoul(argv[2], NULL, 10);
		if (mib == 0)
			mib = 256;
		return mem_test(mib);
	}
	if (argc >= 2 && strcmp(argv[1], "kvm") == 0)
		return kvm_test();
	fprintf(stderr, "usage: %s mem [MiB] | kvm\n", argv[0]);
	return 2;
}
