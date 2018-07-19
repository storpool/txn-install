#!/usr/bin/make -f
#
# Copyright (c) 2017, 2018  Peter Pentchev
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

MAN1=		txn.1
MAN1GZ=		${MAN1}.gz
MAN1GZLINKS=	txn-install.1.gz txn-remove.1.gz

LOCALBASE?=	/usr/local
PREFIX?=	${LOCALBASE}
BINDIR?=	${PREFIX}/bin
MANDIR?=	${PREFIX}/man/man

RM?=		rm -f
LN?=		ln
LN_S?=		${LN} -s

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

MKDIR?=		mkdir -p
INSTALL?=	install

BINOWN?=	root
BINGRP?=	root
BINMODE?=	755

SHAREOWN?=	${BINOWN}
SHAREGRP?=	${BINGRP}
SHAREMODE?=	644

STRIP?=		-s

INSTALL_PROGRAM=	${INSTALL} -o ${BINOWN} -g ${BINGRP} -m ${BINMODE} ${STRIP}
INSTALL_DATA?=	${INSTALL} -o ${SHAREOWN} -g ${SHAREGRP} -m ${SHAREMODE}

all:		${PROG} ${MAN1GZ}

install:	all
		${MKDIR} ${DESTDIR}${BINDIR}
		${INSTALL_PROGRAM} ${PROG} ${DESTDIR}${BINDIR}/
		${MKDIR} ${DESTDIR}${MANDIR}1
		${INSTALL_DATA} ${MAN1GZ} ${DESTDIR}${MANDIR}1/
		set -e; for dst in ${MAN1GZLINKS}; do \
			${LN_S} ${MAN1GZ} ${DESTDIR}${MANDIR}1/$$dst; \
		done

clean:
		${RM} ${PROG} ${OBJS} ${MAN1GZ}

test-single:	${TEST_PROG}
		echo "Testing ${TEST_PROG}"
		prove t
		echo "Testing ${TEST_PROG} complete"

test-real:	${PROG}
		${MAKE} test-single TEST_PROG="./${PROG}"

test:		test-real

${PROG}:	${OBJS}
		${CC} ${LDFLAGS} -o ${PROG} ${OBJS}

${MAN1GZ}:	${MAN1}
		gzip -c9 -n ${MAN1} > ${MAN1GZ}.tmp || (${RM} ${MAN1GZ}.tmp; exit 1)
		mv ${MAN1GZ}.tmp ${MAN1GZ} || (${RM} ${MAN1GZ}.tmp; exit 1)
		
.PHONY:		all clean test test-real test-single
