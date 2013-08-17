#!/usr/bin/perl

BEGIN {
    push(@INC, "../../../lib");
    push(@INC, "../rules");
}


use Getopt::Long;
use ConfigCommon;
use ConfigFSM;

# FSM-based tests
use deterministic_med;
use routerid;

my %options;
GetOptions(\%options, "db", "graph=s", "debug=s");

if (defined($options{'debug'})) {
    $debug = $options{'debug'};
}


# deterministic MED
&$deterministic_med::START(new ConfigFSM());


# routerid test
&$routerid::START(new ConfigFSM());
