#!/usr/bin/perl

package rccHTML;

require Exporter;
use vars(qw(@ISA @EXPORT));

use strict;

@ISA = ('Exporter');
@EXPORT = (qw(&make_rcc_index));

############################################################

sub make_rcc_index {

    my $basedir = shift;
    my $timestr = localtime();

    my $ospfstr;
    my $isisstr;

    my @stats = stat("$basedir/index_ospf.html");
    my $size = $stats[7];
    if ($size > 0) {
	$ospfstr = "<li><a href=index_ospf.html>OSPF Errors</a><br>";
    }

    my @stats = stat("$basedir/index_isis.html");
    my $size = $stats[7];

    if ($size > 0) {
	$isisstr = "<li><a href=index_isis.html>IS-IS Errors</a><br>";
    }



    print STDERR "basedir: $basedir\n";
    open (OUT, ">$basedir/index.html") || die "can't open $basedir: $!\n";

    print OUT <<EOF_HTML;

<h2>rcc Report</h2>

<a href=bgp_summary/graph_bgp.jpg><img height=200 width=300 src=graph_bgp.jpg></a>
<a href=bgp_summary/graph_igp.jpg><img height=200 width=300 src=graph_igp.jpg></a><p>

<h3>Summaries</h3>
<ul>
<li> <a href=bgp_summary/>BGP Summary</a>
<li> <a href=igp_summary/>IGP Summary</a>
</ul>


<h3>Errors</h3>
<ul>
<li><a href=index_bgp.html>BGP Errors</a><br>
$isisstr
$ospfstr
</ul>



<p>
Report run: $timestr<br>
EOF_HTML
}


1;
