#include <stddef.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <string.h>

int bind_unix_from_c(int socket, const char *path, int pathlen)
{
	struct sockaddr_un sa = {
		.sun_family = AF_UNIX
	};
	int len = offsetof(struct sockaddr_un, sun_path) + pathlen + 1;

	memcpy(sa.sun_path, path, pathlen + 1);
	return bind(socket, (struct sockaddr *)&sa, len);
}

int connect_unix_from_c(int socket, const char *path, int pathlen)
{
	struct sockaddr_un sa = {
		.sun_family = AF_UNIX
	};
	int len = offsetof(struct sockaddr_un, sun_path) + pathlen + 1;

	memcpy(sa.sun_path, path, pathlen + 1);
	return connect(socket, (struct sockaddr *)&sa, len);
}

/*
 * See https://stackoverflow.com/a/4491203
 * Send a file handle to socket `sock`.
 * Returns: 1 on success, -1 on error. I *think* this never returns 0. */
ssize_t sendfd(int sock, int fd)
{
	struct msghdr hdr;
	struct iovec iov;
	int cmsgbuf[CMSG_SPACE(sizeof(int))];
	char buf = '\0';
	struct cmsghdr *cmsg;

	memset(&hdr, 0, sizeof(hdr));
	iov.iov_base = &buf;
	iov.iov_len = 1;
	hdr.msg_iov = &iov;
	hdr.msg_iovlen = 1;
	hdr.msg_control = &cmsgbuf[0];
	hdr.msg_controllen = CMSG_LEN(sizeof(fd));
	cmsg = CMSG_FIRSTHDR(&hdr);
	cmsg->cmsg_len = CMSG_LEN(sizeof(fd));
	cmsg->cmsg_level = SOL_SOCKET;
	cmsg->cmsg_type = SCM_RIGHTS;
	*((int *)CMSG_DATA(cmsg)) = fd;
	return sendmsg(sock, &hdr, 0);
}

/*
 * Receive a file handle from socket `sock`.
 * Sets `fd` to the result if recvmsg returns sizeof(int), otherwise to -1.
 * Returns: the return value of recvmsg; this may be -1. */
ssize_t recvfd(int sock, int *fd)
{
	ssize_t n;
	struct iovec iov;
	struct msghdr hdr;
	int cmsgbuf[CMSG_SPACE(sizeof(int))];
	struct cmsghdr *cmsg;
	char buf = '\0';

	iov.iov_base = &buf;
	iov.iov_len = 1;
	memset(&hdr, 0, sizeof(hdr));
	hdr.msg_iov = &iov;
	hdr.msg_iovlen = 1;
	hdr.msg_control = &cmsgbuf[0];
	hdr.msg_controllen = CMSG_SPACE(sizeof(int));
	n = recvmsg(sock, &hdr, 0);
	if (n <= 0) {
		*fd = -1;
		return n;
	}
	cmsg = CMSG_FIRSTHDR(&hdr);
	*fd = *((int *)CMSG_DATA(cmsg));
	return n;
}
