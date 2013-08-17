#!/usr/bin/perl

BEGIN {
    push(@INC, "../modules");
    
    # these are for the "menu.pl" script, which
    # requires different relative paths

    push(@INC, "../queries/modules/");
    push(@INC, "../../lib/");
}

use parse;
use determinism;
use loopback;
use nexthop;
use prepend;
use ibgp;
use peers;
use origin;
use filters;

use ConfigCommon;
use Getopt::Long;
my %options;
my $q;

GetOptions(\%options, "quiet", "summary", "files=s");
if (defined($options{'quiet'})) {
    $q = 1;
} elsif (defined($options{'summary'})) {
    $q = 2;
}

if (defined($options{'files'})) {
    system("mkdir -p $options{'files'}");
}


######################################################################

sub redirect {

    my ($filename, $append) = @_;
    my $d = ">";
    if ($append) {
	$d = ">>";
    }
    if (defined($options{'files'})) {
	my $basedir = $options{'files'};
	open(F, "$d $basedir/$filename");
	*STDOUT = *F;
    }

}

sub header {
    my ($header) = @_;

    if (!defined($options{'files'})) {
	printf "$header";
    }

}


sub make_index {

    my $basedir;
    if (defined($options{'files'})) {
	$basedir = $options{'files'};
	open(F, ">$basedir/index_bgp.html");
	
	print F "<html><h3>rcc BGP Error Summary</h3><center><table width=90% border=0>\n";

    } else {
	return;
    }

    my %title = ('parse' => 'Parse Errors',
		 'loopback' => 'Loopback Configuration',
		 'sync' => 'Synchronization',
		 'signaling' => 'iBGP Signaling',
		 'prepend' => 'AS Path Prepending',
		 'ifc' => 'Information Flow',
		 'nexthop' => 'Next-hop Reachability',
		 'network' => 'Network Advertisement',
		 'filtering' => 'Filtering',
		 'determinism' => 'Determinism');

    my %contents = ('parse' => 'Undefined route maps, access-lists, etc.',
		 'loopback' => 'Duplicate loopbacks, dangling sessions',
		 'sync' => 'Routers with synchronization enabled',
		 'signaling' => 'Possible iBGP partitions',
		 'prepend' => 'Bogus AS path prepending',
		 'ifc' => 'Transit between peers, inconsistent export, etc.',
		 'nexthop' => 'next-hop self usage',
		 'network' => 'network statements without routes',
		 'filtering' => 'Filtering of bogons and private ASes',
		 'determinism' => 'deterministic-med, router ID tiebreak');



    my @files = (keys %title);

    foreach my $file (@files) {
	my $filename = sprintf("%s/%s.txt", $basedir, $file);
	my $filename_rel = sprintf("%s.txt", $file);

	my @stats = stat($filename);
	my $size = $stats[7];
	next if (!$size);

	printf F ("<tr><td><a href=%s>%s</a></td><td>%s</td></tr>\n",
		  $filename_rel,
		  $title{$file}, $contents{$file});

    }

    close(F);

}

######################################################################

&redirect("parse.txt");
&header("\n\nParse Errors\n=====================\n");
my $prs = new parse;
$prs->parse_errors($q);

&redirect("loopback.txt");
# NOTE: This modifies the database to figure out "UP" sessions,
#       so it needs to be one of the first tests.
my $lb = new loopback;
$lb->dangling_ibgp_session($q);
$lb->duplicate_ibgp_session($q);

#&set_debug();


##################################################

&redirect("signaling.txt");
&header("\n\nVisibility Tests\n=====================\n");
my $ibgp = new ibgp;
#$ibgp->signaling_dag($q);
$ibgp->signaling_connect_top($q);
#$ibgp->signaling_connect($q);
$ibgp->client_cluster($q);
$ibgp->duplicate_routerids_lbs($q);

&redirect("sync.txt");
$ibgp->no_synchronization($q);


##################################################

&redirect("ifc.txt");
&header("\n\nInformation-flow Control Tests\n=====================\n");
my $peers = new peers;
$peers->consistent_import_peers($q);
$peers->consistent_export_peers($q);
#$peers->no_transit_between_peers($q);

##################################################



&redirect("prepend.txt");
&header("\n\nValidity Tests\n=====================\n");
my $pp = new prepend;
$pp->prepend_own_as($q);

&redirect("nexthop.txt");
my $nh = new nexthop;
$nh->next_hop_reachability($q);

&redirect("network.txt");
my $or = new origin;
#$or->network_has_route();

&redirect("filtering.txt");
my $flt = new filters;
$flt->remove_private_as($q);
$flt->test_bogon_prefixes();


&redirect("determinism.txt");
&header("\n\nDeterminism Tests\n=====================\n");

my $det = new determinism;
$det->deterministic_med($q);
$det->compare_routerid($q);


&make_index();
