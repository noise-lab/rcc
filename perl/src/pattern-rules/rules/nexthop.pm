#!/usr/bin/perl
package nexthop;
require('initConfigRulesFSM.pl');

use vars (qw ($found_ibgp $found_ebgp $no_nh_self $nh_in_as $OK $ERROR));
use CiscoTypes;

sub define_slots {
    $fsm->slots ( {
	'_r1' => "$rtr_name",
	'_r2' => "$rtr_name",
	'_n2' => "$addr_mask",
	'_a1' => "$asnum",
	'_a2' => "$asnum",
	'_n3' => "$addr_mask",
	'_m3' => "$quad_mask",
    });
}


$START = sub {
    $fsm = shift;
    &define_slots();

    print STDERR "start\n" if $debug;
    $fsm->transition('_r1: router bgp _a1 [[ neighbor _n2 remote-as _a2 ]]')->(sub { ($fsm->get_slot('_a1')==$fsm->get_slot('_a2') && defined($fsm->get_slot('_a1')))?&$found_ibgp:&$found_ebgp; });
    &$ERROR('_r1 has no BGP neighbor statements');
};

$found_ibgp = sub {
    print STDERR $fsm->substitute_def_bindings("found ibgp on _r1\n");
    $fsm->transition('_r1: router bgp _a1 [[ neighbor _n2 next-hop-self ]]')->($OK);
    &$no_nh_self_ibgp();
};

$no_nh_self_ibgp = sub {
    print STDERR $fsm->substitute_def_bindings("ibgp: no next-hop-self _r1 (_n2)\n");
    $fsm->transition('_r2: interface [[ ip address _n2 ]]')->($OK);
    &$ERROR('_n2 not in IGP (iBGP session)');
};


$found_ebgp = sub {
    print STDERR $fsm->substitute_def_bindings("found ebgp on _r1 (AS _a2)\n");
    $fsm->transition('_r1: router bgp _a1 [[ neighbor _n2 next-hop-self ]]')->($OK);
    $fsm->transition('_r1: router bgp _a1 [[ neighbor _n2 update-source Loopback\s*\d+ ]]')->($OK);
    &$no_nh_self_ebgp();
};

$no_nh_self_ebgp = sub {
    print STDERR $fsm->substitute_def_bindings("ebgp: no next-hop-self _r1 (_n2)\n");
    $fsm->transition('_r1: router bgp _a1 [[ network _n3 mask _m3 <contains(_n3/_m3, _n2)>]]',1)->($OK);
    &$ERROR('_n2 not in iBGP/IGP (eBGP session)');
};



$OK = sub { 
    my $msg = "_r1: BGP session to _n2 next-hop OK (_r2)\n";
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
