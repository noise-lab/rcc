#!/usr/bin/perl

package area;

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

# Check that the OSPF areas are configured consistently
sub check_consistent_configs {
    
}

sub check_backbone_existence {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();
    

    print STDERR "\nVerifying that a backbone area is configured if these is more than one OSPF routing area.\n" if !$quiet;

    # Check if there is more than one area configured
    my $q = "SELECT area FROM $area_info";
    my $sth = $cq->query($q);

    my $number_of_areas = 0;
    my $has_backbone = 0;
    while (my $area = $sth->fetchrow_array()) {
	$number_of_areas++;
	
	if ($area eq "0.0.0.0") {
	    $has_backbone = 1;
	}
    }
    
    # print summary here
    if (($number_of_areas > 1) && !$has_backbone) {
	print STDERR "This configuration has multiple areas defined but lacks a backbone area.\n";
    }
    
}

# Check that no areas are configured to be both stub areas and NSSAs
sub check_stub {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();
    

    print STDERR "\nVerifying that a backbone area is configured if these is more than one OSPF routing area.\n" if !$quiet;

    my $q = "SELECT area FROM $area_info WHERE stub = 1 AND nssa = 1";
    my $sth = $cq->query($q);

    my $count = 0;
    while (my $area = $sth->fetchrow_array()) {
	print STDERR "WARNING: $area is configured to be both a Stub Area and a NSSA.\n" if !$quiet;
	$count++;
    }
    
    # print summary
    print STDERR "\n$count areas configured as both Stub and NSSA.\n";
    
}


# Check that every interface with the same subnet IP address is in the same area
sub check_area_addresses {
    my $self = shift;
    my $quiet = shift;
    my @errors;
    
    print STDERR "\nVerifying that all interfaces with the same subnet IP address is in the same area.\n" if !$quiet;
    
    # Check every link (adjacency)
    my $q = "SELECT origin_router_name, dest_router_name, origin_area, dest_area FROM $adjacencies";
    my $sth = $cq->query($q);

    while (my ($origin_router, $dest_router, $origin_area, $dest_area) = $sth->fetchrow_array()) {
	if (!($origin_area eq $dest_area)) {
	    print STDERR "WARNING: $origin_router and $dest_router have the same subnet IP but are in different areas.\n" if !$quiet;
	    push (@errors,($origin_router, $dest_router));
	}
    }
    
    # print summary
    my $count = scalar(@errors)/2;
    print STDERR "\n===Summary===\n";
    print STDERR "Found $count errors.\n";
    
}

# Check that every non-backbone area is connected to the backbone
sub check_backbone_connectivity {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();
    my $number_of_areas = 0;

    print STDERR "\nVerifying that every non-backbone area is connected to the backbone.\n" if !$quiet;

    my $q = "SELECT area from $area_info";
    my $sth = $cq->query($q);

    while (my $area = $sth->fetchrow_array()) {
	
	# get all the routers with an interface in this area
	my $q1 = "SELECT router_name FROM $router_info WHERE enabled = 1 AND area = '$area'";
	my $sth1 = $cq->query($q1);
	while (my $router = $sth1->fetchrow_array()) {
	    my $q2 = "SELECT router_name WHERE router_name = '$router' AND area = '0.0.0.0'";

	    my $sth2 = $cq->query($q2);
	    my ($count) = $sth2->fetchrow_array();

	    if (!$count) {
		push(@errors,$area);
	    }
	}

	$number_of_areas++;
    }

    if (!$quiet && ($number_of_areas >= 2)) {
	foreach my $area (@errors) {
	    print STDERR "WARNING: OSPF Area $area is not connected to the backbone.\n";
	}
    }

    # summary
    print STDERR "\n===Summary===\n";
    my $count = scalar(@errors);
    if ($number_of_areas >=2) {
	print STDERR "Found $count OSPF Areas not connected to the backbone.\n";
    }
    else {
	print STDERR "Found 0 OSPF Areas not connected to the backbone.\n";
    }
}

1;
