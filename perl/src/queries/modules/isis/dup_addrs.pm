#!/usr/bin/perl

package dup_addrs;

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

sub check_duplicate_address {
    my $self = shift;
    my $quiet = shift;

    my @conflicting_routers_iso;
    my @conflicting_routers_ipv4;
    my @conflicting_routers_ipv6;

    my %iso_addresses = {};
    my %ipv4_addresses = {};
    my %ipv6_addresses = {};

    my $q = "SELECT router_name, iso_address, ipv4_address, ipv6_address FROM $router_info";
    my $sth = $cq->query($q);

    while (my ($router, $iso_addr, $ipv4_addr, $ipv6_addr) = $sth->fetchrow_array()) {
	# check if another router has same address
	# iso
	if (defined($iso_addresses{$iso_addr})) {
	    # There is a conflict here.
	    # Put the conflicting routers into array of conflicting routers
	    push(@conflicting_routers_iso, $router . " and " . $iso_addresses{$iso_addr} . " => " . $iso_addr);
	}
	else {
	    # No conflict, add this address as a key and 
	    # the router's name as the value in this hash table
	    if (!($iso_addr eq "")) {
		$iso_addresses{$iso_addr} = $router;
	    }
	}
	
	# ipv4
	if (defined($ipv4_addresses{$ipv4_addr})) {
	    # There is a conflict here.
	    # Put the conflicting routers into array of conflicting routers
	    push(@conflicting_routers_ipv4, $router . " and " . $ipv4_addresses{$ipv4_addr . " => " . $ipv4_addr});
	}
	else {
	    # No conflict, add this address as a key and 
	    # the router's name as the value in this hash table
	    # if the address != 127.0.0.1
	    if (!($ipv4_addr eq "127.0.0.1" || $ipv4_addr eq "")) {
		$ipv4_addresses{$ipv4_addr} = $router;
	    }
	}

	# ipv6
	if (defined($ipv6_addresses{$ipv6_addr})) {
	    # There is a conflict here.
	    # Put the conflicting routers into array of conflicting routers
	    push(@conflicting_routers_ipv6, $router . " and " .$ipv6_addresses{$ipv6_addr} . " => " . $ipv6_addr);
	}
	else {
	    # No conflict, add this address as a key and 
	    # the router's name as the value in this hash table
	    # if the address != ::1/128
	    if (!($ipv6_addr eq "::1/128" || $ipv6_addr eq "")) {
		$ipv6_addresses{$ipv6_addr} = $router;
	    }
	}
	
    }

    # Print out the conflicting routers
    print "The following routers have conflicting ISO addresses configured:\n";
    foreach my $router (@conflicting_routers_iso) {
	print "$router\n";
    }
    
    print "The following routers have conflicting IPv4 addresses configured:\n";
    foreach my $router (@conflicting_routers_ipv4) {
	print "$router\n";
    }
    
    print "The following routers have conflicting IPv6 addresses configured:\n";
    foreach my $router (@conflicting_routers_ipv6) {
	print "$router\n";
    }
}

1;
