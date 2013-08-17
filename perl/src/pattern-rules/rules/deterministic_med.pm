#!/usr/bin/perl
package deterministic_med;
require('initConfigRulesFSM.pl');

use vars (qw ($found_bgp $OK $ERROR));
use CiscoTypes;

sub define_slots {
    $fsm->slots ( {
	'_r1' => "$rtr_name",
	'_a1' => "$asnum",
    });
}


$START = sub {
    $fsm = shift;
    &define_slots();
    print STDERR "start\n" if $debug;
    $fsm->transition('_r1: router bgp _a1')->($found_bgp);
    &$ERROR('_r1 has no router bgp statement');
};

$found_bgp = sub {
    $fsm->transition('_r1: router bgp _a1 [[ bgp deterministic-med ]]')->($OK);
    &$ERROR('_r1 has no deterministic-med');
};

$OK = sub { 
    my $msg = "_r1: deterministic-med OK\n";
    print $fsm->substitute_def_bindings($msg);
    $fsm->pass()
};

$ERROR = sub {
    my $msg = shift;
    if (!$fsm->passed() && !$fsm->failed()) {
	my $msg_ = $fsm->substitute_def_bindings($msg);
	print ("ERROR: $msg_\n");
	$fsm->fail();
    }
};


$ABORT = sub {
    my $msg = shift;
    if (!$fsm->passed() && !$fsm->failed()) {
	my $msg_ = $fsm->substitute_def_bindings($msg);
	print STDERR ("ABORT: $msg_\n") ;
	$fsm->abort();
    }
};
