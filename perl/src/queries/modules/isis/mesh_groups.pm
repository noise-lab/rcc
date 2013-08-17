#!/usr/bin/perl

package mesh_groups;

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

sub check_mesh_groups {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();    
    
    print STDERR "\nVerifying that all mesh group routers are fully connected.\n" if !$quiet;

    my $q = "SELECT router_name, mesh_group_number, interface_name FROM $mesh_groups";
    my $sth = $cq->query($q);

    while (my ($router, $mesh_num, $intf_name) = $sth->fetchrow_array()) {
	# get list of other routers in the same mesh group and check
	# that this router has an adjacency to all of them
	my $q2 = "SELECT router_name FROM $mesh_groups WHERE mesh_group_number = '$mesh_num'";
	my $sth2 = $cq->query($q2);
	
	while (my $other_router = $sth2->fetchrow_array()) {
	    # check if there is an adjacency between the two routers
	    my $q3 = "SELECT origin_router_name FROM $adjacencies WHERE origin_router_name = '$router' AND dest_router_name = '$other_router' AND origin_interface='$intf_name'";
	    my $sth3 = $cq->query($q3);
	    my ($count) = $sth_->fetchrow_array();
	    if (!$count) {
		# No adjacency
		print STDERR "$router and $other_router in mesh group $mesh_num, but do NOT share an adjacency on $router: $intf_name.\n" if !$quiet;
	    }
	}
    }

    # summary goes here
    
}


1;
