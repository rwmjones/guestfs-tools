#!/bin/bash -
# libguestfs
# Copyright (C) 2013 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# https://bugzilla.redhat.com/show_bug.cgi?id=563450
# Test the order of added images

set -e
export LANG=C

if [ ! -s ../guests/fedora.img -o ! -s ../data/test.iso -o ! -s ../guests/debian.img ]; then
    echo "$0: test skipped because there is no fedora.img nor test.iso nor debian.img"
    exit 77
fi

rm -f test.out

../../fish/guestfish --ro > test.out <<EOF
add-drive-ro ../guests/fedora.img
add-cdrom ../data/test.iso
add-drive-ro ../guests/debian.img

run

list-devices
echo ----
list-partitions

ping-daemon
EOF

if [ "$(cat test.out)" != "/dev/sda
/dev/sdb
/dev/sdc
----
/dev/sda1
/dev/sda2
/dev/sdc1
/dev/sdc2" ]; then
    echo "$0: unexpected output:"
    cat test.out
    exit 1
fi

rm -f test.out
