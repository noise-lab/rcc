#!/usr/bin/perl

package authentication;

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

sub check_auth_type {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();    
    
    print STDERR "\nVerifying that all routers are configured for same type of authentication.\n" if !$quiet;
    
    my $q = "SELECT router_name, auth_type FROM router_info";
    my $sth = $cq->query($q);
    
    my $type = "";
    while (my ($router_name, $auth_type) = $sth->fetchrow_array()) {
	if ($type eq "") {
	    $type = $auth_type;
	}
	else {
	    if (!($type eq $auth_type)) {
		# the auth type doesn't match
		print STDERR "$router_name has conflicting authentication type: $auth_type.\n" if !$quiet;
	    }
	}
    }
    
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
