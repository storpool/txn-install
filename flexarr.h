#ifndef INCLUDED_FLEXARR_H
#define INCLUDED_FLEXARR_H

/*-
 * Copyright (c) 2013  Peter Pentchev
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
 *
 * flexarr - a trivial implementation of a "flexible array" that may be
 * reallocated as new elements are added
 */

#define FLEXARR_INIT(arr, nelem, nalloc)	do { \
	(arr) = NULL; \
	(nelem) = (nalloc) = 0; \
} while (0)

#define FLEXARR_ALLOC(arr, count, nelem, nalloc)	do { \
	size_t flexarr_ncount = (nelem) + (count); \
	if (flexarr_ncount > (nalloc)) { \
		size_t flexarr_nsize; \
		void *flexarr_p; \
		flexarr_nsize = (nalloc) * 2 + 1; \
		if (flexarr_nsize < flexarr_ncount) \
			flexarr_nsize = flexarr_ncount; \
		flexarr_p = realloc((arr), flexarr_nsize * sizeof(*(arr))); \
		if (flexarr_p == NULL) \
			errx(1, "Out of memory"); \
		(arr) = flexarr_p; \
		(nalloc) = flexarr_nsize; \
	} \
	(nelem) = flexarr_ncount; \
} while (0)

#define FLEXARR_FREE(arr, nalloc)	do { \
	free(arr); \
} while (0)

#endif
