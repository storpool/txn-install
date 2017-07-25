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

#ifndef __dead2
#if defined(__GNUC__) && __GNUC__ >= 2
#define __dead2	__attribute__((noreturn))
#else
#define __dead2
#endif
#endif

#include "flexarr.h"

enum index_action {
	ACT_CREATE,
	ACT_PATCH,
};

static const char * const index_action_names[] = {
	"create",
	"patch",
};

struct index_line {
	bool			read_any;
	size_t			idx;
	const char		*module;
	enum index_action	action;
	const char		*filename;
};

struct txn_db {
	const char * const dir;
	const char * const idx;
	FILE * const file;
	const char * const module;
};

#define INDEX_LINE_INIT ((struct index_line){ .read_any = false, })

#define INDEX_NUM_SIZE	6
#define INDEX_FIRST	"000000\n"

static bool		verbose;

static void __dead2
usage(const bool _ferr)
{
	const char * const s =
	    "Usage:\ttxn [-Nv] filename...\n"
	    "\ttxn -V | -h\n"
	    "\n"
	    "\t-h\tdisplay program usage information and exit\n"
	    "\t-N\tno operation mode; display what would have been done\n"
	    "\t-V\tdisplay program version information and exit\n"
	    "\t-v\tverbose operation; display diagnostic output\n";

	fprintf(_ferr? stderr: stdout, "%s", s);
	exit(_ferr ? 1 : 0);
}

static void
version(void)
{
	puts("txn 0.1.0.dev1");
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

	return (db_env != NULL ? db_env : "/var/lib/txn");
}

static const char *
get_db_index(const char * const db_dir)
{
	char *idx;
	const int res = asprintf(&idx, "%s/txn.index", db_dir);
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

static struct txn_db
do_open_db(const char * const dir, const char * const idx)
{
	const int fd = open(idx, O_RDWR);
	if (fd == -1)
		err(1, "Could not open the database index '%s'", idx);
	if (flock(fd, LOCK_EX | LOCK_NB) == -1)
		err(1, "Could not lock the database index '%s'", idx);

	FILE * const file = fdopen(fd, "r+");
	if (file == NULL)
		err(1, "Could not reopen the database index '%s'", idx);

	const char * const module = getenv("TXN_INSTALL_MODULE");

	return ((struct txn_db){
		.dir = dir,
		.idx = idx,
		.file = file,
		.module = module != NULL ? module : "unknown",
	});
}

static struct txn_db
open_db(void)
{
	const char * const dir = get_db_dir();
	const char * const idx = get_db_index(dir);
	return (do_open_db(dir, idx));
}

static struct txn_db
open_or_create_db(const bool may_exist)
{
	const char * const dir = get_db_dir();
	const char * const idx = get_db_index(dir);
	struct stat sb;
	if (stat(dir, &sb) == -1) {
		if (errno != ENOENT)
			err(1, "Could not check for the existence of '%s'", dir);
		if (mkdir(dir, 0755) == -1)
			err(1, "Could not create the database directory '%s'", dir);
	} else if (!S_ISDIR(sb.st_mode)) {
		errx(1, "Not a directory: %s", dir);
	} else {
		if (stat(idx, &sb) == -1) {
			if (errno != ENOENT)
				err(1, "Could not check for the existence of '%s'", idx);
		} else if (!S_ISREG(sb.st_mode)) {
			errx(1, "Not a regular file: %s", idx);
		} else if (!may_exist) {
			errx(1, "The database index '%s' already exists", idx);
		} else {
			return (do_open_db(dir, idx));
		}
	}

	const int fd = open(idx, O_CREAT | O_EXCL | O_RDWR);
	if (fd == -1)
		err(1, "Could not create the database index '%s'", idx);
	if (!writen(fd, INDEX_FIRST, INDEX_NUM_SIZE + 1))
		err(1, "Could not write out an empty database index '%s'", idx);
	if (close(fd) == -1)
		err(1, "Could not close the newly-created database index '%s'", idx);
	return (do_open_db(dir, idx));
}

static int
cmd_db_init(const int argc, char * const argv[] __unused)
{
	if (argc > 1)
		usage(true);

	open_or_create_db(false);
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

	errx(1, "FIXME: read the action from %s, got line index %zu and modlule %s", db_idx, idx, module);
}

static int
cmd_list_modules(const int argc, char * const argv[] __unused)
{
	if (argc > 1)
		usage(true);

	const struct txn_db db = open_db();
	struct index_line ln = INDEX_LINE_INIT;
	char **modules;
	size_t mlen, mall;
	FLEXARR_INIT(modules, mlen, mall);
	while (true) {
		read_next_index_line(db.file, db.idx, &ln);
		if (ln.module == NULL)
			break;
		warnx("FIXME: process module %s", ln.module);
	}
	if (fclose(db.file) == EOF)
		err(1, "Could not close the database index '%s'", db.idx);

	for (size_t i = 0; i < mlen; i++) {
		puts(modules[i]);
		free(modules[i]);
	}
	FLEXARR_FREE(modules, mall);
	return (0);
}

static const char *
get_destination_filename(const char * const src, const char * const dst)
{
	struct stat sb;
	if (stat(dst, &sb) == -1) {
		if (errno != ENOENT)
			err(1, "Could not check for the existence of %s", dst);
		else
			return dst;
	} else if (!S_ISDIR(sb.st_mode)) {
		return dst;
	}

	const char * const last_slash = strrchr(src, '/');
	const char * const filename = last_slash != NULL ? last_slash + 1 : src;

	const size_t len = strlen(dst);
	const bool has_slash = len == 0 ? false : dst[len - 1] == '/';

	char *full;
	if (asprintf(&full, "%s%s%s", dst, has_slash ? "" : "/", filename) == -1)
		err(1, "Could not build a destination pathname");
	return (full);
}

static bool
write_db_entry(const struct txn_db * const db, const struct index_line ln)
{
	if (fprintf(db->file, "%06zu %s %s %s\n%06zu\n",
	    ln.idx, ln.module, index_action_names[ln.action],
	    ln.filename, ln.idx + 1) < 0 ||
	    ferror(db->file)) {
		warn("Could not write to the database index '%s'", db->idx);
		return (false);
	}
	if (fflush(db->file) == EOF) {
		warn("Could not sync a write to the database index '%s'", db->idx);
		return (false);
	}
	return (true);
}

static bool
record_install(const char * const src, const char * const orig_dst, const struct txn_db * const db, const size_t line_idx)
{
	const char * const dst = get_destination_filename(src, orig_dst);
	struct stat sb;

	if (stat(src, &sb) == -1) {
		warn("Invalid source filename '%s'", src);
		return (false);
	}
	else if (!S_ISREG(sb.st_mode)) {
		warnx("Not a regular source file: '%s'", src);
		return (false);
	}

	if (stat(dst, &sb) == -1) {
		if (errno != ENOENT) {
			warnx("Could not check for the existence of the destination file '%s'", dst);
			return (false);
		}

		return (write_db_entry(db, (struct index_line){
			.idx = line_idx,
			.module = db->module,
			.action = ACT_CREATE,
			.filename = dst,
		}));
	}

	/* But is it a text file? */
	{
		int fds[2];
		if (pipe(fds) == -1) {
			warn("Could not create a pipe for file(1) on '%s'", src);
			return (false);
		}

		const pid_t pid = fork();
		if (pid == -1) {
			warn("Could not fork for file(1) on '%s'", src);
			return (false);
		} else if (pid == 0) {
			if (close(fds[0]) == -1)
				err(1, "Could not close the read end of the pipe for '%s'", src);
			if (dup2(fds[1], 1) == -1)
				err(1, "Could not reopen the standard output for '%s'", src);
			execlp("file", "file", "--", src, NULL);
			err(1, "Could not execute file(1) on '%s'", src);
		}

		if (close(fds[1]) == -1) {
			warn("Could not close the write end of the pipe for '%s'", src);
			return (false);
		}
		FILE * const filefile = fdopen(fds[0], "r");
		if (filefile == NULL) {
			warn("Could not reopen the read end of the pipe for '%s'", src);
			return (false);
		}

		char *fline = NULL;
		size_t len = 0;
		if (getline(&fline, &len, filefile) == -1) {
			warn("Could not read a line from the output of file(1) on '%s'", src);
			return (false);
		}
		fclose(filefile);

		const size_t srclen = strlen(src);
		if (len < srclen + 2) {
			warnx("Could not parse the output of file(1) on '%s': line too short: %s", src, fline);
			return (false);
		}
		if (strncmp(fline, src, srclen) != 0 ||
		    strncmp(fline + srclen, ": ", 2) != 0) {
			warnx("Could not parse the output of file(1) on '%s': line starts weirdly: %s", src, fline);
			return (false);
		}
		errx(1, "FIXME: parse the rest of the output of file(1) on '%s': %s", src, fline + srclen + 2);
	}
	errx(1, "FIXME: record the installation of %s to %s into %s as %zu", src, dst, db->idx, line_idx);
}

static bool
run_install(char * const argv[])
{
	const pid_t pid = fork();
	if (pid == -1) {
		warn("Could not fork for install(1)");
		return (false);
	} else if (pid == 0) {
		execvp("install", argv);
		err(1, "Could not run install(1)");
	}

	int stat;
	const int res = waitpid(pid, &stat, 0);
	if (res == -1) {
		warn("Could not wait for install(1) to complete");
		return (false);
	} else if (!WIFEXITED(stat) || WEXITSTATUS(stat) != 0) {
		warn("install(1) failed");
		return (false);
	}
	return (true);
}

static void
rollback_install(const long pos, const struct txn_db * const db, const size_t line_idx)
{
	errx(1, "FIXME: roll back an installation at position %ld, index %zu in %s", pos, line_idx, db->idx);
}

static int
cmd_install(const int argc, char * const argv[])
{
	int ch;
	optind = 0;
	while (ch = getopt(argc, argv, "cg:m:o:"), ch != -1)
		switch (ch) {
			case 'c':
			case 'g':
			case 'm':
			case 'o':
				break;

			default:
				errx(1, "Unhandled install(1) command-line option");
				/* NOTREACHED */
		}

	const int pos_argc = argc - optind;
	char * const * const pos_argv = argv + optind;
	if (pos_argc < 2) // FIXME: handle -d
		usage(true);

	(void)debug; // FIXME: remove me

	const struct txn_db db = open_or_create_db(true);
	if (fseek(db.file, -(INDEX_NUM_SIZE + 1), SEEK_END) == -1)
		err(1, "Could not seek almost to the end of the database index '%s'", db.idx);
	struct index_line ln = INDEX_LINE_INIT;
	read_next_index_line(db.file, db.idx, &ln);
	if (ln.module != NULL)
		errx(1, "Internal error, the last line of the database index should really be a last one...");

	if (fseek(db.file, -(INDEX_NUM_SIZE + 1), SEEK_CUR) == -1)
		err(1, "Could not seek back in the database index '%s'", db.idx);
	const long rollback_pos = ftell(db.file);
	const size_t rollback_idx = ln.idx;

	const char * const destination = pos_argv[pos_argc - 1];
	for (int i = 0; i < pos_argc - 1; i++) {
		if (!record_install(pos_argv[i], destination, &db, ln.idx)) {
			rollback_install(rollback_pos, &db, rollback_idx);
			return (1);
		}
		ln.idx++;
	}

	if (!run_install(argv)) {
		rollback_install(rollback_pos, &db, rollback_idx);
		return (1);
	}
	return (0);
}

const struct {
	const char *name;
	int (*func)(int argc, char * const argv[]);
} cmds[] = {
	{"db-init", cmd_db_init},
	{"install", cmd_install},
	{"list-modules", cmd_list_modules},
};
#define NUM_CMDS (sizeof(cmds) / sizeof(cmds[0]))

static int
run_command(const char * const cmd, const int argc, char * const argv[])
{
	for (size_t i = 0; i < NUM_CMDS; i++)
		if (strcmp(cmd, cmds[i].name) == 0)
			return cmds[i].func(argc, argv);
	warnx("Invalid command '%s'", cmd);
	usage(true);
	/* NOTREACHED */
}

int
main(const int argc, char * const argv[])
{
	{
		const char * const slash = strrchr(argv[0], '/');
		const char * const fname = slash != NULL ? slash + 1 : argv[0];
		if (strncmp(fname, "txn-", 4) == 0) {
			const char * const cmd = fname + 4;
			return (run_command(cmd, argc, argv));
		}
	}

	bool hflag = false, Vflag = false;
	int ch;
	while (ch = getopt(argc, argv, "+hVv-:"), ch != -1)
		switch (ch) {
			case 'h':
				hflag = true;
				break;

			case 'V':
				Vflag = true;
				break;

			case 'v':
				verbose = true;
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
				usage(true);
				/* NOTREACHED */
		}
	if (Vflag)
		version();
	if (hflag)
		usage(false);
	if (Vflag || hflag)
		return (0);

	const int pos_argc = argc - optind;
	char * const * const pos_argv = argv + optind;

	if (pos_argc < 1)
		usage(true);
	return (run_command(pos_argv[0], pos_argc, pos_argv));
}
