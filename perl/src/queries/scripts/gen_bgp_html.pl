#!/usr/bin/perl

BEGIN {
    push(@INC, "../../../lib/");

    # these are for the "menu.pl" script, which
    # requires different relative paths
    push(@INC, "../../lib/");
}


use strict;
use ConfigDB;
use ConfigCommon;
use ConfigQuery;
use Getopt::Long;

############################################################

my %options = ();
GetOptions(\%options, "basedir=s");

if (!defined($options{'basedir'})) {
    die "Error: Must define base output directory."
    }
my $basedir = sprintf("%s/bgp_summary/",
		      $options{'basedir'});
system("mkdir -p $basedir");


my $cq = new ConfigQuery;

############################################################

my %bgp_files = ('iBGP sessions' => 'ibgp_sessions.html',
		 'eBGP sessions' => 'ebgp_sessions.html');


############################################################

sub print_route_maps {
    my $rrm = shift;
    my %route_maps = %$rrm;

    foreach my $rm (sort {$a <=> $b} keys %route_maps) {
	system("mkdir -p $basedir/rm");
	my $outfile = sprintf("%s/rm/%d.html",
			      $basedir, $rm);
	
	open (RM, ">$outfile") || die "can't open $outfile: $!\n";
	print RM "<html><h3>iBGP sessions</h3>";

	print RM "<center><table>\n";
	print RM "<tr><td><b>Permit</td><td><b>AS Regexp</td><td><b>Community</td><td><b>Local Preference</td><td><b>MED</td><td><b>Origin</td><td><b>Community</td><td><b>Prepend</td></tr>\n";

	my $q = "select permit, as_regexp, comm_regexp, localpref, med, origin, community, prepend from route_maps, as_regexps, comm_regexps, communities where route_maps.as_regexp_num=as_regexps.as_regexp_num and route_maps.comm_regexp_num=comm_regexps.comm_regexp_num and route_maps.community_num=communities.community_num and rmap_id=$rm order by clause_num";
	my $sth = $cq->query($q);

	while (my ($permit, $asr, $cr, $lp,
		   $med, $origin, $comm, $prep) =
	       $sth->fetchrow_array()) {
	    
	    printf RM ("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
		       $permit, $asr, $cr, $lp, $med, $origin, $comm, $prep);

	}

    }

}

sub make_index {

    my $idxfile = "$basedir/index.html";

    open (INDEX, ">$idxfile") || die "can't open $idxfile: $!\n";

    printf INDEX "<h3>BGP Summary</h3>";
    printf INDEX "iBGP Graph: [<a href=graph_bgp.jpg>.jpg</a>] [<a href=graph_bgp.ps>.ps</a>]\n";
    printf INDEX "<p><center><table width=80%>\n";
    foreach my $heading (keys %bgp_files) {
	next if ($heading =~ /info/i);
	printf INDEX ("<tr><td><a href=%s>%s</a></td></tr>\n",
		      $bgp_files{$heading}, $heading);
    }
    printf INDEX "</table></center><a href=../>Back</a>\n";

}

############################################################

sub bgp_summary {

    my %route_maps = ();

    open(IBGP, ">$basedir/ibgp_sessions.html") || die "can't open outfile: $!\n";
    print IBGP "<html><h3>iBGP sessions</h3>";

    my $ibgp_restr = "ebgp=0 and up=1 and router_loopbacks.loopback=sessions.neighbor_ip";

    my $q = "select count(*) from sessions,router_loopbacks where $ibgp_restr";
    my $sth = $cq->query($q);
    my ($igp_sessions) = $sth->fetchrow_array();
    printf IBGP "%d iBGP sessions", $igp_sessions;


    printf IBGP "<center><table>\n";
    print IBGP "<tr><td><b>Router</td><td><b>Neighbor</td><td><b>Neighbor IP</td><td><b>RR Session?</td></tr>\n";


    $q = "SELECT sessions.router_name, router_loopbacks.router_name, inet_ntoa(neighbor_ip), rr_client, clusterid, nh_self from sessions,router_loopbacks where $ibgp_restr";
    my $sth = $cq->query($q);

    while (my ($router, $neighbor_name, $neighbor_ip, $rr_client, $clusterid, $nh_self) = $sth->fetchrow_array()) {
	printf IBGP ("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
		     $router, $neighbor_name, $neighbor_ip, $rr_client);
    }

    print IBGP "</table><a href=index.html>Back</a></html>\n";
    close(IBGP);


    ############################################################
    # eBGP session info

    open(EBGP, ">$basedir/ebgp_sessions.html") || die "can't open outfile: $!\n";
    my $ebgp_restr = "ebgp=1 and up=1";
    print EBGP "<html><h3>eBGP sessions</h3>";

    $q = "select count(*) from sessions where $ebgp_restr";
    $sth = $cq->query($q);
    my ($bgp_sessions) = $sth->fetchrow_array();
    printf EBGP "%d eBGP sessions", $bgp_sessions;

    printf EBGP "<center><table>\n";
    print EBGP "<tr><td><b>Router</td><td><b>Neighbor AS</td><td><b>Neighbor IP</td><td><b>Import</td><td><b>Export</td></tr>\n";


    my $q = "SELECT sessions.router_name, asn, inet_ntoa(neighbor_ip), import_rm, export_rm from sessions where $ebgp_restr";
    my $sth = $cq->query($q);

    while (my ($router, $neighbor_asn, $neighbor_ip, $import_rm, $export_rm) = $sth->fetchrow_array()) {
	printf EBGP ("<tr><td>%s</td><td>%s</td><td>%s</td><td><a href=rm/%d.html>%d</a></td><td><a href=rm/%d.html>%d</a></td></tr>\n",
		     $router, $neighbor_asn, $neighbor_ip,
		     $import_rm, $import_rm,
		     $export_rm, $export_rm);
	$route_maps{$import_rm} = 1;
	$route_maps{$export_rm} = 1;

    }
    print EBGP "</table><a href=index.html>Back</a></html>\n";

    close(EBGP);

    &print_route_maps(\%route_maps);

}


############################################################

&make_index();
&bgp_summary();

