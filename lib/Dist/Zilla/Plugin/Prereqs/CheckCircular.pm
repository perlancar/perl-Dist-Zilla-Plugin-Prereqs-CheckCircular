package Dist::Zilla::Plugin::Prereqs::CheckCircular;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
with 'Dist::Zilla::Role::InstallTool';

use App::lcpan::Call qw(call_lcpan_script);
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

    my $prereqs_hash = $self->zilla->prereqs->as_string_hash;
    my $rr_prereqs = $prereqs_hash->{runtime}{requires} // {};

    my $my_mods = $self->_list_my_modules;

    $self->log_debug(
        ["We are depending on these modules (RuntimeRequires): ".
             "%s, checking for circularity from local CPAN mirror (whether ".
             "these dependencies depend back to us)", $rr_prereqs]);
    # skip unknown modules
    my $res = call_lcpan_script(argv=>[
        "mods", "--or", "-x",
        grep {$_ ne 'perl'} keys %$rr_prereqs]);
    $self->log_fatal(["Can't lcpan mods -x: %s - %s", $res->[0], $res->[1]])
        unless $res->[0] == 200;
    my $mods = $res->[2];
    $res = call_lcpan_script(argv=>[
        "deps", "-R", @$mods]);
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

This plugin will check that the recursive dependencies of all RuntimeRequires
prereqs do not depend back on one of the distribution's modules.

Checking recursive dependencies is done using a local CPAN mirror that is
indexed by L<App::lcpan>.


=head1 SEE ALSO

L<App::lcpan>, L<lcpan>
