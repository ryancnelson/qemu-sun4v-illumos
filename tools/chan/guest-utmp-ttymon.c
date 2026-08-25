/*
 * Supply the INIT_PROCESS utmpx record normally created by init before
 * entering ttymon's express/getty mode.  socat launches this wrapper on a
 * freshly allocated pty; exec keeps the PID that ttymon looks up.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
#include <utmpx.h>

int
main(void)
{
	struct utmpx entry;
	char *device;
	char *line;
	size_t length;

	device = ttyname(STDIN_FILENO);
	if (device == NULL) {
		(void) fprintf(stderr, "guest-utmp-ttymon: ttyname: %s\n",
		    strerror(errno));
		return (1);
	}
	line = device;
	if (strncmp(line, "/dev/", 5) == 0)
		line += 5;

	(void) memset(&entry, 0, sizeof (entry));
	entry.ut_type = INIT_PROCESS;
	entry.ut_pid = getpid();
	(void) gettimeofday(&entry.ut_tv, NULL);
	(void) strncpy(entry.ut_user, "ttymon", sizeof (entry.ut_user));
	(void) strncpy(entry.ut_line, line, sizeof (entry.ut_line));

	/* A stable four-byte id lets each respawn replace its old record. */
	length = strlen(line);
	if (length > sizeof (entry.ut_id))
		line += length - sizeof (entry.ut_id);
	(void) strncpy(entry.ut_id, line, sizeof (entry.ut_id));

	setutxent();
	if (pututxline(&entry) == NULL) {
		(void) fprintf(stderr,
		    "guest-utmp-ttymon: cannot create utmpx entry\n");
		endutxent();
		return (1);
	}
	endutxent();

	(void) execl("/usr/lib/saf/ttymon", "ttymon", "-g", "-h", "-d",
	    device, "-l", "console", "-p", "login: ", (char *)NULL);
	(void) fprintf(stderr, "guest-utmp-ttymon: exec ttymon: %s\n",
	    strerror(errno));
	return (1);
}
