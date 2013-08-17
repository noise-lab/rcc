#!/usr/bin/perl

package prepend;

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

sub prepend_own_as {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();

    if (!$quiet) {
	print STDERR "\nVerifying no bogus AS path prepending.\n\n";
    }


    # XXX should handle the 'local-as' option...

    my $q = "select rmap_id, prepend from $route_maps where prepend!=''";
    my $sth = $cq->query($q);
    while (my ($rmap_id, $prepend) = $sth->fetchrow_array()) {

	# the unique ASes that are prepended by this route map
	my %uniq_as;
	my @ases = split (/\s+/, $prepend);
	foreach my $as (@ases) {
	    $uniq_as{$as} = 1;
	}

	# get the routers where this route map was used
	my $q_ = "select router_name, asn from $sessions where import_rm=$rmap_id or export_rm=$rmap_id";
	my $sth_ = $cq->query($q_);
	while (my ($router) =  $sth_->fetchrow_array()) {

	    my $q__ = "select asn from $router_global where router_name='$router'";
	    my $sth__ = $cq->query($q__);
	    my ($asn) = $sth__->fetchrow_array();
	    

	    foreach my $as (keys %uniq_as) {
		if ($as != $asn) {
		    printf ("WARNING: prepending w/foreign AS $as at router (local AS is $asn) %s\n",
			    $router) if !$quiet;
		    push(@errors, $router, $asn);
		}
	    }
	}

    }

    if ($quiet==2) {
	my $q = "select count(*) from $sessions";
	$sth = $cq->query($q);
	my ($num_sessions) = $sth->fetchrow_array();
	
	printf("sessions w/bad prepends: %d (%.2f\%)\n",
	       scalar(@errors), scalar(@errors)/$num_sessions*100);
    }

    return \@errors;

}
