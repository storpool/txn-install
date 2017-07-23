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

use File::Temp qw(tempdir);
use Path::Tiny;
use Test::More;
use Test::Command;

my $prog = $ENV{TEST_PROG} // './txn-install';

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

plan tests => 4;

my $tempdir = tempdir(CLEANUP => 1);
my $tempd = path($tempdir);
my $data = $tempd->child('data');
my $dbdir = $tempd->child('db');
my $dbidx = $dbdir->child('txn-install.index');
my $dbfirst = $dbdir->child('txn-install.000000');

$data->mkpath({ mode => 0755 });
$dbdir->mkpath({ mode => 0755 });
$ENV{'TXN_INSTALL_DB'} = $dbdir;

subtest 'Error out without a database' => sub {
	plan tests => 5;
	my @lines = get_error_output([$prog, '-X', 'list-modules'], 'list-modules without a database');
	is scalar @lines, 1, 'list-modules without a database returned a single error message';
	ok ! -f $dbidx, 'list-modules did not create a database by itself';
	ok ! -f $dbfirst, 'list-modules did not create a first entry by itself';
};

subtest 'Initialize a database' => sub {
	plan tests => 6;
	my @lines = get_ok_output([$prog, '-X', 'db-init'], 'db-init');
	is scalar @lines, 0, 'db-init did not return any output';
	ok -f $dbidx, 'db-init created a database';
	ok ! -f $dbfirst, 'db-init did not create a first entry by itself';
	is $dbidx->slurp_utf8, "000000\n", 'db-init created an empty database';
};

subtest 'Do not reinitialize a database' => sub {
	plan tests => 6;
	my @lines = get_error_output([$prog, '-X', 'db-init'], 'db-init with an existing database');
	is scalar @lines, 1, 'db-init with a database returned a single error message';
	ok -f $dbidx, 'db-init did not remove the database';
	ok ! -f $dbfirst, 'db-init did not create a first entry by itself';
	is $dbidx->slurp_utf8, "000000\n", 'db-init did not modify the database';
};

subtest 'No modules in an empty database' => sub {
	plan tests => 6;
	my @lines = get_ok_output([$prog, '-X', 'list-modules'], 'list-modules with an empty database');
	is scalar @lines, 0, 'list-modules returned nothing on an empty database';
	ok -f $dbidx, 'list-modules did not remove the database';
	ok ! -f $dbfirst, 'list-modules did not create a first entry by itself';
	is $dbidx->slurp_utf8, "000000\n", 'list-modules did not modify the database';
};
