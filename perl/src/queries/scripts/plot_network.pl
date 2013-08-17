#!/usr/bin/perl

BEGIN {
    push(@INC, "../../../lib/");

    # these are for the "menu.pl" script, which
    # requires different relative paths
    push(@INC, "../../lib/");

}

use strict;
use ConfigCommon;
use ConfigQuery;
use Getopt::Long;

############################################################

my $cq_igp = new ConfigQuery("config_isis");
my $cq_bgp = new ConfigQuery("config_if");

my $plot_igp = 0;
my $plot_bgp = 0;

my %igp_edges;
my %bgp_edges;

############################################################

my $basedir = "/tmp";
my $dotfile = "/tmp/graph.$$.dot";
my $format = "ps";

############################################################

my %options;
my $type;

GetOptions(\%options, "bgp", "igp", "format=s", "files=s");
if (defined($options{'bgp'})) {
    $plot_bgp = 1;
    $type = 'bgp';
}
if (defined($options{'igp'})) {
    $plot_igp = 1;
    
    if (!$plot_bgp) {
	$type = 'igp';
    } else {
	$type = 'all';
    }
}
if (!$plot_bgp && !$plot_igp) {
    die "error: specify either --bgp or --igp\n";
}
if (defined($options{'format'})) {
    $format = $options{'format'};
}

if (defined($options{'files'})) {
    $basedir = $options{'files'};
}

my $plotfile = sprintf("$basedir/%s_summary/graph_%s.$format",
			   $type, $type);

my $cmd = sprintf("mkdir -p $basedir/%s_summary/", $type);
system($cmd);

############################################################

sub get_igp_edges {

    my $q = "select origin_router_name, dest_router_name, level2_metric from adjacencies";
    my $sth = $cq_igp->query($q);
    
    while (my ($src, $dst, $cost) = $sth->fetchrow_array()) {
	$igp_edges{$src}->{$dst} = $cost;
    }
}


sub get_bgp_edges {
    
    my $q = "select sessions.router_name, router_loopbacks.router_name, rr_client from sessions,router_loopbacks where sessions.neighbor_ip=router_loopbacks.loopback";
    my $sth = $cq_bgp->query($q);

    while (my ($src, $dst, $rr) = $sth->fetchrow_array()) {
	$bgp_edges{$src}->{$dst} = $rr;
    }

}


sub print_graph {
    
    open(DOT, ">$dotfile") || die "can't open $dotfile: $!\n";
    print DOT "digraph Network { \n";

    ##################################################
    # Plot IGP Graph

    if ($plot_igp) {
	foreach my $src (sort keys %igp_edges) {

	    my $srcstr;
	    if ($src =~ /(.*?)\..*/) {
		$srcstr = $1;
		$srcstr =~ s/\-/\_/;
	    }
	    print DOT "\t$srcstr [style=filled, color=lightblue]\n";



	    foreach my $dst (sort keys %{$igp_edges{$src}}) {
		my $cost = $igp_edges{$src}->{$dst};
		
		my $dststr;
		if ($dst =~ /(.*?)\..*/) {
		    $dststr = $1;
		    $dststr =~ s/\-/\_/;
		}

		print DOT "\t$srcstr -> $dststr [label=\"$cost\"];\n";
	    }
	}
    }

    ##################################################
    # Plot BGP Graph

    if ($plot_bgp) {

	my %linecache = ();
	
	foreach my $src (sort keys %bgp_edges) {
	    my $srcstr;
	    if ($src =~ /(.*?)\..*/) {
		$srcstr = $1;
		$srcstr =~ s/\-/\_/;
	    }
	    print DOT "\t$srcstr [style=filled, color=lightblue]\n";


	    foreach my $dst (sort keys %{$igp_edges{$src}}) {
		my $rr = $bgp_edges{$src}->{$dst};
		
		my $dststr;
		if ($dst =~ /(.*?)\..*/) {
		    $dststr = $1;
		    $dststr =~ s/\-/\_/;
		}

		if (!$rr) {
		    if (!$linecache{$src}->{$dst}) {
			print DOT "\t$srcstr -> $dststr [arrowhead=none, style=dashed]\n";
		    }
		    $linecache{$src}->{$dst} = 1;
		    $linecache{$dst}->{$src} = 1;
		} else {
		    print DOT "\t$srcstr -> $dststr [style=dashed]\n";
		}
	    }
	}
    }
    ##################################################


    print DOT "}\n";

}


############################################################

sub plot_graph {

    my ($format) = @_;
    system("$dot -T$format $dotfile >$plotfile");

}


############################################################
&get_igp_edges();
&get_bgp_edges();

############################################################
&print_graph();
&plot_graph($format);
