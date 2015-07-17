use strict;
use warnings;

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Deep;
use Test::Fatal;
use Path::Tiny;

use lib 't/lib';

my @tests = (
    {
        x_static_install => 0,
        mode => 'on',
    },
    {
        x_static_install => 1,
        mode => 'off',
    },
);

subtest "preset x_static_install = input of $_->{x_static_install}, our mode = $_->{mode}" => sub
{
    my $config = $_;

    my $tzil = Builder->from_config(
        { dist_root => 'does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    [ GatherDir => ],
                    [ MetaConfig => ],
                    [ MetaJSON => ],
                    [ '=SimpleFlagSetter' => { value => $config->{x_static_install} } ],
                    [ 'MakeMaker' ],
                    [ 'StaticInstall' => { mode => $config->{mode} } ],
                ),
                path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
            },
        },
    );

    $tzil->chrome->logger->set_debug(1);

    like(
        exception { $tzil->build },
        qr/Can't merge attribute x_static_install: '$config->{x_static_install}' does not equal '${ \($config->{mode} eq 'on' ? 1 : 0) }' at /,
        'build fails in setup_installer when the results conflict',
    );

    diag 'got log messages: ', explain $tzil->log_messages
        if not Test::Builder->new->is_passing;
}
foreach @tests;

done_testing;
