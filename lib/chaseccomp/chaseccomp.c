/*
 * ref. seccomp(2)
 * also bpf(4), except I can't find it on Linux... check a BSD.
 */

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

#include "chaseccomp.h"

int cha_enter_buffer_sandbox(void)
{
	struct sock_filter filter[] = {
#include "chasc_buffer.h"
	};
	struct sock_fprog prog = { .len = COUNTOF(filter), .filter = filter };

	if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0))
		return 0;
	if (syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER, 0, &prog))
		return 0;
	return 1;
}

int cha_enter_network_sandbox(void)
{
	struct sock_filter filter[] = {
#include "chasc_network.h"
	};
	struct sock_fprog prog = { .len = COUNTOF(filter), .filter = filter };

	if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0))
		return 0;
	if (syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER, 0, &prog))
		return 0;
	return 1;
}
