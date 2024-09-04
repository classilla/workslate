/*
 * A modified version of usb2ppp from BURLAP with a smaller buffer and
 * a post buffer send delay.
 * Copyright (C) 2023, 2024 Cameron Kaiser. All rights reserved.
 * Floodgap Free Software License.
 * http://oldvcr.blogspot.com/
 */

#include <fcntl.h>
#include <stdio.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <termios.h>
#include <sys/select.h>

int port, pid = 0;
struct termios tty, tty_saved, tty_saved_in, tty_saved_out, tty_saved_err;
struct sigaction sig;

speed_t
baudr(int baud) {
	switch (baud) {
		case 300: return B300;
		case 600: return B600;
		case 1200: return B1200;
		case 2400: return B2400;
		case 4800: return B4800;
		case 9600: return B9600;
		case 19200: return B19200;
		case 38400: return B38400;
		case 57600: return B57600;
		case 115200: return B115200;
		default: return B0;
	}
	return B0; /* not reached */
}

static int
popen2(char **cmd, int *pid, int *infd, int *outfd)
{
	int p1[2], p2[2];
	if (!cmd || !pid || !infd || !outfd) return -1;
	if (pipe(p1) == -1) return -1;
	if (pipe(p2) == -1) {
		close(p1[1]); close(p1[0]);
		return -1;
	}
	if ((*pid = fork()) == -1) {
		close(p2[1]); close(p2[0]);
		close(p1[1]); close(p1[0]);
		return -1;
	}
	if (*pid) {
		/* parent */
		*infd = p1[1];
		*outfd = p2[0];
		close(p1[0]); close(p2[1]);
		return 0;
	}

	/* child */
	(void)dup2(p1[0], 0);
	(void)dup2(p2[1], 1);
	close(p1[0]); close(p1[1]);
	close(p2[0]); close(p2[1]);
	execvp(cmd[0], cmd);
	/* oops */
#if DEBUG
perror("execvp");
#endif
	exit(255);
	return -1;
}

void
cleanup()
{
	/* handle child process, but don't pingpong */
	sig.sa_handler = SIG_IGN;
	sigaction(SIGCHLD, &sig, NULL);
	if (pid) {
		fprintf(stderr, "killing subprocess\n");
		(void)kill(pid, SIGHUP);
		sleep(1);
		(void)kill(pid, SIGTERM);
		pid = 0;
	}
	fprintf(stderr, "restoring terminal settings\n");
	(void)tcsetattr(port, TCSAFLUSH, &tty_saved);
	(void)close(port);
	(void)tcsetattr(STDIN_FILENO, TCSANOW, &tty_saved_in);
	(void)tcsetattr(STDOUT_FILENO, TCSANOW, &tty_saved_out);
	(void)tcsetattr(STDERR_FILENO, TCSANOW, &tty_saved_err);
}

void
deadkid()
{
	pid = 0;
	fprintf(stderr, "subprocess terminated\n");
	exit(0);
}

void
deadme()
{
	fprintf(stderr, "terminating on user signal\n");
	exit(0);
}

#define SERBUF 1

int
main(int argc, char **argv)
{
	int port, speed, infd, outfd, bytes;
	fd_set master_rfd, rfd, wfd;
	struct timeval tv;
	char buf[SERBUF];
	speed_t speedd;

	/* it's not enough to just restore the serial port settings */
	if (tcgetattr(STDIN_FILENO, &tty_saved_in) ||
			tcgetattr(STDOUT_FILENO, &tty_saved_out) ||
			tcgetattr(STDERR_FILENO, &tty_saved_err)) {
		perror("tcgetattr (tty)");
		return 1;
	}

	if (argc < 2) {
		fprintf(stderr, "missing path to serial port (e.g., /dev/cu.usbserial)\n");
		return 1;
	}
	if (argc < 3) {
		fprintf(stderr, "missing serial port speed\n");
		return 1;
	}
	speed = atoi(argv[2]);
	if (!speed || ((speedd = baudr(speed)) == B0)) {
		fprintf(stderr, "unsupported baud rate %d\n", speed);
		return 1;
	}

	fprintf(stderr, "opening %s\n", argv[1]);
	port = open(argv[1], O_RDWR | O_NOCTTY);
	if (!isatty(port)) {
		fprintf(stderr, "warning: isatty returned false for this path\n");
	}
	fprintf(stderr, "setting up for serial access\n");
	if (tcgetattr(port, &tty)) {
		perror("tcgetattr");
		close(port);
		return 1;
	}
	tty_saved = tty;

	fprintf(stderr, "setting flags on serial port fd=%d\n", port);
	memset(&tty, 0, sizeof(tty));
	tty.c_cflag |= (CS8 | CREAD | CLOCAL);
	tty.c_cc[VTIME] = 5;
	tty.c_cc[VMIN] = 1;
	(void)cfsetospeed(&tty, speedd);
	(void)cfsetispeed(&tty, speedd);
	if (tcsetattr(port, TCSAFLUSH, &tty)) {
		perror("tcsetattr (tty)");
		close(port);
		return 1;
	}
	atexit(cleanup);
	sig.sa_handler = deadkid;
	sigaction(SIGCHLD, &sig, NULL);
	sig.sa_handler = deadme;
	sigaction(SIGINT, &sig, NULL);
	sigaction(SIGHUP, &sig, NULL);
	sigaction(SIGTERM, &sig, NULL);

	if (argc < 4) {
		fprintf(stderr, "missing path to process\n");
		return 1;
	}
	if (argc < 5) {
		if (argv[4] != NULL) {
			fprintf(stderr, "unexpected: no null termination\n");
			return 255;
		}
		fprintf(stderr, "warning: no arguments being passed to %s\n",
			argv[3]);
	} else {
		fprintf(stderr, "starting process %s\n", argv[3]);
	}
	if (popen2(&(argv[3]), &pid, &infd, &outfd)) {
		perror("popen2");
		close(port);
		return 255;
	}
	fprintf(stderr, "subprocess pid= %d\n", pid);
	
	FD_ZERO(&master_rfd);
	FD_SET(port, &master_rfd);
	FD_SET(outfd, &master_rfd);

	for(;;) {
		/* time out if we can't write. check individually */
		FD_ZERO(&wfd);
		FD_SET(port, &wfd);
		tv.tv_sec = 5;
		tv.tv_usec = 0;
		if (select(outfd+1, NULL, &wfd, NULL, &tv) < 1) {
			perror("timeout write select on port");
			return 1;
		}
		FD_ZERO(&wfd);
		FD_SET(infd, &wfd);
		tv.tv_sec = 5;
		tv.tv_usec = 0;
		if (select(outfd+1, NULL, &wfd, NULL, &tv) < 1) {
			perror("timeout write select on process");
			return 1;
		}

		/* wait for something to read */
		rfd = master_rfd;
		if (select(outfd+1, &rfd, NULL, NULL, NULL) < 0)
			perror("warning: read select");

		if (FD_ISSET(port, &rfd)) {
			if (bytes = read(port, &buf, SERBUF)) {
				write(infd, &buf, bytes);
			} else {
				// XXX
			}
		}
		if (FD_ISSET(outfd, &rfd)) {
			if (bytes = read(outfd, &buf, SERBUF)) {
				write(port, &buf, bytes);
				usleep(3000);
			} else {
				// XXX
			}
		}
	}

	return 255; /* not reached */
}
