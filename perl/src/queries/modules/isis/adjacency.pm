#!/usr/bin/perl

package adjacency;

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

# Check that all edges are bi-directional
sub check_dangling_adjacencies {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();
    my $dangling_errors = 0;
    my $loopback_errors = 0;
    my $disabled_errors = 0;


    print STDERR "\nVerifying that every IS-IS adjacency is configured on both ends.\n\n" if !$quiet;

    my $q = "SELECT router_name, ipv4_address FROM $router_interfaces WHERE (interface_name != 'lo0.0' OR interface_name NOT REGEXP 'Loopback.*') AND ipv4_address != 'none'";
    my $sth = $cq->query($q);

    while (my ($router, $ipv4_subnet_addr) = $sth->fetchrow_array()) {

	# check if another router has same subnet address
	my $q_ = "SELECT router_name FROM $router_interfaces WHERE ipv4_address = '$ipv4_subnet_addr' AND (interface_name != 'lo0.0' OR interface_name NOT REGEXP 'Loopback.*')";
	my $sth_ = $cq->query($q_);
	my ($count) = $sth_->fetchrow_array();

	if (!$count) {
	    print STDERR "WARNING: Dangling IS-IS adjacency: $router -> $ipv4_subnet_addr\n" if !$quiet;
	    push(@errors, ($router, $ipv4_subnet_addr));
	    $dangling_errors++;
	}

	# check to see if the adjacency is formed 
	# with a loopback interface
	my $q_ = "SELECT router_name FROM $router_interfaces WHERE ipv4_address = '$ipv4_subnet_addr' AND (interface_name = 'lo0.0' or interface_name REGEXP 'Loopback')";
	my $sth_ = $cq->query($q_);
	my ($count) = $sth_->fetchrow_array();
	if ($count) {
	    print STDERR "WARNING: IS-IS adjacency with a loopback interface: $router -> $ipv4_subnet_addr\n" if !$quiet;
	    push(@errors, ($router, $ipv4_subnet_addr));
	    $loopback_errors++;
	}

	# check to see if the adjacency is formed
	# with a disabled interface
	my $q_ = "SELECT router_name FROM $router_interfaces WHERE ipv4_address = '$ipv4_subnet_addr' AND level1_routing = 0 AND level2_routing = 0";
	my $sth_ = $cq->query($q_);
	my ($count) = $sth_->fetchrow_array();
	if ($count) {
	    print STDERR "WARNING: IS-IS adjacency with a disabled interface: $router -> $ipv4_subnet_addr\n" if !$quiet;
	    push(@errors, ($router, $ipv4_subnet_addr));
	    $disabled_errors++;
	}
    }

    # print summary
    print STDERR "\n===Summary===\n";
    print STDERR "Found $dangling_errors cases of dangling IS-IS adjacencies.\n";
    print STDERR "Found $loopback_errors cases of IS-IS adjacencies with a loopback interface.\n";
    print STDERR "Found $disabled_errors cases of IS-IS adjacencies with a disabled interface.\n";

    # return errors?
}


# Check that adjacency levels are matched
sub check_adjacency_levels {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();
    
    print STDERR "\nVerifying that every IS-IS adjacency is configured for the same levels on each end.\n\n" if !$quiet;

    # Start with Level 1 Adjacencies
    print STDERR "\nChecking Level 1 Adjacencies.\n" if !$quiet;

    my $q1 = "SELECT router_name, ipv4_address FROM $router_interfaces WHERE (interface_name != 'lo0.0' OR interface_name NOT REGEXP 'Loopback') AND ipv4_address != 'none' AND level1_routing = 1 AND level2_routing = 0";
    my $sth1 = $cq->query($q1);

    while (my ($router, $ipv4_subnet_addr) = $sth1->fetchrow_array()) {

	# check that all other routers with the 
	# same subnet address have Level 1 ENABLED
	my $q_1 = "SELECT router_name FROM $router_interfaces WHERE ipv4_address = '$ipv4_subnet_addr' AND level1_routing = 0";
	my $sth_1 = $cq->query($q_1);
	my ($count) = $sth_1->fetchrow_array();

	if ($count) {
	    print "WARNING: IS-IS adjacency DISABLED for Level 1 on other end: $router -> $ipv4_subnet_addr\n" if !$quiet;
	    push(@errors, ($router, $ipv4_subnet_addr));
	}
    }


		   
    # Level 2 Adjacencies
    print STDERR "\nChecking Level 2 Adjacencies.\n" if !$quiet;
    
    my $q2 = "SELECT router_name, ipv4_address FROM $router_interfaces WHERE (interface_name != 'lo0.0' or interface_name NOT REGEXP 'Loopback.*') AND ipv4_address != 'none' AND level1_routing = 0 AND level2_routing = 1";
    my $sth2 = $cq->query($q2);
    
    while (my ($router, $ipv4_subnet_addr) = $sth2->fetchrow_array()) {
		
	# check that all other routers with the 
	# same subnet address have level 2 ENABLED
	my $q_2 = "SELECT router_name FROM $router_interfaces WHERE ipv4_address = '$ipv4_subnet_addr' AND level2_routing = 0";
	my $sth_2 = $cq->query($q_2);
	my ($count) = $sth_2->fetchrow_array();

	if ($count) {
	    print STDERR "WARNING: IS-IS adjacency DISABLED for Level 2 on other end: $router -> $ipv4_subnet_addr\n" if !$quiet;
		push(@errors, ($router, $ipv4_subnet_addr));	
	}
    }
    
    
    # Level 1&2 Adjacencies
    print STDERR "\nChecking Level 1 and 2 Adjacencies.\n" if !$quiet;
    
    my $q3 = "SELECT router_name, ipv4_address FROM $router_interfaces WHERE (interface_name != 'lo0.0' or interface_name NOT REGEXP 'Loopback.*') AND ipv4_address != 'none' AND level1_routing = 1 AND level2_routing = 1";
    my $sth3 = $cq->query($q3);
    
    while (my ($router, $ipv4_subnet_addr) = $sth3->fetchrow_array()) {
	
	# check that all other routers with the 
	# same subnet address have Level 1 and/or Level 2 ENABLED
	my $q_1 = "SELECT router_name FROM $router_interfaces WHERE ipv4_address = '$ipv4_subnet_addr' AND level1_routing = 0 and level2_routing = 0";
	my $sth_1 = $cq->query($q_1);
	my ($count) = $sth_1->fetchrow_array();
	
	if ($count) {
	    print STDERR "WARNING: IS-IS adjacency DISABLED for Level 1 and 2 on other end: $router -> $ipv4_subnet_addr\n" if !$quiet;
		push(@errors, ($router, $ipv4_subnet_addr));	
	}
	
    }


    # print summary info


}



# Check that inter-area adjacencies are configured for level 2
# and intra-area adjacencies are configured for level 1
sub check_area_adjacencies {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();
    

    print STDERR "\nVerifying that every inter-area IS-IS adjacency is configured for Level 2 Routing.\n" if !$quiet;
    
    # Get the router names and their area addresses;
    my $q = "SELECT router_name, area_address FROM $router_info";
    my $sth = $cq->query($q);
    
    while (my ($origin_router, $origin_area_addr) = $sth->fetchrow_array()) {
	
	# get its adjacencies from the "adjacencies" table
	my $q_ = "SELECT dest_router_name,ipv4_subnet_address FROM $adjacencies WHERE origin_router_name='$origin_router'";
	my $sth_ = $cq->query($q_);
	
	while (my ($dest_router,$ipv4_subnet_address) = $sth_->fetchrow_array()) {
	    # Check if $dest_router is in another area
	    # and if so, that the adjacency is configured for
	    # Level 2 routing
	    my $q1 = "SELECT area_address FROM $router_info WHERE router_name = '$dest_router'";
	    my $sth1 = $cq->query($q1);
	    my @row = $sth1->fetchrow_array();
	    my $dest_area_addr = $row[0];
	    
	    # Compare to see if they match
	    if ($origin_area_addr eq $dest_area_addr) {

		# I don't think this is correct -- they can form a level 2 adjacency

		# intra-area adjacency
		# Check if both interfaces are configured for
		# Level 1 routing and warn if they are not since
		# no adjacency will be formed here
		
		# my $q2 = "SELECT router_name,interface_name,level1_routing FROM $router_interfaces WHERE ipv4_address='$ipv4_subnet_address' AND (router_name='$origin_router' OR router_name='dest_router')";
# 		my $sth2 = $cq->query($q2);
# 		while (my ($rtr,$interface,$level) = $sth2->fetchrow_array()) {
# 		    if ($level == 0) {
# 			print "WARNING: $origin_router and $dest_router have INTRA-AREA connection\n but $rtr on $interface NOT configured for Level 1 routing.\n" if !$quiet;
# 		    }
# 		}
		
	    }
	    else {
		# inter-area adjacency
		# Check if both interfaces are configured for
		# Level 2 routing and warn if they are not since
		# no adjacency will be formed here

		my $q2 = "SELECT router_name,interface_name,level2_routing FROM $router_interfaces WHERE ipv4_address='$ipv4_subnet_address' AND (router_name='$origin_router' OR router_name='dest_router')";
		my $sth2 = $cq->query($q2);
		while (my ($rtr,$interface,$level) = $sth2->fetchrow_array()) {
		    if ($level == 0) {
			print "WARNING: $origin_router and $dest_router have INTER-AREA connection\n but $rtr on $interface NOT configured for Level 2 routing.\n" if !$quiet;
		    }
		    
		}
	    }
	}
    }

    # Handle printing summary info later
}

1;
