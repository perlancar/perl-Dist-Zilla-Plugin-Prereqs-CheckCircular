package Dist::Zilla::Plugin::Prereqs::CheckCircular;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
with 'Dist::Zilla::Role::InstallTool';

use App::lcpan::Call qw(call_lcpan_script check_lcpan);
use namespace::autoclean;

sub _list_my_modules {
    my ($self) = @_;

    my %res;
    for my $file (@{ $self->zilla->files }) {
        my $name = $file->name;
        next unless $name =~ m!^lib/(.+)\.pm$!;
        $name = $1; $name =~ s!/!::!g;
        $res{$name} = 0;
    }
    \%res;
}

sub setup_installer {
    my ($self) = @_;

    if ($ENV{DZIL_CHECKCIRCULAR_SKIP}) {
        $self->log(["Skipping checking circular dependency because ".
                        "environment DZIL_CHECKCIRCULAR_SKIP is set to true"]);
        return;
    }

    my $lcpan_check = check_lcpan();
    unless ($lcpan_check->[0] == 200) {
        $self->log(["Skipping checking circular dependency because ".
                        "check_lcpan() was not successful: " .
                            $lcpan_check->[1]]);
        return;
    }

    my $prereqs_hash = $self->zilla->prereqs->as_string_hash;
    my $rr_prereqs = $prereqs_hash->{runtime}{requires} // {};
    my @prereqs = grep { $_ ne 'perl' } sort keys %$rr_prereqs;
    return unless @prereqs;

    my $my_mods = $self->_list_my_modules;

    # since this can take several seconds, we log at non-debug level to show
    # message to user
    $self->log(
        ["We are depending on these modules (RuntimeRequires): ".
             "%s, checking for circularity from local CPAN mirror (whether ".
                 "these dependencies depend back to us)", \@prereqs]);

    # skip unknown modules
    my $res = call_lcpan_script(argv=>["mods", "--or", "-x", @prereqs]);
    $self->log_fatal(["Can't lcpan mods -x: %s - %s", $res->[0], $res->[1]])
        unless $res->[0] == 200;
    my $mods = $res->[2];

    $res = call_lcpan_script(argv=>["deps", "-R", @$mods]);
    $self->log_fatal(["Can't lcpan deps: %s - %s", $res->[0], $res->[1]])
        unless $res->[0] == 200;
    for my $entry (@{$res->[2]}) {
        my $mod = $entry->{module};
        $mod =~ s/^\s+//;
        next if $mod eq 'perl';
        if (exists $my_mods->{$mod}) {
            $self->log_fatal(["Circular dependency detected: one of our ".
                                  "dependencies depend back on one of our ".
                                  "modules: %s", $mod]);
        }
    }
}

__PACKAGE__->meta->make_immutable;
1;
# ABSTRACT: Check for circular/recursive dependencies (using local CPAN mirror)

=for Pod::Coverage .+

=head1 SYNOPSIS

In F<dist.ini>:

 [Prereqs::CheckCircular]


=head1 DESCRIPTION

This plugin will check that there is no circular dependency being formed. This
is done by: collecting all RuntimeRequires prereqs of the distribution, then
feeding them to L<App::lcpan> to get the recursive dependencies of those
prereqs. If one of those dependencies is one of the distribution's modules, then
we have a circular dependency and the build is aborted.


=head1 ENVIRONMENT

=head2 DZIL_CHECKCIRCULAR_SKIP => bool

Can be set to 1 to skip checking circular dependency.


=head1 SEE ALSO

L<App::lcpan>, L<lcpan>
