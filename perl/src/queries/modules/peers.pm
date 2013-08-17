#!/usr/bin/perl

package peers;

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

    my $peerfile = "../../conf/peers.txt";

    if (! -e $peerfile) {
	$peerfile = "../../../conf/peers.txt";
    }

    if (open(PEERS, "$peerfile")) {
	while (<PEERS>) {
	    chomp;
	    my $peerline = $_;
	    
	    foreach my $peer (split(',', $peerline)) {
		$peer =~ s/\s+//g;
		push (@{$self->{peerarray}}, $peer);
	    }
	}
    } else {
	print STDERR "warning: couldn't open $peerfile: $!\n";	
	print STDERR "\t ** assuming all eBGP neighbors are peers. **\n";

	my $q = "select distinct asn from $sessions where ebgp=1 order by asn";
	my $sth = $cq->query($q);

	while (my ($asn) = $sth->fetchrow_array()) {
	    push(@{$self->{peerarray}}, $asn);
	}

    }

    $self->{cmp_community} = 0;


    # nothing...
    return $self;
}


sub rms_equivalent {
    my $self = shift;
    my ($rm1, $rm2) = @_;
    my ($rm1_str, $rm2_str);

    # XXX removed "community_num" from these.  
    # should make this an option.

    my $com_str = "";
    if ($self->{cmp_community} == 1) {
	$com_str = "community_num, "
    }


    my $q = "select clause_num, pfxnum, permit, as_regexp_num, comm_regexp_num, localpref, med, origin, $com_str prepend from $route_maps where rmap_id=$rm1 order by clause_num";
    my $sth = $cq->query($q);

    while (my @rmarray = $sth->fetchrow_array()) {
	$rm1_str .= join(',', @rmarray);
    }


    my $q = "select clause_num, pfxnum, permit, as_regexp_num, comm_regexp_num, localpref, med, origin, $com_str prepend from $route_maps where rmap_id=$rm2 order by clause_num";
    my $sth = $cq->query($q);

    while (my @rmarray = $sth->fetchrow_array()) {
	$rm2_str .= join(',', @rmarray);
    }

    return $rm1_str eq $rm2_str;
}


sub consistent_export {
    my $self = shift;
    my ($peer, $quiet) = @_;
    my %rms = ();
    my %routers = ();

    my $q = "select export_rm, router_name from sessions where asn=$peer";
    my $sth = $cq->query($q);
    
    while (my ($rm, $router) = $sth->fetchrow_array()) {

	# route map is consistent
	if (!defined($rms{$rm}) && scalar(keys %rms)!=0) {

	    foreach my $seen_rm (sort {$a <=> $b} keys %rms) {
		if ($self->rms_equivalent($rm, $seen_rm)) {
		    $rm = $seen_rm;
		}
	    }

	}

	$rms{$rm}++;
	push(@{$routers{$rm}}, $router);
    }

    my $i=0;
    my $common_rm;
    foreach my $rm (sort {$rms{$b} <=> $rms{$a}} keys %rms) {
	if (!$i++) {
	    # skip most common
	    $common_rm = $rm;
	    next;
	}
	
	printf("WARNING: anomalous export to AS %d at %s (%d)\n",
	       $peer, join(',',@{$routers{$rm}}), $rm)
    }
    
    if ($i>1) {
	printf ("('normal' export to AS %d at %s)\n\n",
		$peer, join(",",@{$routers{$common_rm}}), $rms{$common_rm});
    }


}


sub consistent_import {
    my $self = shift;
    my ($peer, $quiet) = @_;
    my %rms = ();
    my %routers = ();

    my $q = "select import_rm, router_name from sessions where asn=$peer";
    my $sth = $cq->query($q);
    
    while (my ($rm, $router) = $sth->fetchrow_array()) {

	# route map is consistent
	if (!defined($rms{$rm}) && scalar(keys %rms)!=0) {

	    foreach my $seen_rm (sort {$a <=> $b} keys %rms) {
		if ($self->rms_equivalent($rm, $seen_rm)) {
		    $rm = $seen_rm;
		}
	    }

	}

	$rms{$rm}++;
	push(@{$routers{$rm}}, $router);
    }

    my $i=0;
    my $common_rm;
    foreach my $rm (sort {$rms{$b} <=> $rms{$a}} keys %rms) {
	if (!$i++) {
	    # skip most common
	    $common_rm = $rm;
	    next;
	}
	
	printf("WARNING: anomalous import to AS %d at %s (%d)\n",
	       $peer, join(',',@{$routers{$rm}}), $rm)
    }
    
    if ($i>1) {
	printf ("('normal' import to AS %d at %s)\n\n",
		$peer, join(",",@{$routers{$common_rm}}), $rms{$common_rm});
    }


}




sub consistent_export_peers {
    my $self = shift;
    my $quiet = shift;

    foreach my $peer (@{$self->{peerarray}}) {
	$self->consistent_export($peer, $quiet);
    }
}

sub consistent_import_peers {
    my $self = shift;
    my $quiet = shift;

    return if (!defined($self->{peerarray}));

    foreach my $peer (@{$self->{peerarray}}) {
	$self->consistent_import($peer, $quiet);
    }
}

######################################################################

sub no_transit_to_peer {

    my $self = shift;
    my $peer = shift;
    my $quiet = shift;
    my %peer_import = ();

    my $q = "select router_name, import_rm from sessions where asn=$peer and up=1";
    my $sth = $cq->query($q);
    
    while (my ($router_name, $import_rm) = $sth->fetchrow_array()) {
	
	# ensure that routes are tagged on import
	my $q_ = "select as_regexp_num, comm_regexp_num, community from route_maps, communities where rmap_id=$import_rm and route_maps.community_num=communities.community_num and permit=1";


	my $sth_ = $cq->query($q_);

	while (my ($asr_num, $cr_num, $comm) = $sth_->fetchrow_array()) {

	    # everything that comes in and the communities that get assigned
	    $peer_import{$peer}->{$router_name}->{$comm} = ($asr_num, $cr_num);
	}
    }


    ############################################################
    # check all of the export sessions to other peers

    my $q = sprintf("select router_name, asn, export_rm from sessions where asn!=$peer and asn in (%s) order by asn", join (',', @{$self->{peerarray}}));
    my $sth = $cq->query($q);
    while (my ($router_name, $asn, $export_rm) = $sth->fetchrow_array()) {
	my $q_ = "select as_regexp_num, comm_regexp_num from route_maps where rmap_id=$export_rm and permit=1";
	my $sth_ = $cq->query($q_);

	while (my ($asrn, $crn) = $sth_->fetchrow_array()) {

	    # test base case -- nothing defined
	    if (!$asrn && !$crn) {
		print "WARNING: no AS path or community-based filters from $peer to $asn at $router_name\n";
		last;

	    } elsif (!$crn) {
		
		my $as_regexp;
		my $q_asr = "select as_regexp from as_regexps where as_regexp_num=$asrn";
		my $sth_asr = $cq->query($q_asr);
		($as_regexp) = $sth_asr->fetchrow_array();

		
		print "WARNING: routes matching $as_regexp leaked to $peer at $router_name to $asn\n";
	    } else {


		# test specific cases
		my ($as_regexp, $comm_regexp);
		if ($asrn > 0) {
		    my $q_asr = "select as_regexp from as_regexps where as_regexp_num=$asrn";
		    my $sth_asr = $cq->query($q_asr);
		    ($as_regexp) = $sth_asr->fetchrow_array();

		}


		if ($crn > 0) {
		    my $q_cr = "select comm_regexp from comm_regexps where comm_regexp_num=$crn";
		    my $sth_cr = $cq->query($q_cr);
		    ($comm_regexp) = $sth_cr->fetchrow_array();

		}

		foreach my $in_router (keys %{$peer_import{$peer}}) {

		    foreach my $com_on_route
			(keys %{$peer_import{$peer}->{$in_router}}) {
			    
			if ($com_on_route =~ /$comm_regexp/) {
			    print "ERROR: exporting routes from $in_router with $com_on_route to $asn at $router_name\n";
			} 
		    }
		}


	    }

	}	

    }


    


}


sub no_transit_between_peers {
    
    my $self = shift;
    my $quiet = shift;

    return if (!defined($self->{peerarray}) ||
	       !(scalar(@{$self->{peerarray}})));

    foreach my $peer (sort {$a <=> $b} @{$self->{peerarray}}) {
	$self->no_transit_to_peer($peer, $quiet);
    }

}
