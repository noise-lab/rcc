#!/usr/bin/perl

package parse;

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


sub summary {
    my $self = shift;

    my %num_errors;
    my %num_router_errors;

    my $q = "select def_type, count(*) from $parse_errors group by def_type";
    my $sth = $cq->query($q);
    while (my ($def_type, $cnt) = $sth->fetchrow_array()) {
	$num_errors{$def_type} = $cnt;
    }

    $q = "select def_type, count(distinct router_name) from parse_errors group by def_type";
    $sth = $cq->query($q);
    while (my ($def_type, $cnt) = $sth->fetchrow_array()) {
	$num_router_errors{$def_type} = $cnt;
    }

    foreach my $type (keys %num_errors) {
	my $idx = $type;
	print "undefined $def_names[$idx]: $num_errors{$type} ($num_router_errors{$type} routers)\n";
    }

}


sub parse_errors {
    my $self = shift;
    my $quiet = shift;

    if ($quiet==2) {
	$self->summary();
    } elsif (!$quiet) {
	my $q = "select router_name, route_map_name, def_type, def_num from parse_errors order by router_name";
	my $sth = $cq->query($q);
	while (my ($router, $rm, $type, $num) = $sth->fetchrow_array()) {
	    print "ERROR: $router, undefined $def_names[$type] $num in route map $rm\n" if ($type < 4);
	    printf "ERROR: $router, undefined $def_names[$type] $rm (%s)\n", &inet_ntoa_($num) if ($type == 4);
	}
    }

}
