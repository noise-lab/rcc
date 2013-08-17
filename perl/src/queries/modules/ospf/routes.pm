#!/usr/bin/perl

package routes;

BEGIN {
    push(@INC, "../../../lib");
}

use strict;
use ConfigCommon;
use ConfigDB;
use ConfigQueryOSPF;
use SSSP_Dijkstra;

my $cq = new ConfigQueryOSPF;
my $dijkstra = new SSSP_Dijkstra;

sub new {
    my ($class) = @_;
    my $self = {};
    bless ($self, $class);
    return $self;
}


# Build the shortest paths table
sub build_shortest_paths_table {
    my $self = shift;
    my $quiet = shift;
    
    # Get a list of all the routers
    my $q = "SELECT router_name FROM $router_info;";
    my $sth = $cq->query($q);

    my $dbh = &dbhandle("config_ospf");
    my $cmd = "DELETE FROM $routes";
    $dbh->do($cmd);

    while (my $router = $sth->fetchrow_array()) {
	$dijkstra->SSSP_Dijkstra_OSPF($router);
    }
}

1;
