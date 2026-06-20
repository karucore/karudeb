// perf_run.c
// RISC-V benchmark helper.
//
// Default mode opens Linux perf events once, then runs a benchmark that uses
// direct rdcycle/rdinstret reads in its measured regions. Those raw CSR reads
// are total counters, not user-only counters.
//
// --user-count runs a child under perf_event_open() with exclude_kernel set and
// prints whole-process user-mode cycle/instruction counts after the child exits.

#include <asm/unistd.h>
#include <errno.h>
#include <linux/perf_event.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static inline uint64_t plat_get_instret(void)
{
	uint64_t r;

	__asm__ volatile("rdinstret %0" : "=r"(r));
	return r;
}

static inline uint64_t rv_get_vlenb(void)
{
	uint64_t r;

	__asm__ volatile("csrr %0, 0xC22" : "=r"(r));
	return r;
}

static inline uint64_t plat_get_cycle(void)
{
	uint64_t cnt;

	__asm__ volatile("rdcycle %0" : "=r"(cnt));
	return cnt;
}

static void hex(const char *lab, const void *dat, size_t len)
{
	size_t i;

	printf("%24s =", lab);
	for (i = 0; i < len; i++)
		printf(" %02X", ((const uint8_t *)dat)[i]);
	printf("\n");
}

static int print_mach(void)
{
	const uint32_t c32 = 0x01020304;
	const uint64_t c64 = 0x0102030405060708;

	hex("0x01020304", &c32, sizeof(c32));
	hex("0x0102030405060708", &c64, sizeof(c64));

	printf("%24s = %d\n", "sizeof(char)", (int)sizeof(char));
	printf("%24s = %d\n", "sizeof(short)", (int)sizeof(short));
	printf("%24s = %d\n", "sizeof(int)", (int)sizeof(int));
	printf("%24s = %d\n", "sizeof(void *)", (int)sizeof(void *));
	printf("%24s = %d\n", "sizeof(long)", (int)sizeof(long));
	printf("%24s = %d\n", "sizeof(long long)", (int)sizeof(long long));
	printf("%24s = %d\n", "sizeof(size_t)", (int)sizeof(size_t));
	printf("%24s = %d\n", "((char) 0xFF)", (int)((char)0xFF));
	printf("%24s = %d\n", "((unsigned char) 0xFF)",
	       (int)((unsigned char)0xFF));

	printf("%24s = %lu\n", "vlen", 8 * rv_get_vlenb());
	printf("%24s = %lu\n", "cycle", plat_get_cycle());
	printf("%24s = %lu\n", "instret", plat_get_instret());

	return 0;
}

static void usage(const char *prog)
{
	fprintf(stderr,
		"Usage:\n"
		"  %s [benchmark [args...]]\n"
		"  %s --user-count [--] benchmark [args...]\n"
		"\n"
		"Default mode keeps raw rdcycle/rdinstret usable across exec.\n"
		"--user-count prints perf_user_cycle/perf_user_instret for the child.\n",
		prog, prog);
}

static int open_hw_event(uint64_t config, pid_t pid, bool disabled,
			 bool user_only)
{
	struct perf_event_attr pe = { 0 };

	pe.type = PERF_TYPE_HARDWARE;
	pe.size = sizeof(pe);
	pe.config = config;
	pe.disabled = disabled ? 1 : 0;
	if (user_only) {
		pe.exclude_kernel = 1;
		pe.exclude_hv = 1;
		pe.exclude_idle = 1;
	}

	return syscall(__NR_perf_event_open, &pe, pid, -1, -1, 0);
}

static int read_u64(int fd, uint64_t *value)
{
	ssize_t got = read(fd, value, sizeof(*value));

	if (got == (ssize_t)sizeof(*value))
		return 0;
	if (got >= 0)
		errno = EIO;
	return -1;
}

static int wait_status_to_exit(int status)
{
	if (WIFEXITED(status))
		return WEXITSTATUS(status);
	if (WIFSIGNALED(status))
		return 128 + WTERMSIG(status);
	return EXIT_FAILURE;
}

static int run_user_count(const char *prog, char **argv, char *envp[])
{
	int sync_pipe[2];
	pid_t child;
	int fd_cycles = -1;
	int fd_instret = -1;
	uint64_t cycles = 0;
	uint64_t instret = 0;
	int status = 0;
	char token = 0;

	if (!argv[0]) {
		usage(prog);
		return EXIT_FAILURE;
	}

	if (pipe(sync_pipe) < 0) {
		perror("pipe");
		return EXIT_FAILURE;
	}

	child = fork();
	if (child < 0) {
		perror("fork");
		close(sync_pipe[0]);
		close(sync_pipe[1]);
		return EXIT_FAILURE;
	}

	if (child == 0) {
		close(sync_pipe[1]);
		if (read(sync_pipe[0], &token, 1) != 1)
			_exit(127);
		close(sync_pipe[0]);
		execve(argv[0], argv, envp);
		perror("execve");
		_exit(127);
	}

	close(sync_pipe[0]);

	fd_cycles = open_hw_event(PERF_COUNT_HW_CPU_CYCLES, child, true, true);
	if (fd_cycles < 0) {
		perror("perf_event_open cycles");
		goto fail_child;
	}

	fd_instret = open_hw_event(PERF_COUNT_HW_INSTRUCTIONS, child, true, true);
	if (fd_instret < 0) {
		perror("perf_event_open instructions");
		goto fail_child;
	}

	if (ioctl(fd_cycles, PERF_EVENT_IOC_RESET, 0) < 0 ||
	    ioctl(fd_instret, PERF_EVENT_IOC_RESET, 0) < 0) {
		perror("perf reset");
		goto fail_child;
	}
	if (ioctl(fd_cycles, PERF_EVENT_IOC_ENABLE, 0) < 0 ||
	    ioctl(fd_instret, PERF_EVENT_IOC_ENABLE, 0) < 0) {
		perror("perf enable");
		goto fail_child;
	}

	if (write(sync_pipe[1], "x", 1) != 1) {
		perror("release child");
		goto fail_child;
	}
	close(sync_pipe[1]);
	sync_pipe[1] = -1;

	if (waitpid(child, &status, 0) < 0) {
		perror("waitpid");
		status = EXIT_FAILURE;
	}

	if (ioctl(fd_cycles, PERF_EVENT_IOC_DISABLE, 0) < 0 ||
	    ioctl(fd_instret, PERF_EVENT_IOC_DISABLE, 0) < 0)
		perror("perf disable");

	if (read_u64(fd_cycles, &cycles) < 0 ||
	    read_u64(fd_instret, &instret) < 0) {
		perror("perf read");
		status = EXIT_FAILURE;
	}

	fprintf(stderr, "perf_user_cycle=%lu\n", cycles);
	fprintf(stderr, "perf_user_instret=%lu\n", instret);

	close(fd_cycles);
	close(fd_instret);
	return wait_status_to_exit(status);

fail_child:
	if (sync_pipe[1] >= 0)
		close(sync_pipe[1]);
	if (fd_cycles >= 0)
		close(fd_cycles);
	if (fd_instret >= 0)
		close(fd_instret);
	waitpid(child, &status, 0);
	return EXIT_FAILURE;
}

int main(int argc, char **argv, char *envp[])
{
	int fd1;
	int fd2;
	const char *prog = argv[0];

	if (argc >= 2 && strcmp(argv[1], "--help") == 0) {
		usage(prog);
		return 0;
	}

	if (argc >= 2 &&
	    (strcmp(argv[1], "--user-count") == 0 ||
	     strcmp(argv[1], "--perf-user") == 0)) {
		argv += 2;
		if (argv[0] && strcmp(argv[0], "--") == 0)
			argv++;
		return run_user_count(prog, argv, envp);
	}

	fd1 = open_hw_event(PERF_COUNT_HW_CPU_CYCLES, 0, false, false);
	if (fd1 < 0) {
		perror("perf_event_open 1");
		exit(EXIT_FAILURE);
	}

	fd2 = open_hw_event(PERF_COUNT_HW_INSTRUCTIONS, 0, false, false);
	if (fd2 < 0) {
		perror("perf_event_open 2");
		exit(EXIT_FAILURE);
	}

	if (argc >= 2) {
		execve(argv[1], &argv[1], envp);
		perror("execve");
		exit(EXIT_FAILURE);
	}

	return print_mach();
}
