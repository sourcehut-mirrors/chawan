/*
 * ref. seccomp(2)
 * also bpf(4), except I can't find it on Linux... check a BSD.
 */

#define _GNU_SOURCE
#include <sched.h>
#include <stdlib.h>
#include <stddef.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <sys/mman.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <stdint.h>
#include <signal.h>
#include <assert.h>

#include "chaseccomp.h"

static void sigsys_handler_buffer(int sig, siginfo_t *info, void *ucontext)
{
	(void)sig;
	(void)ucontext;
	fprintf(stderr, "Sandbox violation in buffer: syscall #%d\n",
		info->si_syscall);
	abort();
}

int cha_enter_buffer_sandbox(void)
{
	struct sock_filter filter[] = {
#include "chasc_buffer.h"
	};
#ifndef EXPECTED_COUNT
#error "buffer sandbox not built"
#endif
	struct sock_fprog prog = { .len = COUNTOF(filter), .filter = filter };
	struct sigaction act = {
		.sa_flags = SA_SIGINFO,
		.sa_sigaction = sigsys_handler_buffer,
	};

	static_assert(EXPECTED_COUNT == COUNTOF(filter),
		"wrong buffer filter count");
	if (sigaction(SIGSYS, &act, NULL) < 0)
		return 0;
	if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0))
		return 0;
	if (syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER, 0, &prog))
		return 0;
	return 1;
}

static void sigsys_handler_network(int sig, siginfo_t *info, void *ucontext)
{
	(void)sig;
	(void)ucontext;
	fprintf(stderr, "Sandbox violation in network: syscall #%d\n",
		info->si_syscall);
	abort();
}

int cha_enter_network_sandbox(void)
{
#undef EXPECTED_COUNT
	struct sock_filter filter[] = {
#include "chasc_network.h"
	};
#ifndef EXPECTED_COUNT
#error "network sandbox not built"
#endif
	struct sock_fprog prog = { .len = COUNTOF(filter), .filter = filter };
	struct sigaction act = {
		.sa_flags = SA_SIGINFO,
		.sa_sigaction = sigsys_handler_network,
	};

	static_assert(EXPECTED_COUNT == COUNTOF(filter),
		"wrong network filter count");
	if (sigaction(SIGSYS, &act, NULL) < 0)
		return 0;
	if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0))
		return 0;
	if (syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER, 0, &prog))
		return 0;
	return 1;
}
