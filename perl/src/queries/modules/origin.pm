#!/usr/bin/perl

package origin;

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

sub network_has_route {

    my $self = shift;
    my $quiet = shift;

    if (!$quiet) {
	print STDERR "\n\nTesting that every network statement has a route.\n\n";
    }

    ############################################################

    my $q = "select router_name, prefix, mask from $networks";
    my $sth = $cq->query($q);

    while (my ($router, $network, $mask) = $sth->fetchrow_array()) {
	
	my $q_ = "select count(*) from $routes where router_name='$router' and prefix=$network";
	if ($mask > 0) { 
	    $q_ .= " and mask=$mask";
	}
	my $sth_ = $cq->query($q_);
	my ($route_exists) = $sth_->fetchrow_array();




	if (!$route_exists) {

	    my $ip_max = $network + ($mask^0xffffffff);

	    # test to see if an interface exists
	    my $q_ = "select count(*) from $interfaces where router_name='$router' and ip_min=$network";
	    if ($mask > 0) { 
		$q_ .= " and ip_max=$ip_max";
	    }
	    my $sth_ = $cq->query($q_);
	    my ($intf_exists) = $sth_->fetchrow_array();

	    if (!$intf_exists) {
		printf ("WARNING: $router, network %s/%s with no static route.\n", inet_ntoa_($network), inet_ntoa_($mask));
	    }
	}
	    
    }


}
