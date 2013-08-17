#!/usr/bin/perl

package links;

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


# Check for dangling links
sub check_dangling_links {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();
    my $dangling_errors = 0;
    my $loopback_errors = 0;
    my $disabled_errors = 0;

    print STDERR "\nVerifying that every OSPF link is configured on both ends.\n" if !$quiet;

    my $q = "SELECT router_name, ipv4_address FROM $router_interfaces WHERE (interface_name != 'lo0.0' OR interface_name NOT REGEXP 'Loopback.*') AND ipv4_address != 'none'";
    my $sth = $cq->query($q);

    while (my ($router, $ipv4_subnet_addr) = $sth->fetchrow_array()) {

	# check if another router has same subnet address
	my $q_ = "SELECT router_name FROM $router_interfaces WHERE ipv4_address = '$ipv4_subnet_addr' AND (interface_name != 'lo0.0' OR interface_name NOT REGEXP 'Loopback.*')";
	my $sth_ = $cq->query($q_);
	my ($count) = $sth_->fetchrow_array();

	if (!$count) {
	    print "WARNING: Dangling OSPF link: $router -> $ipv4_subnet_addr\n" if !$quiet;
	    push(@errors, ($router, $ipv4_subnet_addr));
	$dangling_errors++;
	}
	# check to see if the adjacency is formed 
	# with a loopback interface
	my $q_ = "SELECT router_name FROM $router_interfaces WHERE ipv4_address = '$ipv4_subnet_addr' AND (interface_name = 'lo0.0' or interface_name REGEXP 'Loopback')";
	my $sth_ = $cq->query($q_);
	my ($count) = $sth_->fetchrow_array();
	if ($count) {
	    print "WARNING: OSPF link with a loopback interface: $router -> $ipv4_subnet_addr\n" if !$quiet;
	    push(@errors, ($router, $ipv4_subnet_addr));
	    $loopback_errors++;
	}

	# check to see if the adjacency is formed
	# with a disabled interface
	my $q_ = "SELECT router_name FROM $router_interfaces WHERE ipv4_address = '$ipv4_subnet_addr' AND enabled = 0";
	my $sth_ = $cq->query($q_);
	my ($count) = $sth_->fetchrow_array();
	if ($count) {
	    print "WARNING: OSPF with a disabled interface: $router -> $ipv4_subnet_addr\n" if !$quiet;
	    push(@errors, ($router, $ipv4_subnet_addr));
	    $disabled_errors++;
	}
    }

    # print summary
    print STDERR "\n===Summary===\n";
    print STDERR "Found $dangling_errors cases of dangling OSPF links.\n";
    print STDERR "Found $loopback_errors cases of OSPF links with a loopback interface.\n";
    print STDERR "Found $disabled_errors cases of OSPF links with a disabled interface.\n";

    # return errors?
}


1;
