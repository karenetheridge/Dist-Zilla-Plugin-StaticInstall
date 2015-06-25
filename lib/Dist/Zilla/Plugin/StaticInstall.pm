use strict;
use warnings;
package Dist::Zilla::Plugin::StaticInstall;
# ABSTRACT: ...
# KEYWORDS: ...
# vim: set ts=8 sts=4 sw=4 tw=78 et :

our $VERSION = '0.001';
use Moose;
with 'Dist::Zilla::Role::...';

use namespace::autoclean;

around dump_config => sub
{
    my ($orig, $self) = @_;
    my $config = $self->$orig;

    $config->{+__PACKAGE__} = {
        ...
    };

    return $config;
};


__PACKAGE__->meta->make_immutable;
__END__

=pod

=head1 SYNOPSIS

In your F<dist.ini>:

    [StaticInstall]

=head1 DESCRIPTION

This is a L<Dist::Zilla> plugin that...

=head1 CONFIGURATION OPTIONS

=head2 C<foo>

...

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-StaticInstall>
(or L<bug-Dist-Zilla-Plugin-StaticInstall@rt.cpan.org|mailto:bug-Dist-Zilla-Plugin-StaticInstall@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 ACKNOWLEDGEMENTS

...

=head1 SEE ALSO

=for :list
* L<foo>

=cut
