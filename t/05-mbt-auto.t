use strict;
use warnings;

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Deep;
use Test::Fatal;
use Path::Tiny;

use Test::Requires { 'Dist::Zilla::Plugin::ModuleBuildTiny' => '0.011' };

my $tzil = Builder->from_config(
    { dist_root => 'does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ MetaConfig => ],
                [ ModuleBuildTiny => { ':version' => '0.011', static => 'auto' } ],
                [ MetaJSON => ],
                [ 'StaticInstall' => { mode => 'auto' } ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

$tzil->chrome->logger->set_debug(1);
is(
    exception { $tzil->build },
    undef,
    'build proceeds normally',
);

cmp_deeply(
    $tzil->distmeta,
    superhashof({
        x_static_install => 1,
        x_Dist_Zilla => superhashof({
            plugins => supersetof(
                {
                    class => 'Dist::Zilla::Plugin::StaticInstall',
                    config => {
                        'Dist::Zilla::Plugin::StaticInstall' => {
                            mode => 'auto',
                            dry_run => 0,
                        },
                    },
                    name => 'StaticInstall',
                    version => Dist::Zilla::Plugin::StaticInstall->VERSION,
                },
            ),
        }),
    }),
    'plugin metadata indicates a static install',
) or diag 'got distmeta: ', explain $tzil->distmeta;

diag 'got log messages: ', explain $tzil->log_messages
    if not Test::Builder->new->is_passing;

done_testing;
