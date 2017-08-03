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

my $prog = $ENV{TEST_PROG} // './txn';
my $prog_abs = path($prog)->absolute;

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

my ($cmd_in_filename, $tempd, $dbdir, $dbidx);

sub prog($)
{
	my ($cmd) = @_;

	if ($cmd_in_filename) {
		my $path = $tempd->child("txn-$cmd");
		if (!$path->is_file) {
			if (!symlink($prog_abs, $path)) {
				BAIL_OUT("Could not symlink '$prog_abs' to '$path': $!");
			}
		}
		return $path;
	} else {
		return ($prog, $cmd);
	}
}

sub none_exist(@)
{
	for my $idx (@_) {
		my $fname = $dbdir->child(sprintf('txn.%06d', $idx));
		return 0 if $fname->exists;
	}
	return 1;
}

sub all_exist(@)
{
	for my $idx (@_) {
		my $fname = $dbdir->child(sprintf('txn.%06d', $idx));
		return 0 unless $fname->exists;
	}
	return 1;
}

sub split_index(@)
{
	my @contents = split /\n/, $dbidx->slurp_utf8, -1;
	BAIL_OUT("Invalid empty database index $dbidx") unless @contents;
	my $last = pop @contents;
	BAIL_OUT("Invalid database index $dbidx: no EOL at EOF") unless $last eq '';
	return @contents;
}

sub index_add_line($ $)
{
	my ($contents, $line) = @_;

	my $last = pop @{$contents};

	my $next = $last;
	$next =~ s/^0*//;
	$next = 0 if $next eq "";
	$next = sprintf("%06d", $next + 1);

	$last .= " $line";
	push @{$contents}, $last, $next;
}

sub index_roll_module_back($ $)
{
	my ($contents, $module) = @_;

	my @new;
	for my $line (@{$contents}) {
		my @fields = split / /, $line, 4;
		if (@fields == 1) {
			push @new, $line;
			next;
		} elsif (@fields != 4) {
			BAIL_OUT("Rolling back '$line': expected four fiels");
		}
		my ($idx, $mod, $action, $fname) = @fields;
		if ($mod ne $module) {
			push @new, $line;
			next;
		}

		$action = "un$action";
		if (length($fname) < 2) {
			BAIL_OUT("Rolling back '$line': filename too short");
		}
		$fname = substr($fname, 2);
		push @new, "$idx $mod $action $fname";
	}

	@{$contents} = @new;
}

plan tests => 2;

for my $cmd_in_filename_value (0, 1) {
	$cmd_in_filename = $cmd_in_filename_value;
	my $test_name = ($cmd_in_filename ? '' : 'no ').'cmd in filename';
	subtest $test_name => sub {
		plan tests => 20;

		my $tempdir = tempdir(CLEANUP => 1);
		$tempd = path($tempdir);
		my $data = $tempd->child('data');
		$dbdir = $tempd->child('db');
		$dbidx = $dbdir->child('txn.index');
		my $last_entry = 4;
		my @index_contents = ('000000');

		$data->mkpath({ mode => 0755 });
		$dbdir->mkpath({ mode => 0755 });
		$ENV{'TXN_INSTALL_DB'} = $dbdir;

		subtest 'Error out without a database' => sub {
			plan tests => 5;
			my @lines = get_error_output([prog('list-modules')], 'list-modules without a database');
			is scalar @lines, 1, 'list-modules without a database returned a single error message';
			ok ! -f $dbidx, 'list-modules did not create a database by itself';
			ok none_exist(0..$last_entry), 'list-modules did not create any entries';
		};

		subtest 'Initialize a database' => sub {
			plan tests => 6;
			my @lines = get_ok_output([prog('db-init')], 'db-init');
			is scalar @lines, 0, 'db-init did not return any output';
			ok -f $dbidx, 'db-init created a database';
			ok none_exist(0..$last_entry), 'db-init did not create any entries';
			is_deeply [split_index], \@index_contents, 'db-init created an empty database';
		};

		subtest 'Do not reinitialize a database' => sub {
			plan tests => 6;
			my @lines = get_error_output([prog('db-init')], 'db-init with an existing database');
			is scalar @lines, 1, 'db-init with a database returned a single error message';
			ok -f $dbidx, 'db-init did not remove the database';
			ok none_exist(0..$last_entry), 'db-init did not create any entries';
			is_deeply [split_index], \@index_contents, 'db-index did not modify the database';
		};

		subtest 'No modules in an empty database' => sub {
			plan tests => 6;
			my @lines = get_ok_output([prog('list-modules')], 'list-modules with an empty database');
			is scalar @lines, 0, 'list-modules returned nothing on an empty database';
			ok -f $dbidx, 'list-modules did not remove the database';
			ok none_exist(0..$last_entry), 'list-modules did not create any entries';
			is_deeply [split_index], \@index_contents, 'list-modules did not modify the database';
		};

		subtest 'Fail to install a nonexistent file' => sub {
			plan tests => 6;

			$ENV{'TXN_INSTALL_MODULE'} = 'something';
			my @lines = get_error_output([prog('install'), '-c', '-m', '644', $data->child('nonexistent'), $data->child('target')], 'list-modules with an empty database');

			ok ! -e $data->child('nonexistent'), 'install did not create a nonexistent source file';
			ok ! -e $data->child('target'), 'install nonexistent did not create the target';

			ok none_exist(0..$last_entry), 'install nonexistent did not create any entries';
			is_deeply [split_index], \@index_contents, 'install nonexistent did not modify the database';
		};

		subtest 'Install something' => sub {
			plan tests => 8;

			my $src = $data->child('source-1.txt');
			my $tgt = $data->child('target-1.txt');
			$src->spew_utf8("This is a test.\n");
			ok -f $src, 'a simple file was created';

			$ENV{'TXN_INSTALL_MODULE'} = 'something';
			my @lines = get_ok_output([prog('install'), '-c', '-m', '644', $src, $tgt], 'install/create with an empty database');
			is scalar @lines, 0, 'install/create did not output anything';

			ok -f $src, 'install/create did not remove the source file';
			ok -f $tgt, 'install/create created the target file';

			ok none_exist(0..$last_entry), 'install/create did not create any entries';
			index_add_line(\@index_contents, "something create $tgt");
			is_deeply [split_index], \@index_contents, 'install/create updated the index';
		};

		subtest 'Now modify the installed something' => sub {
			plan tests => 9;

			my $src = $data->child('source-1.txt');
			my $tgt = $data->child('target-1.txt');
			$src->spew_utf8($src->slurp_utf8 . "This is only a test.\n");
			ok -f $src, 'a simple file was modified';

			$ENV{'TXN_INSTALL_MODULE'} = 'something';
			my @lines = get_ok_output([prog('install'), '-c', '-m', '644', $src, $tgt], 'install/patch');
			is scalar @lines, 0, 'install/patch did not output anything';

			ok -f $src, 'install/patch did not remove the source file';
			ok -f $tgt, 'install/patch created the target file';

			ok none_exist(0, 2..$last_entry), 'install/patch did not create a first entry';
			ok all_exist(1), 'install/patch created a second entry';
			index_add_line(\@index_contents, "something patch $tgt");
			is_deeply [split_index], \@index_contents, 'install/patch updated the index';
		};

		subtest 'A wild module appears' => sub {
			plan tests => 6;
			my @lines = get_ok_output([prog('list-modules')], 'list-modules with an empty database');
			is_deeply \@lines, ['something'], 'list-modules returned the single module name';
			ok none_exist(0, 2..$last_entry), 'list-modules did not create a first entry';
			ok all_exist(1), 'list-modules did not remove the second entry';
			is_deeply [split_index], \@index_contents, 'list-modules did not modify the database';
		};

		subtest 'Install a binary file' => sub {
			plan tests => 9;

			my $src = path('/bin/sh');
			my $tgt = $data->child('target-2.txt');
			ok -f $src, 'there is a /bin/sh on this system';

			$ENV{'TXN_INSTALL_MODULE'} = 'shell';
			my @lines = get_ok_output([prog('install'), '-c', '-m', '755', $src, $tgt], 'install/create/bin');
			is scalar @lines, 0, 'install/create/bin did not output anything';

			ok -f $src, 'install/create/bin did not remove the source file';
			ok -f $tgt, 'install/create/bin created the target file';

			ok none_exist(0, 2..$last_entry), 'install/create/bin did not create any entries';
			ok all_exist(1), 'install/create/bin did not remove the second entry';
			index_add_line(\@index_contents, "shell create $tgt");
			is_deeply [split_index], \@index_contents, 'install/create/bin updated the index';
		};

		subtest 'Recreate a binary file' => sub {
			plan tests => 9;

			my $src = path('/bin/cat');
			my $tgt = $data->child('target-2.txt');
			ok -f $src, 'there is a /bin/cat on this system';

			$ENV{'TXN_INSTALL_MODULE'} = 'shell';
			my @lines = get_ok_output([prog('install'), '-c', '-m', '755', $src, $tgt], 'install/recreate/bin');
			is scalar @lines, 0, 'install/recreate/bin did not output anything';

			ok -f $src, 'install/recreate/bin did not remove the source file';
			ok -f $tgt, 'install/recreate/bin created the target file';

			ok none_exist(0, 2..$last_entry), 'install/recreate/bin did not create any entries';
			ok all_exist(1), 'install/recreate/bin did not remove the second entry';
			index_add_line(\@index_contents, "shell create $tgt");
			is_deeply [split_index], \@index_contents, 'install/recreate/bin updated the index';
		};

		subtest 'Remove a nonexistent file' => sub {
			plan tests => 8;

			my $tgt = $data->child('nonexistent.txt');
			ok !$tgt->exists, 'a nonexistent file does not exist';

			$ENV{'TXN_INSTALL_MODULE'} = 'removal';
			my @lines = get_error_output([prog('remove'), $tgt], 'remove/nonexistent');
			is scalar @lines, 1, 'remove/nonexistent output a single error message';

			ok !$tgt->exists, 'remove/nonexistent did not create the target file';

			ok none_exist(0, 2..$last_entry), 'remove/nonexistent did not create any entries';
			ok all_exist(1), 'remove/nonexistent did not remove the second entry';
			is_deeply [split_index], \@index_contents, 'remove/nonexistent did not modify the index';
		};

		subtest 'Remove an existing file' => sub {
			plan tests => 8;

			my $tgt = $data->child('removed.txt');
			$tgt->spew_utf8("Another test, I guess...\n");
			ok $tgt->is_file, 'a simple file was created';

			$ENV{'TXN_INSTALL_MODULE'} = 'removal';
			my @lines = get_ok_output([prog('remove'), $tgt], 'remove');
			is scalar @lines, 0, 'remove did not output anything';

			ok !$tgt->exists, 'remove removed the target file';

			ok none_exist(0, 2, 3, 5..$last_entry), 'remove/nonexistent did not create any unexpected entries';
			ok all_exist(1, 4), 'remove/nonexistent created a fourth entry';
			index_add_line(\@index_contents, "removal remove $tgt");
			is_deeply [split_index], \@index_contents, 'remove/nonexistent updated the index';
		};

		subtest 'Abort a failed removal' => sub {
			plan tests => 11;

			my $tgtdir = $data->child('newdir');
			ok $tgtdir->mkpath({ mode => 0755 }) == 1, 'a directory was created';
			my $tgt = $tgtdir->child('newfile.txt');
			$tgt->spew_utf8("Are you looking at me?\n");

			ok -f $tgt, 'a simple file was created';

			ok $tgtdir->chmod(0), 'the directory was made inaccessible';

			$ENV{'TXN_INSTALL_MODULE'} = 'removal';
			my @lines = get_error_output([prog('remove'), $tgt], 'remove/inaccessible');
			is scalar @lines, 1, 'remove/inaccessible output a single error message';

			ok $tgtdir->chmod(0755), 'the directory was made accessible again';

			ok -f $tgt, 'remove/inaccessible did not remove the target file';

			ok none_exist(0, 2, 3, 5..$last_entry), 'remove/nonexistent did not create any entries';
			ok all_exist(1, 4), 'remove/nonexistent did not remove any existing entries';
			is_deeply [split_index], \@index_contents, 'remove/nonexistent did not modify the index';
		};

		subtest 'Abort a failed installation' => sub {
			if ($> == 0) {
				plan skip_all => 'Do not know how to do a failed installation as root';
				return;
			}
			plan tests => 11;

			my $src = $data->child('source-3.txt');
			$src->spew_utf8("Well, *are* you looking at me?\n");
			my $tgtdir = $data->child('newdir-2');
			ok $tgtdir->mkpath({ mode => 0755 }) == 1, 'a directory was created';
			my $tgt = $tgtdir->child('newfile.txt');

			ok -f $src, 'a simple file was created';
			ok ! -f $tgt, 'a nonexistent file does not exist';

			$ENV{'TXN_INSTALL_MODULE'} = 'noninstall';
			my @lines = get_error_output([prog('install'), '-o', 'root', $src, $tgt], 'install/inaccessible');
			ok @lines, 'install/inaccessible output some error messages';

			ok -f $src, 'install/inaccessible did not remove the source file';
			ok -f $tgt, 'install/inaccessible created the target file before failing';

			ok none_exist(0, 2, 3, 5..$last_entry), 'install/nonexistent did not create any entries';
			ok all_exist(1, 4), 'install/nonexistent did not remove any existing entries';
			is_deeply [split_index], \@index_contents, 'install/nonexistent did not modify the index';
		};

		subtest 'Roll something back' => sub {
			plan tests => 12;

			my $to_remove = $data->child('target-1.txt');
			my $to_stay = $data->child('target-2.txt');
			my $to_stay_removed = $data->child('removed.txt');

			ok -f $to_remove, 'the rollback target is there';
			ok -f $to_stay, 'the unaffected target is there';
			ok ! -f $to_stay_removed, 'the removed file is not there';

			my @lines = get_ok_output([prog('rollback'), 'something'], 'roll something back');
			ok @lines == 0, 'rollback did not output anything';

			ok ! -f $to_remove, 'the rollback target is no longer there';
			ok -f $to_stay, 'the unaffected target is still there';
			ok ! -f $to_stay_removed, 'the removed file is still not there';

			ok none_exist(0..3, 5..$last_entry), 'rollback rolled back the patch entry';
			ok all_exist(4), 'rollback did not remove any other entries';
			index_roll_module_back \@index_contents, 'something';
			is_deeply [split_index], \@index_contents, 'rollback updated the index';
		};

		subtest 'No something, just removal in modules' => sub {
			plan tests => 6;
			my @lines = get_ok_output([prog('list-modules')], 'list-modules after rolling back');
			is_deeply \@lines, ['shell', 'removal'], 'list-modules returned the single module name';
			ok none_exist(0..3, 5..$last_entry), 'list-modules did not create any entries';
			ok all_exist(4), 'rollback did not remove any entries';
			is_deeply [split_index], \@index_contents, 'list-modules did not modify the database';
		};

		subtest 'Try to remove the same module again' => sub {
			plan tests => 12;

			my $to_remove = $data->child('target-1.txt');
			my $to_stay = $data->child('target-2.txt');
			my $to_stay_removed = $data->child('removed.txt');

			ok ! -f $to_remove, 'the rollback target is not there';
			ok -f $to_stay, 'the unaffected target is there';
			ok ! -f $to_stay_removed, 'the removed file is not there';

			my @lines = get_ok_output([prog('rollback'), 'something'], 'roll something back');
			ok @lines == 0, 'rollback did not output anything';

			ok ! -f $to_remove, 'the rollback target is still not there';
			ok -f $to_stay, 'the unaffected target is still there';
			ok ! -f $to_stay_removed, 'the removed file is still not there';

			ok none_exist(0..3, 5..$last_entry), 'rollback did not create any entries';
			ok all_exist(4), 'rollback did not remove any entries';
			is_deeply [split_index], \@index_contents, 'rollback did not modify the index';
		};

		subtest 'Roll back a file removal' => sub {
			plan tests => 11;

			my $to_stay_removed = $data->child('target-1.txt');
			my $to_stay = $data->child('target-2.txt');
			my $to_reappear = $data->child('removed.txt');

			ok ! -f $to_stay_removed, 'the removed file is not there';
			ok -f $to_stay, 'the unaffected target is there';
			ok ! -f $to_reappear, 'the rollback target is not there';

			my @lines = get_ok_output([prog('rollback'), 'removal'], 'roll a file removal back');
			ok @lines == 0, 'rollback did not output anything';

			ok ! -f $to_stay_removed, 'the removed file is still not there';
			ok -f $to_stay, 'the unaffected target is still there';
			ok -f $to_reappear, 'the rollback target reappeared';

			ok none_exist(0..$last_entry), 'rollback removed the file removal entry';
			index_roll_module_back \@index_contents, 'removal';
			is_deeply [split_index], \@index_contents, 'rollback did not modify the index';
		};

		subtest 'Fail to install-exact a nonexistent source file' => sub {
			plan tests => 6;

			$ENV{'TXN_INSTALL_MODULE'} = 'exact';
			my @lines = get_error_output([prog('install-exact'), $data->child('nonexistent'), $data->child('target')], 'install-exact/nonexistent');

			ok ! -e $data->child('nonexistent'), 'install-exact/nonexistent did not create a nonexistent source file';
			ok ! -e $data->child('target'), 'install-exact/nonexistent did not create the target';

			ok none_exist(0..$last_entry), 'install-exact/nonexistent did not create any new entries';
			is_deeply [split_index], \@index_contents, 'install-exact/nonexistent did not modify the database';
		};

		subtest 'Install something exactly as it is' => sub {
			plan tests => 11;

			my $src = $data->child('source-1.txt');
			my $tgt = $data->child('target-1.txt');
			$src->spew_utf8("This is a test.\n");
			ok -f $src, 'a simple file was created';
			ok chmod(0602, $src) == 1, 'the permissions mode of the simple file was set';

			$ENV{'TXN_INSTALL_MODULE'} = 'something';
			my @lines = get_ok_output([prog('install-exact'), $src, $tgt], 'install-exact/create');
			is scalar @lines, 0, 'install-exact/create did not output anything';

			ok -f $src, 'install-exact/create did not remove the source file';
			ok -f $tgt, 'install-exact/create created the target file';
			my @sbuf = stat $tgt;
			ok @sbuf, 'install-exact/create actually created the target file';
			is $sbuf[2] & 03777, 0602, 'install-exact/create set the correct permissions mode';

			ok none_exist(0..$last_entry), 'install-exact/create did not create any entries';
			index_add_line(\@index_contents, "something create $tgt");
			is_deeply [split_index], \@index_contents, 'install/create updated the index';
		};
	};
}
