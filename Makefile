#!/usr/bin/make -f
#
# Copyright (c) 2017  Peter Pentchev
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

PROG=		txn
SRCS=		txn-install.c
OBJS=		txn-install.o

RM?=		rm -f

CPPFLAGS_STD?=	-D_POSIX_C_SOURCE=200809L -D_XOPEN_SOURCE=700

CPPFLAGS+=	${CPPFLAGS_STD}

CFLAGS_OPT?=	-O2 -g -pipe
CFLAGS_STD?=	-std=c99
CFLAGS_WARN?=	-Wall -W -Wextra

CFLAGS?=	${CFLAGS_OPT}
CFLAGS+=	${CFLAGS_STD} ${CFLAGS_WARN}

# FIXME: comment -Werror out at some point
CFLAGS+=	-Werror
CFLAGS+=	-pipe -Wall -W -std=c99 -pedantic -Wbad-function-cast \
		-Wcast-align -Wcast-qual -Wchar-subscripts -Winline \
		-Wmissing-prototypes -Wnested-externs -Wpointer-arith \
		-Wredundant-decls -Wshadow -Wstrict-prototypes -Wwrite-strings

all:		${PROG}

clean:
		${RM} ${PROG} ${OBJS}

test-single:	${TEST_PROG}
		echo "Testing ${TEST_PROG}"
		prove t
		echo "Testing ${TEST_PROG} complete"

test-real:	${PROG}
		${MAKE} test-single TEST_PROG="./${PROG}"

test:		test-real

${PROG}:	${OBJS}
		${CC} ${LDFLAGS} -o ${PROG} ${OBJS}

.PHONY:		all clean test test-real test-single
