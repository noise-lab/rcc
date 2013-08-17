#!/usr/bin/perl

package nexthop;

BEGIN {
    push(@INC, "../../../lib");
}

use strict;
use ConfigCommon;
use ConfigDB;
use ConfigQuery;


my $cq = new ConfigQuery;

sub new {
    my ($class) = @_;
    my $self = {};
    bless ($self, $class);
    return $self;
}

sub next_hop_reachability {
    my $self = shift;
    my $quiet = shift;
    my @errors = shift;
   
    my $q = "select router_name, neighbor_ip, asn from sessions where ebgp=1 and nh_self=0";
    my $sth = $cq->query($q);

    while (my ($router, $nbr, $asn) = $sth->fetchrow_array()) {
	# XXX here we should check the IGP stuff for this nbr
	#     to see if the addr is reachable via the IGP

    }

    if ($quiet==2) {
	printf "sessions w/next-hop unreachable: XXX FIX THIS TEST (need IGP) XXX\n";
    }

    return \@errors;
}

1;
