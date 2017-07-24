#!/usr/bin/perl
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

use v5.010;
use strict;
use warnings;

use Test::More;
use Test::Command;

my $prog = $ENV{TEST_PROG} // './txn';

my $version_line;
my @usage_lines;

sub get_ok_output($ $) {
	my ($cmd, $desc) = @_;

	my $c = Test::Command->new(cmd => $cmd);
	$c->exit_is_num(0, "$desc succeeded");
	$c->stderr_is_eq('', "$desc did not output any errors");
	split /\n/, $c->stdout_value
}

sub get_error_output($ $) {
	my ($cmd, $desc) = @_;

	my $c = Test::Command->new(cmd => $cmd);
	$c->exit_isnt_num(0, "$desc failed");
	$c->stdout_is_eq('', "$desc did not output anything");
	split /\n/, $c->stderr_value
}

plan tests => 8;

# A single version line with -V
subtest 'Version output with -V' => sub {
	my $c = Test::Command->new(cmd => [$prog, '-V']);
	$c->exit_is_num(0, '-V succeeded');
	$c->stderr_is_eq('', '-V did not output any errors');
	my @lines = split /\n/, $c->stdout_value, -1;
	BAIL_OUT('Unexpected number of lines in the -V output') unless @lines == 2;
	BAIL_OUT('Unexpected -V line') unless $lines[0] =~ /^ txn \s \S+ $/x;
	$version_line = $lines[0];
};

# More than one usage line with -h
subtest 'Usage output with -h' => sub {
	my $c = Test::Command->new(cmd => [$prog, '-h']);
	$c->exit_is_num(0, '-h succeeded');
	$c->stderr_is_eq('', '-h did not output any errors');
	my @lines = split /\n/, $c->stdout_value;
	BAIL_OUT('Too few lines in the -h output') unless @lines > 1;
	BAIL_OUT('Unexpected -h first line') unless $lines[0] =~ /^ Usage: \s+ txn /x;
	@usage_lines = @lines;
};

subtest 'Usage and version output with -V -h' => sub {
	my @lines = get_ok_output([$prog, '-V', '-h'], '-V -h');
	is scalar @lines, 1 + @usage_lines, '-V -h output one more line than the usage message';
	is $lines[0], $version_line, '-V -h output the version line first';
	shift @lines;
	is_deeply \@lines, \@usage_lines, '-V -h output the usage message';
};

subtest 'Usage and version output with -hV' => sub {
	my @lines = get_ok_output([$prog, '-hV'], '-hV');
	is scalar @lines, 1 + @usage_lines, '-hV output one more line than the usage message';
	is $lines[0], $version_line, '-hV output the version line first';
	shift @lines;
	is_deeply \@lines, \@usage_lines, '-hV output the usage message';
};

subtest 'Long-form version' => sub {
	my @lines = get_ok_output([$prog, '--version'], '--version');
	is scalar @lines, 1, '--version output a single line';
	is $lines[0], $version_line, '--version output the version information';
};

subtest 'Long-form usage' => sub {
	my @lines = get_ok_output([$prog, '--help'], '--help');
	ok @lines > 1, '--help output more than one line';
	is_deeply \@lines, \@usage_lines, '--help output the usage information';
};

subtest 'Invalid short option' => sub {
	my @lines = get_error_output([$prog, '-Y', 'Makefile'], 'invalid short option -Y');
	is scalar @lines, 1 + scalar @usage_lines, '-Y output one more line than the usage message';
	shift @lines;
	is_deeply \@lines, \@usage_lines, '-Y output the usage message';
};

subtest 'Invalid long option' => sub {
	my @lines = get_error_output([$prog, '--whee', 'Makefile'], 'invalid short option --whee');
	is scalar @lines, 1 + scalar @usage_lines, '--whee output one more line than the usage message';
	shift @lines;
	is_deeply \@lines, \@usage_lines, '--whee output the usage message';
};
