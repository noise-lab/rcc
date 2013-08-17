#!/usr/bin/perl

package filters;

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

    $self->{bogon_list};

    return $self;

}

sub get_bogon_prefixes {

    my $self = shift;
    my $quiet = shift;

    my $q = "select ip_min, ip_max, mask from bogon_list order by ip_min,ip_max,mask";
    my $sth = $cq->query($q);
    while (my ($ip_min, $ip_max, $mask) = $sth->fetchrow_array()) {
	my $idx = scalar(keys %{$self->{bogon_list}}) + 1;
	$self->{bogon_list}->{$idx}->{min} = $ip_min;
	$self->{bogon_list}->{$idx}->{max} = $ip_max;
	$self->{bogon_list}->{$idx}->{mask} = $mask;
    }
    
}

sub remove_private_as {
    
    my $self = shift;
    my $quiet = shift;


    # we also check here that the import and export route map 
    # are actually sending some routes

    # this query was causing mysql to hang in certain cases.
    # simplify/ break into multiple queries

#    my $q = "select router_name,inet_ntoa(neighbor_ip),asn,max(import.permit), max(export.permit) from sessions,route_maps as import,route_maps as export where up=1 and asn>64511 and remove_priv=0 and sessions.import_rm=import.rmap_id and sessions.export_rm=export.rmap_id group by session_id";

    my $q = "select router_name,inet_ntoa(neighbor_ip),asn,import_rm, export_rm from sessions where up=1 and asn>64511 and remove_priv=0";


    my $sth = $cq->query($q);
    while (my ($router, $nbr, $as, $import_rm, $export_rm) = $sth->fetchrow_array()) {
	
	# get permit_in and permit_out
	my $q_ = "select permit from route_maps where rmap_id=$import_rm";
	my $sth_ = $cq->query($q_);
	my ($permit_in) = $sth_->fetchrow_array();


	$q_ = "select permit from route_maps where rmap_id=$export_rm";
	$sth_ = $cq->query($q_);
	my ($permit_out) = $sth_->fetchrow_array();

	if ($permit_in>0 && $permit_out>0) {
	    printf ("WARNING: $router: private AS number $as from $nbr not filtered\n");
	}
    }
    


}


sub test_bogon_prefixes {

    my $self = shift;
    my $quiet = shift;

    $self->get_bogon_prefixes();

    # just look at crisco (vendor=0) for now 
    my $q = "select sessions.router_name, neighbor_ip, sessions.asn, import_rm, export_rm, import_acl, export_acl from router_global,sessions where (router_global.router_name=sessions.router_name) and vendor=0 and ebgp=1 and up=1 order by router_name,asn";
    my $sth = $cq->query($q);

    while (my ($router, $neighbor, $asn, $import_rm, $export_rm, $import_acl, $export_acl) =
	   $sth->fetchrow_array()) {
	if (!($import_acl || $import_rm)) {
	    printf ("WARNING: no import ACL or route map on $router to $asn (%s)\n",
		    &inet_ntoa_($neighbor));
	} else {


	    foreach my $idx (sort {$self->{bogon_list}->{$a}->{min} <=>
				       $self->{bogon_list}->{$b}->{min}} keys %{$self->{bogon_list}}) {

		my $acl_permits = 0;
		my $rm_permits = 0;
		
		my $ip_min_bog = $self->{bogon_list}->{$idx}->{min};
		my $ip_max_bog = $self->{bogon_list}->{$idx}->{max};
		my $mask_bog = $self->{bogon_list}->{$idx}->{mask};

		if ($import_acl > 0) {
		    # apply the filter to each bogon in the list
		    my $q_ = "select ip_min, ip_max, mask_min, mask_max, permit from prefix_acls where num=$import_acl order by clause_num";
		    my $sth_ = $cq->query($q_);
		    
		    while (my ($ip_min, $ip_max, $mask_min, $mask_max, $permit) = $sth_->fetchrow_array()) {
			
			if (($ip_min <= $ip_min_bog) && ($ip_max >= $ip_max_bog) &&
			    ($mask_min <= $mask_bog) && ($mask_max >= $mask_bog)) {
			    
			    # explicitly permitting a bogon
			    if ($permit)  {
				$acl_permits = 1;
			    } else {
				$acl_permits = 0;
			    }
			    last;
			    
			}
		    }
		} else {
		    $acl_permits = 1;
		}

		if ($acl_permits) {
	    
		    my $q_ = "select pfxnum, as_regexp_num, comm_regexp_num, permit from route_maps where rmap_id=$import_rm order by clause_num";
		    my $sth_ = $cq->query($q_);
		    
		    while (my ($pfxnum, $asr, $cr, $permit) = $sth_->fetchrow_array()) {

			if (!$pfxnum && !$asr && !$cr) {
			    $rm_permits = $permit;
			    last;
			} else {
			    
			    my $q_acl = "select ip_min, ip_max, mask_min, mask_max, permit from prefix_acls where num=$import_acl order by clause_num";
			    my $sth_acl = $cq->query($q_acl);
			    
			    while (my ($ip_min, $ip_max, $mask_min, $mask_max, $aclpermit) = $sth_acl->fetchrow_array()) {


				if (($ip_min <= $ip_min_bog) && ($ip_max >= $ip_max_bog) &&
				    ($mask_min <= $mask_bog) && ($mask_max >= $mask_bog)) {


				    if ($aclpermit && $permit)  {
					$rm_permits = 1;
				    } elsif ($aclpermit && !$permit) {
					$rm_permits = 0;
				    }
				    last;
				}
			    }
			    
			}
		    }
		    ##############################

		    if ($acl_permits && $rm_permits) {
			printf ("ERROR: $router: ACL/RM <- $asn (%s) permits %s/%d\n",
				&inet_ntoa_($neighbor), &inet_ntoa_($ip_min_bog), $mask_bog);
		    }

		}
		
		

	    }


	}

    }


}
