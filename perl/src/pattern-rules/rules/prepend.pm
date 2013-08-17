#!/usr/bin/perl
package prepend;
require('initConfigRulesFSM.pl');

use vars (qw ($found_bgp $test_prepend $OK $ERROR));
use CiscoTypes;

sub define_slots {
    $fsm->slots ( {
	'_r1' => "$rtr_name",
	'_a1' => "$asnum",
	'_a2' => "$asnum",
    });
}


$START = sub {
    $fsm = shift;
    &define_slots();

    print STDERR "start\n" if $debug;
    $fsm->transition('_r1: router bgp _a1')->($found_bgp);
    &$ERROR('_r1 has no BGP statement');
};

$found_bgp = sub {
    print STDERR $fsm->substitute_def_bindings("found bgp on _r1\n");
    $fsm->transition('_r1: set as-path prepend')->($test_prepend);
    &$OK();
};

$test_prepend = sub {
    print STDERR $fsm->substitute_def_bindings("found prepend on _r1\n");
    $fsm->transition('_r1: set as-path prepend _a1')->($OK);
    $fsm->transition('_r1: set as-path prepend _a2')->($ERROR->('bogus prepend _a2 (should be _a1)'));
};

$OK = sub { 
    my $msg = "_r1 Passed\n";
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
