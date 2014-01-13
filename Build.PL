use v5.14;
use warnings;
use Module::Build;


my $build = Module::Build->new(
    module_name       => 'UAV::Pilot::WumpusRover::Server',
    dist_abstract     => 'Control the WumpusRover',
    dist_author       => q{Timm Murray <tmurray@wumpus-cave.net>},
    dist_version_from => 'lib/UAV/Pilot/WumpusRover/Server.pm',
    license           => 'bsd',
    requires          => {
        perl          => '>= 5.14.0',
        'UAV::Pilot'  => '>= 0.8',
        'HiPi'        => 0,
        'Moose'       => 0,
        'Test::More'  => 0,
        'Tie::IxHash' => 0,
        'Throwable'   => 0,
    },
    recommends => {
        'Getopt::Long' => 0,
    },
    meta_merge => {
        resources => {
            repository => 'https://github.com/frezik/UAV-Pilot-WumpusRover-Server',
        },
    },
);

$build->create_build_script;
