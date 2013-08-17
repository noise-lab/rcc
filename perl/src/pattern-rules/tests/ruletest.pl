#!/usr/bin/perl

BEGIN {
    push(@INC, "../../../lib");
    push(@INC, "../rules");
}


use Getopt::Long;
use ConfigCommon;
use ConfigFSM;

# FSM-based tests
use loopback;
use prepend;
use nexthop;


my %options;
GetOptions(\%options, "db", "graph=s", "debug=s");

if (defined($options{'debug'})) {
    $debug = $options{'debug'};
}



# loopback test
#my $lb_fsm = new ConfigFSM();
#$lb_fsm->bind_slot('_r1', 'wswdc01ck');
#$lb_fsm->bind_slot('_r1', 'abyny31c3');
#&$loopback::START($lb_fsm);

# AS prepend test
#&$prepend::START(new ConfigFSM());

# next-hop reachability
&$nexthop::START(new ConfigFSM());



#my $nh_fsm = new ConfigFSM();
#$nh_fsm->bind_slot('_r1', 'abyny31c3');
