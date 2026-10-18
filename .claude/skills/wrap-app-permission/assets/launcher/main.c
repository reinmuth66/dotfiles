// Launcher that sits inside the .app and execs the real program (usually a wrapper script),
// whose path is passed in as TARGET at build time. It does nothing else. See default.nix for why it exists.

#include <stdio.h>
#include <unistd.h>

#ifndef TARGET
#error "TARGET must be defined"
#endif

int main(int argc, char **argv) {
	(void)argc;
	argv[0] = TARGET;
	execv(TARGET, argv);
	perror("<tool>-launcher: execv " TARGET);
	return 127;
}
