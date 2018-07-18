# txn-install

The `txn` utility helps automated deployment systems keep track of changes
made to files and, later, roll those changes back, e.g. when uninstalling
a module.  While some of its functionality (keeping track of newly-installed
files) is similar to that of a package management system, its true goal is to
record modifications made to e.g. configuration files; most package management
systems run into problems when different packages try to modify the same file.
The `txn` utility will use the `diff` tool to store a patch into its internal
database and, later, when asked to roll the change back, will invoke
the `patch` tool to revert it.

## Examples

Initialize the database once after installing the `txn` utility:

    txn db-init

Record the installation (or modification) of a configuration file:

    env TXN_INSTALL_MODULE=p1 txn install -c -o root -g root -m 644 /tmp/sources.12131 /etc/apt/sources.list.d/vendor.list

Record a modification of an existing file, contents only, no metadata change:

    env TXN_INSTALL_MODULE=p1 txn install-exact /tmp/hosts.32784 /etc/hosts

Record the removal of an existing file:

    env TXN_INSTALL_MODULE=p2 txn remove /etc/grub.d/10_linux

List the modules that have performed changes (after these commands, this would
output "p1" and "p2"):

    txn list-modules

Revert any changes performed by a module, removing all of its entries from
the `txn` database:

    txn rollback p1

## Contact

The `txn` utility was written by [Peter Pentchev][roam] for
[StorPool][storpool].

[roam]: mailto:pp@storpool.com
[storpool]: https://storpool.com/
