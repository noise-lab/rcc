#!/usr/bin/perl

package determinism;

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

sub deterministic_med {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();

    my $q = "select router_name from $router_global where bgp=1 and deterministic_med=0";
    my $sth = $cq->query($q);

    while (my ($router) = $sth->fetchrow_array()) {
	printf ("WARNING: no deterministic-med: %s\n", $router) if !$quiet;
	push (@errors, $router);
    }

    if ($quiet==2) {
	my $q = "select count(distinct router_name) from $router_global";
	my $sth = $cq->query($q);
	my ($num_routers) = $sth->fetchrow_array();

	printf("routers w/o deterministic-med: %d (%.2f\%)\n",
	       scalar(@errors), scalar(@errors)/$num_routers*100);
    }
    return \@errors;
}


sub compare_routerid {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();

    my $q = "select router_name from $router_global where bgp=1 and compare_routerid=0";
    my $sth = $cq->query($q);

    while (my ($router) = $sth->fetchrow_array()) {
	printf ("WARNING: nondeterministic tiebreaking: %s\n", $router) if !$quiet;
	push (@errors, $router);
    }


    if ($quiet==2) {
	my $q = "select count(distinct router_name) from $router_global";
	my $sth = $cq->query($q);
	my ($num_routers) = $sth->fetchrow_array();

	printf("routers w/o compare-routerid: %d (%.2f\%)\n",
	       scalar(@errors), scalar(@errors)/$num_routers*100);
    }
    return \@errors;
}


1;
