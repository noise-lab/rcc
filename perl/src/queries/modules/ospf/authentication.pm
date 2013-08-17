#!/usr/bin/perl

package authentication;

BEGIN {
    push(@INC, "../../../lib");
}

use strict;
use ConfigCommon;
use ConfigDB;
use ConfigQueryOSPF;

my $cq = new ConfigQueryOSPF;

sub new {
    my ($class) = @_;
    my $self = {};
    bless ($self, $class);
    return $self;
}

sub check_auth_type {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();    
    
    print STDERR "\nVerifying that all routers are configured for same type of authentication.\n" if !$quiet;
    
    my $q = "SELECT area, auth_type FROM area_info";
    my $sth = $cq->query($q);
    
    while (my ($area, $auth_type) = $sth->fetchrow_array()) {
	my $q2 = "SELECT router_name, interface_name, auth_type  FROM router_interfaces WHERE area='$area' AND auth_type != '$auth_type'";
	my $sth2 = $cq->query($q2);
	
	while (my ($router, $interface, $auth) - $sth2->fetchrow_array()) {
	    print STDERR "WARNING: $router on interface $interface in area $area uses $auth authentication while area $area is configured to use $auth_type authentication.\n" if !$quiet;
	    push(@errors, $router);
	}
	
    }
    
    # summary
    my $count = scalar(@errors);
    print STDERR "===Summary===\n";
    print STDERR "Found $count discrepancies in authentication.\n";
    
}

sub check_auth_key {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();

    print STDERR "\nVerifying that all routers using the same authentication key.\n" if !$quiet;
    
    my $q = "SELECT router_name, auth_key FROM router_info where auth_type != 'none'";
    my $sth = $cq->query($q);
    
    my $key = "";
    while (my ($router_name, $auth_key) = $sth->fetchrow_array()) {
	if ($key eq "") {
	    $key = $auth_key;
	    print STDERR "$router_name has key SHA1 hash $auth_key.\n" if !$quiet;
	}
	else {
	    if (!($key eq $auth_key)) {
		# the keys don't match
		print STDERR "$router_name has conflicting authentication key.\n" if !$quiet;
	    }
	}
    }
}

1;
