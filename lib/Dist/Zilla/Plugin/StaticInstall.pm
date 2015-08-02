use strict;
use warnings;
package Dist::Zilla::Plugin::StaticInstall;
# ABSTRACT: (EXPERIMENTAL, DANGEROUS) Identify a distribution as eligible for static installation
# KEYWORDS: distribution metadata toolchain static dynamic installation
# vim: set ts=8 sts=4 sw=4 tw=115 et :

our $VERSION = '0.008';

use Moose;
with 'Dist::Zilla::Role::MetaProvider',
    'Dist::Zilla::Role::InstallTool';

use Moose::Util::TypeConstraints;
use MooseX::Types::Moose qw(Str Bool);
use Scalar::Util 'blessed';
use List::Util 1.33 qw(first any);
no autovivification;
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
        dry_run => $self->dry_run ? 1 : 0,
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

    my $value = $mode eq 'on' ? 1 : $mode eq 'off' ? 0 : undef;
    if (defined $value)
    {
        $self->log([ 'setting x_static_install to %s', $value ]);
        return +{ x_static_install => $value };
    }

    # if mode = auto and dry_run = 0, we'll add it later
    return +{};
}

sub setup_installer
{
    my $self = shift;

    # even if mode = off or on, we still run all the heuristics, as an extra check.
    my ($value, $message) = $self->_heuristics;

    my $distmeta = $self->zilla->distmeta;

    if ($self->mode ne 'off' and exists $distmeta->{x_static_install} and ($distmeta->{x_static_install} xor $value))
    {
        $self->log_fatal('something set x_static_install = 0 but we want to set it to 1') if $value;

        my $str1 = $self->mode eq 'on' ? 'mode = on' : 'x_static_install was set';
        $message = [ $message ] if not ref $message;

        $self->log_fatal([
            $str1 . ' but this distribution is ineligible: ' . $message->[0],
            splice(@$message, 1)
        ]);
    }

    $self->${ \ ($self->dry_run ? 'log' : 'log_debug') }($message) if $message;

    # say what we would do, if dry run or heuristic different than requested
    $self->log([ 'would set x_static_install to %s', $value ])
        if $self->dry_run or ($value and $self->mode eq 'off');

    if (not exists $distmeta->{x_static_install} and $self->mode eq 'auto' and not $self->dry_run)
    {
        $self->log([ 'setting x_static_install to %s', $value ]);
        $distmeta->{x_static_install} = $value;
    }
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
            join(', ', sort keys %extra_configure_requires) ]) if keys %extra_configure_requires;

    $self->$log('checking build prereqs');
    my @build_requires = grep { $_ ne 'perl' } keys %{ $distmeta->{prereqs}{build}{requires} };
    return (0, [ 'found build prereq%s %s',
            @build_requires > 1 ? 's' : '',
            join(', ', sort @build_requires) ]) if @build_requires;

    $self->$log('checking sharedirs');
    my @module_sharedirs = keys %{ $self->zilla->_share_dir_map->{module} };
    return (0, [ 'found module sharedir%s for %s',
            @module_sharedirs > 1 ? 's' : '',
            join(', ', sort @module_sharedirs) ]) if @module_sharedirs;

    $self->$log('checking installer plugins');
    my @installers = @{ $self->zilla->plugins_with(-InstallTool) };

    # we need to be last, to see the final copy of the installer files
    return (0, [ 'this plugin must be after %s', blessed($installers[-1]) ]) if $installers[-1] != $self;

    return (0, [ 'a recognized installer plugin must be used' ]) if @installers < 2;

    # only these installer plugins can be trusted to not add disqualifying content
    my @other_installers = grep { blessed($_) !~ /^Dist::Zilla::Plugin::((MakeMaker|ModuleBuildTiny)(::Fallback)?|StaticInstall)$/ } @installers;
    return (0, [ 'found install tool%s %s that will add extra content to Makefile.PL, Build.PL',
            @other_installers > 1 ? 's' : '',
            join(', ', sort map { blessed($_) } @other_installers) ]) if @other_installers;

    # check that no other plugins put their grubby hands on our installer file(s)
    foreach my $installer_file (grep { $_->name eq 'Makefile.PL' or $_->name eq 'Build.PL' } @{ $self->zilla->files })
    {
        $self->$log([ 'checking for munging of %s', $installer_file->name ]);

        foreach my $added_by (split(/; /, $installer_file->added_by))
        {
            return (0, [ '%s %s', $installer_file->name, $added_by ])
                if $added_by =~ /from coderef added by/
                    or $added_by =~ /filename set by/
                    or ($added_by =~ /content set by .* \((.*) line \d+\)/
                        and not ($1 eq 'Dist::Zilla::Plugin::MakeMaker::Awesome'
                                 and any { blessed($_) eq 'Dist::Zilla::Plugin::MakeMaker::Fallback' } @installers)
                        and $1 !~ /Dist::Zilla::Plugin::(MakeMaker|ModuleBuildTiny)(::Fallback)?$/);
        }
    }

    $self->$log('checking META.json');
    my $metajson = first { blessed($_) eq 'Dist::Zilla::Plugin::MetaJSON' } @{ $self->zilla->plugins };
    return (0, 'META.json is not being added to the distribution') if not $metajson;
    return (0, [ 'META.json is using meta-spec version %s', $metajson->version ]) if $metajson->version ne '2';

    my @filenames = map { $_->name } @{ $self->zilla->files };

    $self->$log('checking for .xs files');
    my @xs_files = grep { /\.xs$/ } @filenames;
    return (0, [ 'found .xs file%s %s', @xs_files > 1 ? 's' : '', join(', ', sort @xs_files) ]) if @xs_files;

    my $BASEEXT = (split(/-/, $self->zilla->name))[-1];

    $self->$log('checking .pm, .pod, .pl files');
    my @root_files = grep { m{^[^/]*\.(pm|pl|pod)$} and !m{^lib/} } @filenames;
    return (0, [ 'found %s in the root', join(', ', sort @root_files) ]) if @root_files;

    my @baseext_files = $BASEEXT eq 'lib' ? () : grep { m{^$BASEEXT/[^/]*\.(pm|pl|pod)$} } @filenames;
    return (0, [ 'found %s in %s/', join(', ', sort map { s{^$BASEEXT/}{}; $_ } @baseext_files), $BASEEXT ]) if @baseext_files;

    $self->$log('checking for .PL, .pmc files');
    my @PL_files = grep { !/^(Makefile|Build)\.PL$/ and /\.(PL|pmc)$/ } @filenames;
    return (0, [ 'found %s', join(', ', sort @PL_files) ]) if @PL_files;

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

    ; trust us to set the right value (DANGER!)
    [StaticInstall]
    mode = auto

    ; be conservative; just tell us what the value should be
    [StaticInstall]
    mode = auto
    dry_run = 1

=head1 DESCRIPTION

This is a L<Dist::Zilla> plugin that, when C<mode> is C<on>, provides the following distribution metadata:

    x_static_install : "1"

The plugin performs a number of checks against the distribution to determine
the proper value of the C<x_static_install> metadata field. When set to a true
value, this indicates that the can skip a number of installation steps
(such as running F<Makefile.PL> or F<Build.PL> and acting on its side effects).

The definition of a "static installation" is being prototyped by the Perl
Toolchain Gang and is still being refined.  B<DO NOT USE THIS PLUGIN> if you
are not involved in this testing. The proper installation of the built
distribution cannot be guaranteed if installed with a static install-enabled
client.

The current preconditions for C<x_static_install> being true include:

=for stopwords sharedir

=begin :list

* C<dynamic_config> must be false in metadata
* no prerequisites in configure-requires other than L<ExtUtils::MakeMaker>,
  L<Module::Build::Tiny>, or L<File::ShareDir::Install>
* no prerequisites in build-requires
* no L<module sharedir|Dist::Zilla::Plugin::ModuleShareDirs> (a L<distribution
  sharedir|Dist::Zilla::Plugin::ShareDir> is okay)
* no installer plugins permitted other than:

=for :list
* L<Dist::Zilla::Plugin::MakeMaker>
* L<Dist::Zilla::Plugin::MakeMaker::Fallback>
* L<Dist::Zilla::Plugin::ModuleBuildTiny>
* L<Dist::Zilla::Plugin::ModuleBuildTiny::Fallback>

* an installer plugin from the above list B<must> be used (a
  manually-generated F<Makefile.PL> or F<Build.PL> is not permitted)
* no other plugins may modify F<Makefile.PL> nor F<Build.PL>
* the L<C<[MetaJSON]>|Dist::Zilla::Plugin::MetaJSON> plugin must be used, at
  (the default) meta-spec version 2
* no F<.xs> files may be present
* F<.pm>, F<.pod>, F<.pl> files may not be present in the root of the
  distribution or in C<BASEEXT> (where C<BASEEXT> is the last component of the
  distribution name)
* F<.pmc> and F<.PL> files (excluding F<Makefile.PL>, F<Build.PL>) may not be present

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

The calculations are always performed, no matter the value of C<mode> -- if it
comes up with a different result than what you are setting, this is logged. If
C<mode = on> and the calculations discover the distribution is ineligible for
this flag, the build fails, to prevent you from releasing bad metadata.

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
