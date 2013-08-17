#!/usr/bin/perl
package loopback;
require('initConfigRulesFSM.pl');

use vars (qw ($second_lb $fwd_as_match $found_loopback $bgp_open $OK $ERROR));

sub define_slots {
    $fsm->slots ( {
	'_r1' => "$rtr_name",
	'_r2' => "$rtr_name",
	'_n1' => "$addr_mask",
	'_n2' => "$addr_mask",
	'_n3' => "$addr_mask",
	'_a1' => "$asnum",
	'_a2' => "$asnum",
    });
}


$START = sub {
    $fsm = shift;
    &define_slots();

    print STDERR "start\n" if $debug;
    $fsm->transition('_r1: interface Loopback0 [[ ip address _n1 ]]')->($found_loopback);
    &$ERROR('No Loopback Addresses found on _r1');
};

$found_loopback = sub {
    print STDERR $fsm->substitute_def_bindings("found lb on _r1\n");
    $fsm->transition('_r1: router bgp _a1 [[ neighbor _n2 remote-as _a2 ]]')->(sub { ($fsm->get_slot('_a1')==$fsm->get_slot('_a2') && defined($fsm->get_slot('_a1')))?&$bgp_open:&$ABORT('AS _a2 out of scope'); });
    &$ERROR('_r1 has NO BGP Statement');
};
	    

$bgp_open = sub {
    print STDERR "bgp open\n" if $debug;
    $fsm->transition('_r2: interface Loopback\s*\d+ [[ ip address _n2 ]]')->($fwd_as_match);
    $fsm->transition('_r2: interface _n3 [[ ip address _n2 ]]')->($ERROR->('no _r2 with loopback _n2 (from _r1)'));
    &$ERROR('_r1 has dangling session');
};

$fwd_as_match = sub {
    print STDERR "fwd_as_match\n" if $debug;
    $fsm->transition('_r2: router bgp _a2 [[ neighbor _n1 remote-as _a1 ]]')->($OK);
    $fsm->transition('_r2: router bgp _a2 [[ neighbor _n3 remote-as _a1]]', 1)->($second_lb);
    $fsm->transition('_r2: router bgp _a2 [[ neighbor _n1 remote-as _a3 ]]')->($ERROR->('Reverse failure: no _r1/_n1 at _r2/_n2')); 
};

$second_lb = sub {
    print STDERR "second_lb\n" if $debug;
    $fsm->transition('_r1: interface Loopback\s*\d+ [[ ip address _n3 ]]')->($OK);
    &$ERROR('Reverse failure: no _r1/_n1 at _r2/_n2');
};


$OK = sub { 
    my $msg = "_r1->_n2 (_n3) OK\n";
    print $fsm->substitute_def_bindings($msg);
    $fsm->pass()
};

$ERROR = sub {
    my $msg = shift;
    if (!$fsm->passed() && !$fsm->failed()) {
	my $msg_ = $fsm->substitute_def_bindings($msg);
	print ("ERROR: $msg_\n"), 
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
