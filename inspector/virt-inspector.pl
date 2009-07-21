#!/usr/bin/perl -w
# virt-inspector
# Copyright (C) 2009 Red Hat Inc.
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
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

use warnings;
use strict;

use Sys::Guestfs;
use Sys::Guestfs::Lib qw(open_guest get_partitions resolve_windows_path
  inspect_all_partitions inspect_partition
  inspect_operating_systems mount_operating_system inspect_in_detail);
use Pod::Usage;
use Getopt::Long;
use Data::Dumper;
use XML::Writer;
use Locale::TextDomain 'libguestfs';

# Optional:
eval "use YAML::Any;";

=encoding utf8

=head1 NAME

virt-inspector - Display OS version, kernel, drivers, mount points, applications, etc. in a virtual machine

=head1 SYNOPSIS

 virt-inspector [--connect URI] domname

 virt-inspector guest.img [guest.img ...]

=head1 DESCRIPTION

B<virt-inspector> examines a virtual machine and tries to determine
the version of the OS, the kernel version, what drivers are installed,
whether the virtual machine is fully virtualized (FV) or
para-virtualized (PV), what applications are installed and more.

Virt-inspector can produce output in several formats, including a
readable text report, and XML for feeding into other programs.

Virt-inspector should only be run on I<inactive> virtual machines.
The program tries to determine that the machine is inactive and will
refuse to run if it thinks you are trying to inspect a running domain.

In the normal usage, use C<virt-inspector domname> where C<domname> is
the libvirt domain (see: C<virsh list --all>).

You can also run virt-inspector directly on disk images from a single
virtual machine.  Use C<virt-inspector guest.img>.  In rare cases a
domain has several block devices, in which case you should list them
one after another, with the first corresponding to the guest's
C</dev/sda>, the second to the guest's C</dev/sdb> and so on.

Virt-inspector can only inspect and report upon I<one domain at a
time>.  To inspect several virtual machines, you have to run
virt-inspector several times (for example, from a shell script
for-loop).

Because virt-inspector needs direct access to guest images, it won't
normally work over remote libvirt connections.

=head1 OPTIONS

=over 4

=cut

my $help;

=item B<--help>

Display brief help.

=cut

my $version;

=item B<--version>

Display version number and exit.

=cut

my $uri;

=item B<--connect URI> | B<-c URI>

If using libvirt, connect to the given I<URI>.  If omitted,
then we connect to the default libvirt hypervisor.

Libvirt is only used if you specify a C<domname> on the
command line.  If you specify guest block devices directly,
then libvirt is not used at all.

=cut

my $output = "text";

=back

The following options select the output format.  Use only one of them.
The default is a readable text report.

=over 4

=item B<--text> (default)

Plain text report.

=item B<--none>

Produce no output at all.

=item B<--xml>

If you select I<--xml> then you get XML output which can be fed
to other programs.

=item B<--yaml>

If you select I<--yaml> then you get YAML output which can be fed
to other programs.

=item B<--perl>

If you select I<--perl> then you get Perl structures output which
can be used directly in another Perl program.

=item B<--fish>

=item B<--ro-fish>

If you select I<--fish> then we print a L<guestfish(1)> command
line which will automatically mount up the filesystems on the
correct mount points.  Try this for example:

 guestfish $(virt-inspector --fish guest.img)

I<--ro-fish> is the same, but the I<--ro> option is passed to
guestfish so that the filesystems are mounted read-only.

=item B<--query>

In "query mode" we answer common questions about the guest, such
as whether it is fullvirt or needs a Xen hypervisor to run.

See section I<QUERY MODE> below.

=cut

my $windows_registry;

=item B<--windows-registry>

If this item is passed, I<and> the guest is Windows, I<and> the
external program C<reged> is available (see SEE ALSO section), then we
attempt to parse the Windows registry.  This allows much more
information to be gathered for Windows guests.

This is quite an expensive and slow operation, so we don't do it by
default.

=back

=cut

GetOptions ("help|?" => \$help,
	    "version" => \$version,
	    "connect|c=s" => \$uri,
	    "text" => sub { $output = "text" },
	    "none" => sub { $output = "none" },
	    "xml" => sub { $output = "xml" },
	    "yaml" => sub { $output = "yaml" },
	    "perl" => sub { $output = "perl" },
	    "fish" => sub { $output = "fish" },
	    "guestfish" => sub { $output = "fish" },
	    "ro-fish" => sub { $output = "ro-fish" },
	    "ro-guestfish" => sub { $output = "ro-fish" },
	    "query" => sub { $output = "query" },
	    "windows-registry" => \$windows_registry,
    ) or pod2usage (2);
pod2usage (1) if $help;
if ($version) {
    my $g = Sys::Guestfs->new ();
    my %h = $g->version ();
    print "$h{major}.$h{minor}.$h{release}$h{extra}\n";
    exit
}
pod2usage (__"virt-inspector: no image or VM names given") if @ARGV == 0;

my $rw = 0;
$rw = 1 if $output eq "fish";
my $g;
my @images;
if ($uri) {
    my ($conn, $dom);
    ($g, $conn, $dom, @images) =
	open_guest (\@ARGV, rw => $rw, address => $uri);
} else {
    my ($conn, $dom);
    ($g, $conn, $dom, @images) =
	open_guest (\@ARGV, rw => $rw);
}

$g->launch ();
$g->wait_ready ();

=head1 OUTPUT FORMAT

 Operating system(s)
 -------------------
 Linux (distro + version)
 Windows (version)
    |
    |
    +--- Filesystems ---------- Installed apps --- Kernel & drivers
         -----------            --------------     ----------------
         mount point => device  List of apps       Extra information
         mount point => device  and versions       about kernel(s)
              ...                                  and drivers
         swap => swap device
         (plus lots of extra information
         about each filesystem)

The output of virt-inspector is a complex two-level data structure.

At the top level is a list of the operating systems installed on the
guest.  (For the vast majority of guests, only a single OS is
installed.)  The data returned for the OS includes the name (Linux,
Windows), the distribution and version.

The diagram above shows what we return for each OS.

With the I<--xml> option the output is mapped into an XML document.
Unfortunately there is no clear schema for this document
(contributions welcome) but you can get an idea of the format by
looking at other documents and as a last resort the source for this
program.

With the I<--fish> or I<--ro-fish> option the mount points are mapped to
L<guestfish(1)> command line parameters, so that you can go in
afterwards and inspect the guest with everything mounted in the
right place.  For example:

 guestfish $(virt-inspector --ro-fish guest.img)
 ==> guestfish --ro -a guest.img -m /dev/VG/LV:/ -m /dev/sda1:/boot

=cut

# List of possible filesystems.
my @partitions = get_partitions ($g);

# Now query each one to build up a picture of what's in it.
my %fses =
    inspect_all_partitions ($g, \@partitions,
      use_windows_registry => $windows_registry);

#print "fses -----------\n";
#print Dumper(\%fses);

my $oses = inspect_operating_systems ($g, \%fses);

#print "oses -----------\n";
#print Dumper($oses);

# Mount up the disks so we can check for applications
# and kernels.  Skip this if the output is "*fish" because
# we don't need to know.

if ($output !~ /.*fish$/) {
    my $root_dev;
    foreach $root_dev (sort keys %$oses) {
	my $os = $oses->{$root_dev};
	mount_operating_system ($g, $os);
	inspect_in_detail ($g, $os);
	$g->umount_all ();
    }
}

#----------------------------------------------------------------------
# Output.

if ($output eq "fish" || $output eq "ro-fish") {
    my @osdevs = keys %$oses;
    # This only works if there is a single OS.
    die __"--fish output is only possible with a single OS\n" if @osdevs != 1;

    my $root_dev = $osdevs[0];

    if ($output eq "ro-fish") {
	print "--ro ";
    }

    print "-a $_ " foreach @images;

    my $mounts = $oses->{$root_dev}->{mounts};
    # Have to mount / first.  Luckily '/' is early in the ASCII
    # character set, so this should be OK.
    foreach (sort keys %$mounts) {
	print "-m $mounts->{$_}:$_ " if $_ ne "swap" && $_ ne "none";
    }
    print "\n"
}

# Perl output.
elsif ($output eq "perl") {
    print Dumper(%$oses);
}

# YAML output
elsif ($output eq "yaml") {
    die __"virt-inspector: no YAML support\n"
	unless exists $INC{"YAML/Any.pm"};

    print Dump(%$oses);
}

# Plain text output (the default).
elsif ($output eq "text") {
    output_text ();
}

# XML output.
elsif ($output eq "xml") {
    output_xml ();
}

# Query mode.
elsif ($output eq "query") {
    output_query ();
}

sub output_text
{
    output_text_os ($oses->{$_}) foreach sort keys %$oses;
}

sub output_text_os
{
    my $os = shift;

    print $os->{os}, " " if exists $os->{os};
    print $os->{distro}, " " if exists $os->{distro};
    print $os->{major_version} if exists $os->{major_version};
    print ".", $os->{minor_version} if exists $os->{minor_version};
    print " ";
    print "on ", $os->{root_device}, ":\n";

    print __"  Mountpoints:\n";
    my $mounts = $os->{mounts};
    foreach (sort keys %$mounts) {
	printf "    %-30s %s\n", $mounts->{$_}, $_
    }

    print __"  Filesystems:\n";
    my $filesystems = $os->{filesystems};
    foreach (sort keys %$filesystems) {
	print "    $_:\n";
	print "      label: $filesystems->{$_}{label}\n"
	    if exists $filesystems->{$_}{label};
	print "      UUID: $filesystems->{$_}{uuid}\n"
	    if exists $filesystems->{$_}{uuid};
	print "      type: $filesystems->{$_}{fstype}\n"
	    if exists $filesystems->{$_}{fstype};
	print "      content: $filesystems->{$_}{content}\n"
	    if exists $filesystems->{$_}{content};
    }

    if (exists $os->{modprobe_aliases}) {
	my %aliases = %{$os->{modprobe_aliases}};
	my @keys = sort keys %aliases;
	if (@keys) {
	    print __"  Modprobe aliases:\n";
	    foreach (@keys) {
		printf "    %-30s %s\n", $_, $aliases{$_}->{modulename}
	    }
	}
    }

    if (exists $os->{initrd_modules}) {
	my %modvers = %{$os->{initrd_modules}};
	my @keys = sort keys %modvers;
	if (@keys) {
	    print __"  Initrd modules:\n";
	    foreach (@keys) {
		my @modules = @{$modvers{$_}};
		print "    $_:\n";
		print "      $_\n" foreach @modules;
	    }
	}
    }

    print __"  Applications:\n";
    my @apps =  @{$os->{apps}};
    foreach (@apps) {
	print "    $_->{name} $_->{version}\n"
    }

    print __"  Kernels:\n";
    my @kernels = @{$os->{kernels}};
    foreach (@kernels) {
	print "    $_->{version}\n";
	my @modules = @{$_->{modules}};
	foreach (@modules) {
	    print "      $_\n";
	}
    }

    if (exists $os->{root}->{registry}) {
	print __"  Windows Registry entries:\n";
	# These are just lumps of text - dump them out.
	foreach (@{$os->{root}->{registry}}) {
	    print "$_\n";
	}
    }
}

sub output_xml
{
    my $xml = new XML::Writer(DATA_MODE => 1, DATA_INDENT => 2);

    $xml->startTag("operatingsystems");
    output_xml_os ($oses->{$_}, $xml) foreach sort keys %$oses;
    $xml->endTag("operatingsystems");

    $xml->end();
}

sub output_xml_os
{
    my ($os, $xml) = @_;

    $xml->startTag("operatingsystem");

    foreach ( [ "name" => "os" ],
              [ "distro" => "distro" ],
              [ "major_version" => "major_version" ],
              [ "minor_version" => "minor_version" ],
              [ "package_format" => "package_format" ],
              [ "package_management" => "package_management" ],
              [ "root" => "root_device" ] ) {
        $xml->dataElement($_->[0], $os->{$_->[1]}) if exists $os->{$_->[1]};
    }

    $xml->startTag("mountpoints");
    my $mounts = $os->{mounts};
    foreach (sort keys %$mounts) {
        $xml->dataElement("mountpoint", $_, "dev" => $mounts->{$_});
    }
    $xml->endTag("mountpoints");

    $xml->startTag("filesystems");
    my $filesystems = $os->{filesystems};
    foreach (sort keys %$filesystems) {
        $xml->startTag("filesystem", "dev" => $_);

        foreach my $field ( [ "label" => "label" ],
                            [ "uuid" => "uuid" ],
                            [ "type" => "fstype" ],
                            [ "content" => "content" ],
                            [ "spec" => "spec" ] ) {
            $xml->dataElement($field->[0], $filesystems->{$_}{$field->[1]})
                if exists $filesystems->{$_}{$field->[1]};
        }

        $xml->endTag("filesystem");
    }
    $xml->endTag("filesystems");

    if (exists $os->{modprobe_aliases}) {
	my %aliases = %{$os->{modprobe_aliases}};
	my @keys = sort keys %aliases;
	if (@keys) {
            $xml->startTag("modprobealiases");
	    foreach (@keys) {
                $xml->startTag("alias", "device" => $_);

                foreach my $field ( [ "modulename" => "modulename" ],
                                    [ "augeas" => "augeas" ],
                                    [ "file" => "file" ] ) {
                    $xml->dataElement($field->[0], $aliases{$_}->{$field->[1]});
                }

                $xml->endTag("alias");
	    }
            $xml->endTag("modprobealiases");
	}
    }

    if (exists $os->{initrd_modules}) {
	my %modvers = %{$os->{initrd_modules}};
	my @keys = sort keys %modvers;
	if (@keys) {
            $xml->startTag("initrds");
	    foreach (@keys) {
		my @modules = @{$modvers{$_}};
                $xml->startTag("initrd", "version" => $_);
                $xml->dataElement("module", $_) foreach @modules;
                $xml->endTag("initrd");
	    }
            $xml->endTag("initrds");
	}
    }

    $xml->startTag("applications");
    my @apps =  @{$os->{apps}};
    foreach (@apps) {
        $xml->startTag("application");
        $xml->dataElement("name", $_->{name});
        $xml->dataElement("version", $_->{version});
        $xml->endTag("application");
    }
    $xml->endTag("applications");

    $xml->startTag("kernels");
    my @kernels = @{$os->{kernels}};
    foreach (@kernels) {
        $xml->startTag("kernel", "version" => $_->{version});
        $xml->startTag("modules");
	my @modules = @{$_->{modules}};
	foreach (@modules) {
            $xml->dataElement("module", $_);
	}
        $xml->endTag("modules");
        $xml->endTag("kernel");
    }
    $xml->endTag("kernels");

    if (exists $os->{root}->{registry}) {
        $xml->startTag("windowsregistryentries");
	# These are just lumps of text - dump them out.
	foreach (@{$os->{root}->{registry}}) {
            $xml->dataElement("windowsregistryentry", $_);
	}
        $xml->endTag("windowsregistryentries");
    }

    $xml->endTag("operatingsystem");
}

=head1 QUERY MODE

When you use C<virt-inspector --query>, the output is a series of
lines of the form:

 windows=no
 linux=yes
 fullvirt=yes
 xen_pv_drivers=no

(each answer is usually C<yes> or C<no>, or the line is completely
missing if we could not determine the answer at all).

If the guest is multiboot, you can get apparently conflicting answers
(eg. C<windows=yes> and C<linux=yes>, or a guest which is both
fullvirt and has a Xen PV kernel).  This is normal, and just means
that the guest can do both things, although it might require operator
intervention such as selecting a boot option when the guest is
booting.

This section describes the full range of answers possible.

=over 4

=cut

sub output_query
{
    output_query_windows ();
    output_query_linux ();
    output_query_rhel ();
    output_query_fedora ();
    output_query_debian ();
    output_query_fullvirt ();
    output_query_xen_domU_kernel ();
    output_query_xen_pv_drivers ();
    output_query_virtio_drivers ();
}

=item windows=(yes|no)

Answer C<yes> if Microsoft Windows is installed in the guest.

=cut

sub output_query_windows
{
    my $windows = "no";
    foreach my $os (keys %$oses) {
	$windows="yes" if $oses->{$os}->{os} eq "windows";
    }
    print "windows=$windows\n";
}

=item linux=(yes|no)

Answer C<yes> if a Linux kernel is installed in the guest.

=cut

sub output_query_linux
{
    my $linux = "no";
    foreach my $os (keys %$oses) {
	$linux="yes" if $oses->{$os}->{os} eq "linux";
    }
    print "linux=$linux\n";
}

=item rhel=(yes|no)

Answer C<yes> if the guest contains Red Hat Enterprise Linux.

=cut

sub output_query_rhel
{
    my $rhel = "no";
    foreach my $os (keys %$oses) {
	$rhel="yes" if ($oses->{$os}->{os} eq "linux" &&
                        $oses->{$os}->{distro} eq "rhel");
    }
    print "rhel=$rhel\n";
}

=item fedora=(yes|no)

Answer C<yes> if the guest contains the Fedora Linux distribution.

=cut

sub output_query_fedora
{
    my $fedora = "no";
    foreach my $os (keys %$oses) {
	$fedora="yes" if $oses->{$os}->{os} eq "linux" && $oses->{$os}->{distro} eq "fedora";
    }
    print "fedora=$fedora\n";
}

=item debian=(yes|no)

Answer C<yes> if the guest contains the Debian Linux distribution.

=cut

sub output_query_debian
{
    my $debian = "no";
    foreach my $os (keys %$oses) {
	$debian="yes" if $oses->{$os}->{os} eq "linux" && $oses->{$os}->{distro} eq "debian";
    }
    print "debian=$debian\n";
}

=item fullvirt=(yes|no)

Answer C<yes> if there is at least one operating system kernel
installed in the guest which runs fully virtualized.  Such a guest
would require a hypervisor which supports full system virtualization.

=cut

sub output_query_fullvirt
{
    # The assumption is full-virt, unless all installed kernels
    # are identified as paravirt.
    # XXX Fails on Windows guests.
    foreach my $os (keys %$oses) {
	foreach my $kernel (@{$oses->{$os}->{kernels}}) {
	    my $is_pv = $kernel->{version} =~ m/xen/;
	    unless ($is_pv) {
		print "fullvirt=yes\n";
		return;
	    }
	}
    }
    print "fullvirt=no\n";
}

=item xen_domU_kernel=(yes|no)

Answer C<yes> if there is at least one Linux kernel installed in
the guest which is compiled as a Xen DomU (a Xen paravirtualized
guest).

=cut

sub output_query_xen_domU_kernel
{
    foreach my $os (keys %$oses) {
	foreach my $kernel (@{$oses->{$os}->{kernels}}) {
	    my $is_xen = $kernel->{version} =~ m/xen/;
	    if ($is_xen) {
		print "xen_domU_kernel=yes\n";
		return;
	    }
	}
    }
    print "xen_domU_kernel=no\n";
}

=item xen_pv_drivers=(yes|no)

Answer C<yes> if the guest has Xen paravirtualized drivers installed
(usually the kernel itself will be fully virtualized, but the PV
drivers have been installed by the administrator for performance
reasons).

=cut

sub output_query_xen_pv_drivers
{
    foreach my $os (keys %$oses) {
	foreach my $kernel (@{$oses->{$os}->{kernels}}) {
	    foreach my $module (@{$kernel->{modules}}) {
		if ($module =~ m/xen-/) {
		    print "xen_pv_drivers=yes\n";
		    return;
		}
	    }
	}
    }
    print "xen_pv_drivers=no\n";
}

=item virtio_drivers=(yes|no)

Answer C<yes> if the guest has virtio paravirtualized drivers
installed.  Virtio drivers are commonly used to improve the
performance of KVM.

=cut

sub output_query_virtio_drivers
{
    foreach my $os (keys %$oses) {
	foreach my $kernel (@{$oses->{$os}->{kernels}}) {
	    foreach my $module (@{$kernel->{modules}}) {
		if ($module =~ m/virtio_/) {
		    print "virtio_drivers=yes\n";
		    return;
		}
	    }
	}
    }
    print "virtio_drivers=no\n";
}

=back

=head1 SEE ALSO

L<guestfs(3)>,
L<guestfish(1)>,
L<Sys::Guestfs(3)>,
L<Sys::Guestfs::Lib(3)>,
L<Sys::Virt(3)>,
L<http://libguestfs.org/>.

For Windows registry parsing we require the C<reged> program
from L<http://home.eunet.no/~pnordahl/ntpasswd/>.

=head1 AUTHOR

Richard W.M. Jones L<http://et.redhat.com/~rjones/>

Matthew Booth L<mbooth@redhat.com>

=head1 COPYRIGHT

Copyright (C) 2009 Red Hat Inc.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
