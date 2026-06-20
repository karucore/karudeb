#include <unistd.h>

static long sys_write(int fd, const void *buf, unsigned long len)
{
	register long a0 asm("a0") = fd;
	register const void *a1 asm("a1") = buf;
	register unsigned long a2 asm("a2") = len;
	register long a7 asm("a7") = 64;
	asm volatile ("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a7) : "memory");
	return a0;
}

static void sys_exit(int code)
{
	register long a0 asm("a0") = code;
	register long a7 asm("a7") = 93;
	asm volatile ("ecall" : : "r"(a0), "r"(a7) : "memory");
	for (;;)
		;
}

void _start(void)
{
	static const char msg[] = "[hello-static] rv64imac/lp64 userspace OK\n";
	sys_write(1, msg, sizeof(msg) - 1);
	sys_exit(0);
}
