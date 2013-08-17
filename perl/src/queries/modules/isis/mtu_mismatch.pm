#!/usr/bin/perl

package mtu_mismatch;

BEGIN {
    push(@INC, "../../../lib");
}

use strict;
use ConfigCommon;
use ConfigDB;
use ConfigQueryISIS;

my $cq = new ConfigQueryISIS;

sub new {
    my ($class) = @_;
    my $self = {};
    bless ($self, $class);
    return $self;
}

sub check_mtu_mismatch {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();
    

    print STDERR "\nVerifying that there are no MTU mismatches for each IS-IS adjacency.\n" if !$quiet;

    # For each edge check the MTU of the origin and destination router
     my $q = "SELECT origin_router_name, dest_router_name, ipv4_subnet_address FROM $adjacencies";
    my $sth = $cq->query($q);

    while (my ($origin_router, $dest_router, $ipv4_subnet_addr) = $sth->fetchrow_array()) {
	# get MTU of origin router's interface
	my $q1 = "SELECT mtu_ipv4,interface_name FROM $router_interfaces WHERE router_name='$origin_router' AND ipv4_address='$ipv4_subnet_addr'";
	my $sth1 = $cq->query($q1);
	my @row1 = $sth1->fetchrow_array();
	my $origin_mtu = $row1[0];
	my $origin_intf = $row1[1];

	# get MTU of dest router's interface
	my $q2 = "SELECT mtu_ipv4,interface_name FROM $router_interfaces WHERE router_name='$dest_router' AND ipv4_address='$ipv4_subnet_addr'";
	my $sth2 = $cq->query($q2);
	my @row2 = $sth2->fetchrow_array();
	my $dest_mtu = $row2[0];
	my $dest_intf = $row2[1];

	# compare
	if ($origin_mtu != $dest_mtu) {
	    if (!$quiet) {
		print "WARNING: MTU Mismatch for $origin_router => $dest_router.\n";
		print "Conflicting Interfaces: $origin_router : $origin_intf: MTU = $origin_mtu.\n";
		print "Conflicting Interfaces: $dest_router : $dest_intf: MTU = $dest_mtu.\n";
	    }
	}

    }

    # print summary here
    
}

1;
