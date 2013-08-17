#!/usr/bin/perl

package ibgp;

BEGIN {
    push(@INC, "../../../lib");
}

use strict;
use ConfigCommon;
use ConfigDB;
use ConfigQuery;
use Data::Dumper;

my $cq = new ConfigQuery;

sub new {
    my ($class) = @_;
    my $self = {};
    bless ($self, $class);
    return $self;
}

sub duplicate_routerids_lbs {
    my $self = shift;
    my $quiet = shift;

    if (!$quiet) {
	print STDERR "Testing for duplicate router-ids and loopbacks.\n\n";
    }


    ############################################################
    # search for duplicate loopbacks

    my @dup_loopbacks;

    # allow duplicates of "127.0.0.1"
    # mandatory for mpls ping on junipers

    my $q = "select loopback, count(*) as x from $router_loopbacks where loopback!=2130706433 group by loopback order by x desc";
    my $sth = $cq->query($q);

    my $total_dlb = 0;
    my $total_zero_rid = 0;
    
    while (my ($lb, $cnt) = $sth->fetchrow_array()) {
	last if ($cnt < 2);
	push (@dup_loopbacks, $lb);
	$total_dlb += $cnt;
    }

    if ($quiet==2) {
	printf ("routers w/duplicate loopback: %d\n", $total_dlb);
    }


    foreach my $lb (@dup_loopbacks) {
	my @routers;
	my @default_rid;
	
	my $q = "select router_name from $router_loopbacks where loopback=$lb";
	my $sth = $cq->query($q);

	while (my ($router_name) = $sth->fetchrow_array()) {
	    push(@routers, $router_name);
	}

	foreach my $rtr (@routers) {
	    my $q = "select routerid from $router_global where router_name='$rtr'";
	    my $sth = $cq->query($q);
	    my ($rid) = $sth->fetchrow_array();
	    push(@default_rid, $rtr) if (!$rid);
	    $total_zero_rid++ if (!$rid);
	}

	printf ("ERROR: %d routers with loopback %s (%s)\n\t %d with default router-id (%s)\n",
		scalar(@routers), &inet_ntoa_($lb),
		join(',', @routers), scalar(@default_rid),
		join(',', @default_rid))
	    if (!$quiet);

    }

    if ($quiet==2) {
		printf ("routers w/duplicate loopback and default routerid: %d\n", $total_zero_rid); 
    }

    ############################################################
    # search for duplicate router-ids

    my @dup_rid;
    my $total_dup_rid = 0;
    
    my $q = "select routerid, count(*) as x from $router_global where routerid>0 group by routerid order by x desc";
    my $sth = $cq->query($q);
    while (my ($rid, $cnt) = $sth->fetchrow_array()) {
	last if ($cnt < 2);

	$total_dup_rid ++;
	my @routers;
	
	my $q_ = "select router_name from $router_global where routerid=$rid";
	my $sth_ = $cq->query($q_);
	while (my ($rtr) = $sth->fetchrow_array()) {
	    push (@routers, $rtr);
	}
	
	printf ("ERROR: duplicate non-zero router-id (%s)\n",
		join(',',@routers)) if (!$quiet);
    }

    if ($quiet==2) {
		printf ("routers w/duplicate routerid: %d\n", $total_dup_rid); 
    }





}

sub client_cluster {
    my $self = shift;
    my $quiet = shift;

    if (!$quiet) {
	print STDERR "\nVerifying that RR clients in a cluster connect to all RRs in that cluster.\n\n";
    }


    my %sessions_cluster = ();
    my %cluster_rrs = ();
    my @bad_clusters = ();

# no longer need to do this join since the info is in the "sessions" table.
# my $q = "select $sessions.router_name, $router_global.clusterid, count(*) as x from ($sessions natural left join $router_global) where rr_client=1 and up=1 group by router_name";
    my $q = "select router_name, clusterid, count(*) as x from $sessions where rr_client=1 and up=1 group by router_name";
    my $sth = $cq->query($q);
    
    while (my ($router, $cid, $num_sessions) = $sth->fetchrow_array()) {

	push(@{$cluster_rrs{$cid}}, $router);

	if (!defined($sessions_cluster{$cid})) {
	    $sessions_cluster{$cid} = $num_sessions;
	} elsif ($sessions_cluster{$cid} != $num_sessions) {
	    push(@bad_clusters, $cid);
	}
    }



    if ($quiet==2) {
	my $num_bad = scalar(@bad_clusters);

	# [formerly from ($router_global natural left join $sessions) ]
	my $q = "select count(distinct clusterid) from $sessions where up=1";

	my $sth = $cq->query($q);
	my ($num_clusters) = $sth->fetchrow_array();

	printf ("RR clusters w/unequal # of iBGP sessions: %d (%.2f pct of clusters)\n",
		$num_bad, $num_bad/$num_clusters*100);

    } else {
	# look in greater detail at the clusters whose RRs have
	# different numbers of active iBGP sessions

	foreach my $cid (@bad_clusters) {
	    my %clients = ();

	    foreach my $rr (@{$cluster_rrs{$cid}}) {
		my $q = "select neighbor_ip from $sessions where router_name='$rr' and rr_client=1 and up=1";
		my $sth = $cq->query($q);

		while (my ($nbr) = $sth->fetchrow_array()) {
		    $clients{$rr}->{$nbr} = 1;
		}
	    }

	    foreach my $rr1 (@{$cluster_rrs{$cid}}) {
		foreach my $client (keys %{$clients{$rr1}}) {
		    foreach my $rr2 (@{$cluster_rrs{$cid}}) {
			
			if (!defined($clients{$rr2}->{$client})) {

			    my $q = "select router_name from $router_loopbacks where loopback=$client";
			    my $sth = $cq->query($q);
			    my ($cname) = $sth->fetchrow_array();

			    print "ERROR: $rr1 has RR client $cname, $rr2 doesn't (cluster $cid)\n" if !$quiet;
			}


		    }
		}
	    }
	}
    }
}


#my $num_down_summary = "select sessions.router_name, clusterid, count(*) as x from (sessions natural left join router_global), router_loopbacks where rr_client=1 and neighbor_ip=router_loopbacks.loopback group by router_name";


sub signaling_mesh {
    my $self = shift;
    my $quiet = shift;

    my %clique_rtrs = ();
    my %clique_id = ();
    my $num_cliques = 0;

    my $join_restrictions = "$sessions.neighbor_ip=neighbor.loopback and $sessions.router_name=from_global.router_name and neighbor.router_name=to_global.router_name and up=1 and rr_client=0 and from_global.clusterid!=to_global.clusterid";
    

    my $q = "select $sessions.router_name, neighbor.router_name, from_global.clusterid, to_global.clusterid from $sessions, $router_loopbacks as neighbor, $router_global as from_global, $router_global as to_global where $join_restrictions order by $sessions.router_name";
    my $sth = $cq->query($q);
    
    while (my ($from, $to, $fromcid, $tocid) = $sth->fetchrow_array()) {

	my $q = "select rr_client from $sessions, $router_loopbacks as neighbor where $sessions.neighbor_ip=neighbor.loopback and $sessions.router_name='$to' and neighbor.router_name='$from'";
	my $sth = $cq->query($q);
	my ($rrc) = $sth->fetchrow_array();
	next if ($rrc);


	# should check that $from and $to connect to every
	# one of the same sessions
	
	my %frmclique = ();
	my %toclique = ();
	my %clusterid = ();
	
	my $pass = 1;
	
	my $q1 = "select neighbor.router_name, to_global.clusterid from $sessions, $router_loopbacks as neighbor, $router_global as from_global, $router_global as to_global where $join_restrictions and $sessions.router_name='$from' and to_global.router_name!='$to'";
	my $sth1 = $cq->query($q1);
	while (my ($rtr, $cid) = $sth1->fetchrow_array()) {
	    $frmclique{$rtr} = 1;
	    $clusterid{$rtr} = $cid;
	}
		
	$q1 = "select neighbor.router_name, to_global.clusterid from $sessions, $router_loopbacks as neighbor, $router_global as from_global, $router_global as to_global where $join_restrictions and $sessions.router_name='$to' and to_global.router_name!='$from'";
	
	$sth1 = $cq->query($q1);
	while (my ($rtr, $cid) = $sth1->fetchrow_array()) {
	    $toclique{$rtr} = 1;
	    $clusterid{$rtr} = $cid;
	}
	
	foreach my $fr (keys %frmclique) {
	    if (!defined($toclique{$fr})) {
		print "$to clique is missing $fr (in $from clique)\n" if $clusterid{$fr} != $tocid;
		$pass = 0;
	    }
	}
	
	foreach my $tr (keys %toclique) {
	    if (!defined($frmclique{$tr})) {
		print "$from clique is missing $tr (in $to clique)\n" if $clusterid{$tr} != $fromcid;
		$pass = 0;
	    }
	}


	if (!defined($clique_id{$from})) {
	    
	    if (defined($clique_id{$to})) {

		# should check that $from and $to connect to every
		# one of the same sessions
		
		# assign the from router to $to's clique
		$clique_id{$from} = $clique_id{$to};
		$clique_rtrs{$num_cliques}->{$from} = 1;

	    } else {
		# neither is defined -- new clique

		$num_cliques++;
		$clique_id{$from} = $num_cliques;
		$clique_id{$to} = $num_cliques;

		$clique_rtrs{$num_cliques}->{$from} = 1;
		$clique_rtrs{$num_cliques}->{$to} = 1;

	    }

	} else {
	    # the $from router has been assigned to a clique

	    if (!defined($clique_id{$to})) {
		# assign the $to rotuer to $from's clique
		
		$clique_id{$to} = $clique_id{$from};
		$clique_rtrs{$num_cliques}->{$to} = 1;

	    } else {
		# both have been assigned -- make sure that 
		# they are in the same clique
		
		my %frmclique = ();
		my %toclique = ();
		my %clusterid = ();
		my $pass = 1;

		if ($clique_id{$to} != $clique_id{$from}) {
		    # check that each connects to every other session
		    # in the other's clique
		    # try to merge


		    my $q1 = "select neighbor.router_name, to_global.clusterid from $sessions, $router_loopbacks as neighbor, $router_global as from_global, $router_global as to_global where $join_restrictions and $sessions.router_name='$from' and to_global.router_name!='$to'";
		    my $sth1 = $cq->query($q1);
		    while (my ($rtr, $cid) = $sth1->fetchrow_array()) {
			$frmclique{$rtr} = 1;
			$clusterid{$rtr} = $cid;
		    }

		    $q1 = "select neighbor.router_name, to_global.clusterid from $sessions, $router_loopbacks as neighbor, $router_global as from_global, $router_global as to_global where $join_restrictions and $sessions.router_name='$to' and to_global.router_name!='$from'";

		    $sth1 = $cq->query($q1);
		    while (my ($rtr, $cid) = $sth1->fetchrow_array()) {
			$toclique{$rtr} = 1;
			$clusterid{$rtr} = $cid;
		    }

		    foreach my $fr (keys %frmclique) {
			if (!defined($toclique{$fr})) {
			    print "$to clique is missing $fr (in $from clique)\n" if $clusterid{$fr} != $tocid;
			    $pass = 0;
			}
		    }

		    foreach my $tr (keys %toclique) {
			if (!defined($frmclique{$tr})) {
			    print "$from clique is missing $tr (in $to clique)\n" if $clusterid{$tr} != $fromcid;
			    $pass = 0;
			}
		    }

		    if ($pass) {
			# merge the two cliques (postmortem)
			
		    }



		} 


	    }

	}
	
    }
    
}


sub no_synchronization {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();

    if (!$quiet) {
	print STDERR "Testing for no synchronization.\n\n";
    }


    my $q = "select router_name from $router_global where bgp=1 and no_sync=0";
    my $sth = $cq->query($q);

    while (my ($router) = $sth->fetchrow_array()) {
	printf ("WARNING: %s has synchronization enabled\n", $router) if !$quiet;
	push (@errors, $router);
    }

    if ($quiet==2) {
	my $q = "select count(distinct router_name) from $router_global";
	my $sth = $cq->query($q);
	my ($num_routers) = $sth->fetchrow_array();

	printf("routers w/o no synchronization: %d (%.2f\%)\n",
	       scalar(@errors), scalar(@errors)/$num_routers*100);
    }
    return \@errors;
}



sub build_adjacencies_and_levels {

    my $self = shift;

    my %visited = ();
    my $restrictions = "up=1 and ebgp=0";

    print STDERR "building adjacencies and calculating RR levels...";
    my $q = "select distinct router_name from $sessions where $restrictions";
    my $sth = $cq->query($q);
    
    while (my ($router) = $sth->fetchrow_array()) {

	if (!scalar(keys %{$self->{level}})) {
	    $self->{level}->{$router} = 0;
	}
	$self->adjacency_check($router, \%visited);
    }
    print STDERR "done.\n";

}

sub signaling_dag {
    my $self = shift;
    my $quiet = shift;
    my (@errors) = ();

    if (!$quiet) {
	print STDERR "Verifying that the route reflector hierarchy is acyclic.\n\n";
    }


    if (!defined($self->{adjacencies})) {
	$self->build_adjacencies_and_levels();
    }

    # iterate again through all routers
    foreach my $rtr (sort keys %{$self->{adjacencies}}) {
	my %loop_visit = ();
	$self->test_no_level_loops($rtr, $self->{level}->{$rtr}, \%loop_visit);
    }
    

}

sub signaling_connect {
    my $self = shift;
    my $quiet = shift;
    my (@errors) = ();

    if (!$quiet) {
	print STDERR "Verifying iBGP signaling connectedness.\n\n";
    }

    if (!defined($self->{adjacencies})) {
	$self->build_adjacencies_and_levels();
    }

    # iterate again through all routers
    foreach my $rtr (sort keys %{$self->{adjacencies}}) {
	my ($gone_down, $last_over) = (0, 0);
	my %visited = ();
	my @err = ();

	$self->test_level_connected($rtr, $gone_down, $last_over, \%visited);

	# see if we reached every router from this one
	foreach my $dest_rtr (sort keys %{$self->{adjacencies}}) {
	    if (!defined($visited{$dest_rtr})) {
		push(@err, $dest_rtr);
	    }
	}
	
	printf ("$rtr can't reach (%s)\n",
		join(',', @err)) if scalar(@err);
    }
}


sub test_level_connected {
    my $self = shift;

    my ($router, $gone_down, $last_over, $rvisited) = @_;
    my $curr_level = $self->{level}->{$router};
    $rvisited->{$router} = 1;

    foreach my $adj (keys %{$self->{adjacencies}->{$router}}) {

	next if ($rvisited->{$adj});

	my $adj_level = $self->{level}->{$adj};

	if ($adj_level==$curr_level) {
	    if (!$last_over && !$gone_down) {
		$self->test_level_connected($adj, $gone_down, 1, $rvisited);
	    }
	} elsif ($adj_level < $curr_level) {
	    $self->test_level_connected($adj, 1, $last_over, $rvisited);
	} elsif ($adj_level > $curr_level) {
	    $self->test_level_connected($adj, $gone_down, $last_over, $rvisited);
	}
    }

}


sub test_no_level_loops {
    my $self = shift;
    my ($router, $min_level, $rloop_visit) = @_;

    my $curr_level = $self->{level}->{$router};
    $rloop_visit->{$router} = $curr_level;

    # follow each adjacency.  make sure that 
    # levels are non-increasing or non-decreasing

    foreach my $adj (keys %{$self->{adjacencies}->{$router}}) {
	my $adj_level = $self->{level}->{$adj};

	if ((defined($rloop_visit->{$adj})) &&
	    $min_level < $rloop_visit->{$adj} &&
	    !defined($self->{adjacencies}->{$adj}->{$router})) {
	    print STDERR "FOUND LOOP\n";
	    foreach my $rtr (keys %$rloop_visit) {
		print "$rtr $rloop_visit->{$rtr}\n";
	    }
	}


	# follow the tree "down" to other route reflector clients
	if ($adj_level <= $curr_level && !defined($rloop_visit->{$adj})) {
	    $self->test_no_level_loops($adj, $adj_level, $rloop_visit);
	}
    }
    

}

sub adjacency_check {

    # this figures out the levels of the route reflector hierarchy 
    # by doing a depth-first search through the route reflector graph

    my $self = shift;
    my ($router, $rvisited) = @_;

    my $restrictions = "up=1 and ebgp=0";

	my @to_check = ();
	if (!$rvisited->{$router}) {
	# check all sessions for $router

	    my $q_ = "select $sessions.router_name, $router_loopbacks.router_name, $sessions.rr_client from $sessions,$router_loopbacks where $restrictions and $sessions.router_name='$router' and $sessions.neighbor_ip=$router_loopbacks.loopback";
	    my $sth_ = $cq->query($q_);
	    
	    while (my ($from_router, $to_router,
		       $rr_client) = $sth_->fetchrow_array()) {
		
		my $rr_client_rev;

		# build a list of router adjacencies
		# used for recursion
		push(@to_check, $to_router);

		# used so signaling_dag has a record of it
		$self->{adjacencies}->{$from_router}->{$to_router} = 1;
		
		if (!$rr_client) {
		    
		    my $rrq = "select $sessions.rr_client from $sessions, $router_loopbacks where $restrictions and $sessions.router_name='$to_router' and $router_loopbacks.router_name='$from_router' and $sessions.neighbor_ip=$router_loopbacks.loopback";
		    my $sth_rr = $cq->query($rrq);
		    ($rr_client_rev) = $sth_rr->fetchrow_array();
		    
		    if (!$rr_client_rev) {

			# iBGP "peer"
			$self->{level}->{$to_router} = $self->{level}->{$from_router};

		    } else {
			$self->{level}->{$to_router} = $self->{level}->{$from_router} + 1;
		    }
		    
		} else {
		    $self->{level}->{$to_router} = $self->{level}->{$from_router} - 1;
		}

#		printf STDERR ("$from_router (%d), $to_router (%d), %d, %d\n",
#			       $self->{level}->{$from_router}, $self->{level}->{$to_router},
#			       $rr_client, $rr_client_rev);

	    }


	}
	$rvisited->{$router} = 1;

    foreach my $rtr (@to_check) {
	$self->adjacency_check($rtr, $rvisited);
    }
}


############################################################

# get the top level of the signaling hierarchy
sub get_top_level_rrs {

    my $self = shift;
    my $rtop = shift;


    ####################

    my %routers_clients = ();

    ####################

    # get all routers that are not route reflector clients of 
    # anyone this is the top level of the RR hierarchy

    my $restrictions = "up=1 and ebgp=0";

    my $q = "select distinct router_loopbacks.router_name from sessions,router_loopbacks where ebgp=0 and rr_client=1 and sessions.neighbor_ip=router_loopbacks.loopback";
    my $sth = $cq->query($q);

    while (my ($rtr_client) = $sth->fetchrow_array()) {
	$routers_clients{$rtr_client} = 1;
    }
    

    $q = "select distinct router_name from sessions where ebgp=0";
    $sth = $cq->query($q);
    while (my ($rtr) = $sth->fetchrow_array()) {
	if (!defined($routers_clients{$rtr})) {
	    $rtop->{$rtr} = 1;
	}
    }



    return $rtop;

}


sub signaling_connect_top {

    my $self = shift;
    my $quiet = shift;

    my %routers_top;
    $self->get_top_level_rrs(\%routers_top);


    foreach my $rtr (sort keys %routers_top) {

	my %ibgp_sessions = ();
	my $restrictions = "up=1 and ebgp=0";

	my $q = "select distinct router_loopbacks.router_name from sessions,router_loopbacks where $restrictions and sessions.neighbor_ip=router_loopbacks.loopback and sessions.router_name='$rtr' and rr_client=0";
	my $sth = $cq->query($q);

	while (my ($rtr_nbr) = $sth->fetchrow_array()) {
	    $ibgp_sessions{$rtr_nbr} = 1;
	}

	printf STDERR "%d top-level sessions at $rtr\n", scalar(keys %ibgp_sessions) if $debug;

	foreach my $rtr_nbr (sort keys %routers_top) {
	    if (!defined($ibgp_sessions{$rtr_nbr}) &&
		!($rtr eq $rtr_nbr)) {
		print "ERROR: iBGP signaling partition -- $rtr is missing session to $rtr_nbr\n";
	    } else {
#		print "$rtr_nbr, ";
	    }
	}
#	print "\n\n";


    }
}


sub print_top_level_rrs {

    my $self = shift;
    my $quiet = shift;

    my %routers_top;
    $self->get_top_level_rrs(\%routers_top);

    printf ("%s\n", join("\n", sort keys %routers_top));
}


