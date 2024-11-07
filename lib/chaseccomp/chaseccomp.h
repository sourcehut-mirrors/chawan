#include <stdint.h>

/*
 * seccomp
 */

#define SECCOMP_SET_MODE_FILTER	1

#define SECCOMP_RET_KILL_PROCESS	0x80000000u
#define SECCOMP_RET_ALLOW		0x7FFF0000u
#define SECCOMP_RET_TRAP		0x00030000u
#define SECCOMP_RET_ERRNO		0x00050000u
#define SECCOMP_RET_DATA		0x0000FFFFu

struct seccomp_data {
	int nr;
	uint32_t arch;
	uint64_t instruction_pointer;
	uint64_t args[6];
};

/*
 * BPF
 */

/* instruction classes */
#define BPF_LD			0x00
#define BPF_JMP			0x05
#define BPF_RET			0x06

/* ld/ldx fields */
#define BPF_ABS			0x20
#define BPF_W			0x00

/* alu/jmp fields */
#define BPF_JEQ			0x10
#define BPF_JGT			0x20

#define BPF_K			0x00

struct sock_filter {
	uint16_t code;
	uint8_t jt;
	uint8_t jf;
	uint32_t k;
};

struct sock_fprog {
	unsigned short len;
	struct sock_filter *filter;
};

#define BPF_STMT(code, k) { (unsigned short)(code), 0, 0, k }
#define BPF_JUMP(code, k, jt, jf) { (unsigned short)(code), jt, jf, k }

/*
 * chaseccomp stuff
 */

#define COUNTOF(x) (sizeof(x) / sizeof(*(x)))

#define CHA_BPF_LOAD(field) \
	BPF_STMT(BPF_LD | BPF_W | BPF_ABS, \
	    (offsetof(struct seccomp_data, field)))

#define CHA_BPF_RET(val)	BPF_STMT(BPF_RET | BPF_K, val)
#define CHA_BPF_JE(data, n)	BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, data, n, 0)
#define CHA_BPF_JNE(data, m)	BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, data, 0, m)
#define CHA_BPF_JLE(data, m)	BPF_JUMP(BPF_JMP | BPF_JGT | BPF_K, data, 0, m)
