use strict;
use warnings;
package Dist::Zilla::Plugin::StaticInstall;
# ABSTRACT: Identify a distribution as eligible for static installation
# KEYWORDS: distribution metadata toolchain static dynamic installation
# vim: set ts=8 sts=4 sw=4 tw=115 et :

our $VERSION = '0.002';

use Moose;
with 'Dist::Zilla::Role::MetaProvider',
    'Dist::Zilla::Role::InstallTool';

use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(Str Bool);
use Scalar::Util 'blessed';
use List::Util 'first';
use namespace::autoclean;

my $mode_type = enum([qw(off on auto)]);
coerce $mode_type, from Str, via { $_ eq '0' ? 'off' : $_ eq '1' ? 'on' : $_ };
has mode => (
    is => 'ro', isa => $mode_type,
    default => 'on',
    coerce => 1,
);

has dry_run => (
    is => 'ro', isa => Bool,
    default => 0,
);

around dump_config => sub
{
    my ($orig, $self) = @_;
    my $config = $self->$orig;

    $config->{+__PACKAGE__} = {
        mode => $self->mode,
        dry_run => $self->dry_run,
    };

    return $config;
};

sub BUILD
{
    my $self = shift;
    $self->log_fatal('dry_run cannot be true if mode is "off" or "on"')
        if $self->dry_run and $self->mode ne 'auto';
}

sub metadata
{
    my $self = shift;
    my $mode = $self->mode;
    return +{ x_static_install => 0 } if $mode eq 'off';
    return +{ x_static_install => 1 } if $mode eq 'on';

    return +{} if $self->dry_run;

    # we'll calculate this value later in the build and munge it in
    return +{ x_static_install => 'PLACEHOLDER' };
}

sub setup_installer
{
    my $self = shift;

    return if $self->mode ne 'auto';

    my ($value, $message) = $self->_heuristics;
    my $log = $self->dry_run ? 'log' : 'log_debug';

    $self->$log($message) if $message;
    $self->$log([ '%s x_static_install to %s', $self->dry_run ? 'would set' : 'setting', $value ]);
    $self->zilla->distmeta->{x_static_install} = $value if not $self->dry_run;
}

# returns value, log message
sub _heuristics
{
    my $self = shift;

    my $distmeta = $self->zilla->distmeta;
    my $log = $self->dry_run ? 'log' : 'log_debug';

    $self->$log('checking dynamic_config');
    return (0, 'dynamic_config is true') if $distmeta->{dynamic_config};

    $self->$log('checking configure prereqs');
    my %extra_configure_requires = %{ $distmeta->{prereqs}{configure}{requires} || {} };
    delete @extra_configure_requires{qw(ExtUtils::MakeMaker Module::Build::Tiny File::ShareDir::Install perl)};
    return (0, [ 'found configure prereq%s %s',
            keys(%extra_configure_requires) > 1 ? 's' : '',
            join(', ', keys %extra_configure_requires) ]) if keys %extra_configure_requires;

    $self->$log('checking build prereqs');
    my @build_requires = grep { $_ ne 'perl' } keys %{ $distmeta->{prereqs}{build}{requires} };
    return (0, [ 'found build prereq%s %s',
            @build_requires > 1 ? 's' : '',
            join(', ', @build_requires) ]) if @build_requires;

    $self->$log('checking sharedirs');
    my $share_dir_map = $self->zilla->_share_dir_map;
    my @module_sharedirs = keys %{ $share_dir_map->{module} };
    return (0, [ 'found module sharedir%s for %s',
            @module_sharedirs > 1 ? 's' : '',
            join(', ', @module_sharedirs) ]) if @module_sharedirs;

    $self->$log('checking installer plugins');
    my @installers = @{ $self->zilla->plugins_with(-InstallTool) };

    # we need to be last, to see the final copy of the installer files
    return (0, [ 'this plugin must be after %s', blessed($installers[-1]) ]) if $installers[-1] != $self;

    return (0, [ 'a recognized installer plugin must be used' ]) if @installers < 2;

    # only these installer plugins can be trusted to not add disqualifying content
    my @other_installers = grep { blessed($_) !~ /^Dist::Zilla::Plugin::((MakeMaker|ModuleBuildTiny)(::Fallback)?|StaticInstall)$/ } @installers;
    return (0, [ 'found install tool%s %s that will add extra content to Makefile.PL,Build.PL',
            @other_installers > 1 ? 's' : '',
            join(', ', map { blessed($_) } @other_installers) ]) if @other_installers;

    # check that no other plugins put their grubby hands on our installer file(s)
    foreach my $installer_file (grep { $_->name eq 'Makefile.PL' or $_->name eq 'Build.PL' } @{ $self->zilla->files })
    {
        $self->$log([ 'checking for munging of %s', $installer_file->name ]);

        foreach my $added_by (split('; ', $installer_file->added_by))
        {
            return (0, [ '%s %s', $installer_file->name, $added_by ])
                if $added_by =~ /from coderef added by/
                    or $added_by =~ /filename set by/
                    or ($added_by =~ /content set by .* \((.*) line \d+\)/
                        and $1 !~ /Dist::Zilla::Plugin::(MakeMaker|ModuleBuildTiny)(::Fallback)?$/);
        }
    }

    $self->$log('checking META.json');
    my $metajson = first { blessed($_) eq 'Dist::Zilla::Plugin::MetaJSON' } @{ $self->zilla->plugins };
    return (0, 'META.json is not being added to the distribution') if not $metajson;
    return (0, [ 'META.json is using meta-spec version %s', $metajson->version ]) if $metajson->version ne '2';

    $self->$log('checking for .xs files');
    my @xs_files = grep { $_->name =~ /\.xs$/ } @{ $self->zilla->files };
    return (0, [ 'found .xs file%s %s', @xs_files > 1 ? 's' : '', join(', ', map { $_->name } @xs_files) ]) if @xs_files;

    return 1;
}

__PACKAGE__->meta->make_immutable;
__END__

=pod

=head1 SYNOPSIS

In your F<dist.ini>:

    ; when you are confident this is correct
    [StaticInstall]
    mode = on

    ; be conservative; just tell us what the value should be
    [StaticInstall]
    mode = auto
    dry_run = 1

=head1 DESCRIPTION

This is a L<Dist::Zilla> plugin that, when C<mode> is C<on>, provides the following distribution metadata:

    x_static_install : "1"

The definition of a "static installation" is still being refined by the Perl
Toolchain Gang. Use with discretion!

The current preconditions for C<x_static_install> being true include:

=begin :list

* C<dynamic_config> must be false in metadata
* no prerequisites in configure-requires other than L<ExtUtils::MakeMaker>, L<Module::Build::Tiny>, or L<File::ShareDir::Install>
* no prerequisites in build-requires
* no installer plugins permitted other than:

=for :list
* L<Dist::Zilla::Plugin::MakeMaker>
* L<Dist::Zilla::Plugin::MakeMaker::Fallback>
* L<Dist::Zilla::Plugin::ModuleBuildTiny>
* L<Dist::Zilla::Plugin::ModuleBuildTiny::Fallback>

* an installer plugin from the above list B<must> be used (a manually-generated F<Makefile.PL> or F<Build.PL> is not permitted)
* no other plugins may modify F<Makefile.PL> nor F<Build.PL>
* the L<C<[MetaJSON]>|Dist::Zilla::Plugin::MetaJSON> plugin must be used, at (the default) meta-spec version 2
* no F<.xs> files may be present

=end :list

=head1 CONFIGURATION OPTIONS

=head2 C<mode>

=for stopwords usecase

When set to C<on>, the value of C<x_static_install> is set to 1 (the normal usecase).

When set to C<off>, the value of C<x_static_install> is set to 0, which is
equivalent to not providing this field at all.

When set to C<auto>, we attempt to calculate the proper value. When used with
C<dry_run = 1>, the value isn't actually stored, but just provided in a
diagnostic message. This is the recommended usage in a plugin bundle, for
testing against a number of distributions at once.

=head2 C<dry_run>

When true, no value is set in metadata, but verbose logging is enabled so you
can see what the value would have been.

=for Pod::Coverage BUILD metadata setup_installer

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-StaticInstall>
(or L<bug-Dist-Zilla-Plugin-StaticInstall@rt.cpan.org|mailto:bug-Dist-Zilla-Plugin-StaticInstall@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 SEE ALSO

=for :list
* L<CPAN::Meta::Spec>

=cut
