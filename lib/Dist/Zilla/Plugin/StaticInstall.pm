use strict;
use warnings;
package Dist::Zilla::Plugin::StaticInstall;
# ABSTRACT: Identify a distribution as eligible for static installation
# KEYWORDS: distribution metadata toolchain static dynamic installation
# vim: set ts=8 sts=4 sw=4 tw=115 et :

our $VERSION = '0.002';

use Moose;
with 'Dist::Zilla::Role::MetaProvider';

use Moose::Util::TypeConstraints;
use MooseX::Types::Moose 'Str';
use namespace::autoclean;

my $mode_type = enum([qw(off on auto)]);
coerce $mode_type, from Str, via { $_ eq '0' ? 'off' : $_ eq '1' ? 'on' : $_ };
has mode => (
    is => 'ro', isa => $mode_type,
    default => 'on',
    coerce => 1,
);

around dump_config => sub
{
    my ($orig, $self) = @_;
    my $config = $self->$orig;

    $config->{+__PACKAGE__} = {
        mode => $self->mode,
    };

    return $config;
};

sub metadata
{
    my $self = shift;
    my $mode = $self->mode;
    return +{ x_static_install => 0 } if $mode eq 'off';
    return +{ x_static_install => 1 } if $mode eq 'on';

    # we'll calculate this value later in the build and munge it in
    $self->log_fatal('auto mode is not yet supported');
}

__PACKAGE__->meta->make_immutable;
__END__

=pod

=head1 SYNOPSIS

In your F<dist.ini>:

    [StaticInstall]
    mode = on

=head1 DESCRIPTION

This is a L<Dist::Zilla> plugin that, when C<mode> is C<on>, provides the following distribution metadata:

    x_static_install : "1"

The definition of a "static installation" is still being refined by the Perl
Toolchain Gang. Use with discretion!

=head1 CONFIGURATION OPTIONS

=head2 C<mode>

=for stopwords usecase

When set to C<on>, the value of C<x_static_install> is set to 1 (the normal usecase).

When set to C<off>, the value of C<x_static_install> is set to 0, which is
equivalent to not providing this field at all.

(Coming in a later release: support for C<mode = auto>, which will determine
the value of this field automatically; also warnings or fatal errors when the
flag is being used incorrectly.)

=for Pod::Coverage metadata

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-StaticInstall>
(or L<bug-Dist-Zilla-Plugin-StaticInstall@rt.cpan.org|mailto:bug-Dist-Zilla-Plugin-StaticInstall@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 SEE ALSO

=for :list
* L<CPAN::Meta::Spec>

=cut
