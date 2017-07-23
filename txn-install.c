/*-
 * Copyright (c) 2017  Peter Pentchev
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#define _GNU_SOURCE

#include <sys/types.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef __printflike
#if defined(__GNUC__) && __GNUC__ >= 3
#define __printflike(x, y)	__attribute__((format(printf, (x), (y))))
#else
#define __printflike(x, y)
#endif
#endif

#ifndef __unused
#if defined(__GNUC__) && __GNUC__ >= 2
#define __unused	__attribute__((unused))
#else
#define __unused
#endif
#endif

#include "flexarr.h"

enum index_action {
	ACT_CREATE,
	ACT_PATCH,
	ACT_OVERWRITE,
	ACT_REMOVE,
};

struct index_line {
	bool			read_any;
	size_t			idx;
	char			*module;
	enum index_action	action;
	char			*filename;
};

#define INDEX_LINE_INIT ((struct index_line){ .read_any = false, })

#define INDEX_NUM_SIZE	6
#define INDEX_FIRST	"000000\n"

static bool		verbose;

static void
usage(const bool _ferr)
{
	const char * const s =
	    "Usage:\ttxn-install [-Nv] filename...\n"
	    "\ttxn-install -V | -h\n"
	    "\n"
	    "\t-h\tdisplay program usage information and exit\n"
	    "\t-N\tno operation mode; display what would have been done\n"
	    "\t-V\tdisplay program version information and exit\n"
	    "\t-v\tverbose operation; display diagnostic output\n";

	fprintf(_ferr? stderr: stdout, "%s", s);
	if (_ferr)
		exit(1);
}

static void
version(void)
{
	puts("txn-install 0.1.0.dev1");
}

static void
debug(const char * const fmt, ...)
{
	va_list v;

	va_start(v, fmt);
	if (verbose)
		vfprintf(stderr, fmt, v);
	va_end(v);
}

static const char *
get_db_dir(void)
{
	const char * const db_env = getenv("TXN_INSTALL_DB");

	return (db_env != NULL ? db_env : "/var/lib/txn-install");
}

static const char *
get_db_index(const char * const db_dir)
{
	char *idx;
	const int res = asprintf(&idx, "%s/txn-install.index", db_dir);
	if (res == -1)
		err(1, "Could not allocate memory for the index filename");
	return (idx);
}

static bool
writen(const int fd, const char * const buf, const size_t len)
{
	size_t left = len;
	while (left > 0) {
		const ssize_t n = write(fd, buf + len - left, left);
		/* We do not need any fancy EAGAIN/EINPROGRESS handling here */
		if (n < 1)
			return (false);
		left -= n;
	}
	return (true);
}

static int
cmd_db_init(const int argc, char * const argv[] __unused)
{
	if (argc > 0)
		usage(true);

	const char * const db_dir = get_db_dir();
	const char * const db_idx = get_db_index(db_dir);
	struct stat sb;
	if (stat(db_dir, &sb) == -1) {
		if (errno != ENOENT)
			err(1, "Could not check for the existence of '%s'", db_dir);
		if (mkdir(db_dir, 0755) == -1)
			err(1, "Could not create the database directory '%s'", db_dir);
	} else if (!S_ISDIR(sb.st_mode)) {
		errx(1, "Not a directory: %s", db_dir);
	} else {
		if (stat(db_idx, &sb) == -1) {
			if (errno != ENOENT)
				err(1, "Could not check for the existence of '%s'", db_idx);
		} else if (!S_ISREG(sb.st_mode)) {
			errx(1, "Not a regular file: %s", db_idx);
		} else {
			errx(1, "The database index '%s' already exists", db_idx);
		}
	}

	const int fd = open(db_idx, O_CREAT | O_EXCL | O_RDWR);
	if (fd == -1)
		err(1, "Could not create the database index '%s'", db_idx);
	if (!writen(fd, INDEX_FIRST, strlen(INDEX_FIRST)))
		err(1, "Could not write out an empty database index '%s'", db_idx);
	if (close(fd) == -1)
		err(1, "Could not close the newly-created database index '%s'", db_idx);
	return (0);
}

static void
read_next_index_line(FILE * const fp, const char * const db_idx, struct index_line * const ln)
{
	/* Read the serial number first */
	size_t idx = 0;
	{
		for (size_t ofs = 0; ofs < INDEX_NUM_SIZE; ofs++) {
			const int ch = fgetc(fp);
			if (ch == EOF) {
				if (ferror(fp))
					err(1, "Could not read a line index from '%s'", db_idx);
				else
					errx(1, "Invalid database index '%s': incomplete line index at EOF", db_idx);
			} else if (ch < '0' || ch > '9') {
				errx(1, "Invalid database index '%s': bad character in the line index", db_idx);
			}
			idx = idx * 10 + (ch - '0');
		}

		const size_t expected = ln->read_any ? ln->idx + 1 : 0;
		if (idx != expected)
			errx(1, "Invalid database index '%s': expected line index %zu, got %zu", db_idx, expected, idx);

		const int ch = fgetc(fp);
		if (ch == EOF) {
			if (ferror(fp))
				err(1, "Could not read a module name from '%s'", db_idx);
			else
				errx(1, "Invalid database index '%s': no module name at EOF", db_idx);
		} else if (ch == '\n') {
			ln->read_any = true;
			ln->idx = idx;
			ln->module = NULL;
			return;
		} else if (ch != ' ') {
			errx(1, "Invalid database index '%s': expected a space before the module name at %zu", db_idx, idx);
		}
	}

	/* Read the module name or return a "last line" entry */
	char *module;
	{
		size_t mlen, mall;
		FLEXARR_INIT(module, mlen, mall);
		while (true) {
			const int ch = fgetc(fp);
			if (ch == EOF) {
				if (ferror(fp))
					err(1, "Could not read a module name from '%s'", db_idx);
				else
					errx(1, "Invalid database index '%s': no space after the module name at %zu", db_idx, idx);
			} else if (ch == ' ') {
				FLEXARR_ALLOC(module, 1, mlen, mall);
				module[mlen - 1] = '\0';
				break;
			} else if (!((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || (ch == '-'))) {
				errx(1, "Invalid database index '%s': invalid character '%c' in the module name at %zu", db_idx, ch, idx);
			} else {
				FLEXARR_ALLOC(module, 1, mlen, mall);
				module[mlen - 1] = ch;
			}
		}
		errx(1, "FIXME: go on with module '%s' at line index %zu", module, idx);
	}

	errx(1, "FIXME: read the module from %s, got line index %zu", db_idx, idx);
}

static int
cmd_list_modules(const int argc, char * const argv[] __unused)
{
	if (argc > 0)
		usage(true);

	const char * const db_dir = get_db_dir();
	const char * const db_idx = get_db_index(db_dir);
	const int fd = open(db_idx, O_RDONLY);
	if (fd == -1)
		err(1, "Could not open the database index '%s'", db_idx);
	if (flock(fd, LOCK_EX | LOCK_NB) == -1)
		err(1, "Could not lock the database index '%s'", db_idx);
	FILE * const fp = fdopen(fd, "r");
	if (fp == NULL)
		err(1, "Could not fdopen() the database index '%s'", db_idx);

	struct index_line ln = INDEX_LINE_INIT;
	char **modules;
	size_t mlen, mall;
	FLEXARR_INIT(modules, mlen, mall);
	while (true) {
		read_next_index_line(fp, db_idx, &ln);
		if (ln.module == NULL)
			break;
		warnx("FIXME: process module %s", ln.module);
	}
	if (fclose(fp) == EOF)
		err(1, "Could not close the database index '%s'", db_idx);

	for (size_t i = 0; i < mlen; i++) {
		puts(modules[i]);
		free(modules[i]);
	}
	FLEXARR_FREE(modules, mall);
	return (0);
}

const struct {
	const char *name;
	int (*func)(int argc, char * const argv[]);
} cmds[] = {
	{"db-init", cmd_db_init},
	{"list-modules", cmd_list_modules},
};
#define NUM_CMDS (sizeof(cmds) / sizeof(cmds[0]))

int
main(int argc, char * const argv[])
{
	bool hflag = false, Vflag = false, noop = false;
	int ch;
	const char *transcmd = NULL;
	while (ch = getopt(argc, argv, "hNVvX:-:"), ch != -1)
		switch (ch) {
			case 'h':
				hflag = true;
				break;

			case 'N':
				noop = true;
				break;

			case 'V':
				Vflag = true;
				break;

			case 'v':
				verbose = true;
				break;

			case 'X':
				transcmd = optarg;
				break;

			case '-':
				if (strcmp(optarg, "help") == 0)
					hflag = true;
				else if (strcmp(optarg, "version") == 0)
					Vflag = true;
				else {
					warnx("Invalid long option '%s' specified", optarg);
					usage(true);
				}
				break;

			default:
				usage(1);
				/* NOTREACHED */
		}
	if (Vflag)
		version();
	if (hflag)
		usage(false);
	if (Vflag || hflag)
		return (0);

	argc -= optind;
	argv += optind;

	if (transcmd != NULL) {
		if (strcmp(transcmd, "list") == 0) {
			puts("Available commands (-X):");
			for (size_t i = 0; i < NUM_CMDS; i++)
				puts(cmds[i].name);
			return (0);
		}
		for (size_t i = 0; i < NUM_CMDS; i++)
			if (strcmp(transcmd, cmds[i].name) == 0)
				return cmds[i].func(argc, argv);
		errx(1, "Invalid command '%s', use '-X list' for a list", transcmd);
	}

	if (argc < 1)
		usage(true);

	/* OK, really process the command-line arguments */
	for (int i = 0; i < argc; i++) {
		if (noop) {
			puts(argv[i]);
		} else {
			const char * const fname = argv[i];
			debug("Processing %s\n", fname);
			struct stat sb;
			if (stat(fname, &sb) == -1)
				err(1, "Could not examine '%s'", fname);
			printf("%s %jd\n", fname, (intmax_t)sb.st_size);
		}
	}
	return (0);
}
