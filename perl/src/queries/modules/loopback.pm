#!/usr/bin/perl

package loopback;

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

sub dangling_ibgp_session {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();
    my %router_errors = ();

    if (!$quiet) {
	print STDERR "\nVerifying that every iBGP session is connected on both ends.\n\n";
    }
    

    my $q = "select router_name, neighbor_ip from $sessions where ebgp=0";
    my $sth = $cq->query($q);

    while (my ($router, $nbr) = $sth->fetchrow_array()) {
	
	# test that there is some other router with this loopback addr
	my $q_ = "select count(*) from $router_loopbacks where loopback=$nbr";
	my $sth_ = $cq->query($q_);
	my ($count) = $sth_->fetchrow_array();
	
	if (!$count) {
	    my $nbr_ip = &inet_ntoa_($nbr);
	    printf ("WARNING: dangling iBGP session: $router -> %s\n",
			   $nbr_ip) if !$quiet;
	    push(@errors, ($router, $nbr_ip));
	    $router_errors{$router}=1;
	} else {

	    # need to test iBGP in the reverse direction
	    my $q_ = "select count(*) from sessions, router_loopbacks as to_lb, router_loopbacks as from_lb where to_lb.loopback=sessions.neighbor_ip and to_lb.router_name='$router' and from_lb.loopback=$nbr and from_lb.router_name=sessions.router_name";
	    my $sth_ = $cq->query($q_);
	    my ($count) = $sth_->fetchrow_array();

	    if (!$count) {
		my $q1 = "select router_name from $router_loopbacks where loopback=$nbr";
		my $sth1 = $cq->query($q1);
		my ($neighbor_name) = $sth1->fetchrow_array();

		printf ("WARNING: dangling iBGP session (reverse): $neighbor_name (%s) -> $router\n",
			&inet_ntoa_($nbr)) if !$quiet;
	    } else {
		# THE SESSION IS UP!
		my $c = "update $sessions set up=1 where router_name='$router' and neighbor_ip=$nbr";
		$cq->cmd($c);
	    }

	}
    }


    # print summary information
    if ($quiet==2) {
	my $q = "select count(*) from $sessions";
	my $sth = $cq->query($q);
	my ($num_sessions) = $sth->fetchrow_array();
	
	$q = "select count(distinct router_name) from $sessions";
	$sth = $cq->query($q);
	my ($num_routers) = $sth->fetchrow_array();

	printf("dangling iBGP sessions: %d (%.2f\%, ",
	       scalar(@errors), scalar(@errors)/$num_sessions*100,
	       scalar(keys %router_errors));

	printf ("%.2f pct of routers)\n", scalar(keys %router_errors)/$num_routers*100) ;

    }
    
    return \@errors;
}


sub duplicate_ibgp_session {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();
    my %router_errors = ();

    if (!$quiet) {
	print STDERR "\nVerifying no duplicate iBGP sessions.\n\n";
    }
    

    my $q = "select router_name, neighbor_ip from $sessions where ebgp=0";
    my $sth = $cq->query($q);

    while (my ($router, $nbr) = $sth->fetchrow_array()) {
	
	# test that there is some other router with this loopback addr
	my $q_ = "select count(*) from $router_loopbacks where loopback=$nbr";
	my $sth_ = $cq->query($q_);
	my ($count) = $sth_->fetchrow_array();
	
	if ($count>1) {
	    my $nbr_ip = &inet_ntoa_($nbr);
	    printf ("ERROR: duplicate iBGP session: $router -> %s\n",
			   $nbr_ip) if !$quiet;
	    push(@errors, ($router, $nbr_ip));
	    $router_errors{$router}=1;
	}

    }

    # print summary information
    if ($quiet==2) {
	my $q = "select count(*) from $sessions";
	my $sth = $cq->query($q);
	my ($num_sessions) = $sth->fetchrow_array();

	$q = "select count(distinct router_name) from $sessions";
	$sth = $cq->query($q);
	my ($num_routers) = $sth->fetchrow_array();

	my $num_router_errors = scalar(keys %router_errors);
	

	printf("duplicate iBGP sessions: %d (%.2f\%, ",
	       scalar(@errors), scalar(@errors)/$num_sessions*100,
	       scalar(keys %router_errors));

	printf ("%.2f pct of routers)\n", scalar(keys %router_errors)/$num_routers*100) ;
    }
    
    return \@errors;
}

1;
