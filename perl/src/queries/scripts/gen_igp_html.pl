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
use ConfigQueryISIS;
use ConfigQueryOSPF;
use Getopt::Long;

############################################################

my %options = ();
GetOptions(\%options, "basedir=s");

if (!defined($options{'basedir'})) {
    die "Error: Must define base output directory."
    }
my $basedir = sprintf("%s/igp_summary/",
		      $options{'basedir'});
system("mkdir -p $basedir");


my $cq_isis = new ConfigQueryISIS;
my $cq_ospf = new ConfigQueryOSPF;

my $isis_sum;
my $ospf_sum;

############################################################

my %isis_files = ('IS-IS Adjacencies' => 'isis_adjacencies.html',
		  'IS-IS Info' => 'isis_info.html',
		  'IS-IS Interfaces' => 'isis_interfaces.html',
		  'IS-IS Path Costs' => 'isis_routes.html');


my %ospf_files = ('OSPF Adjacencies' => 'ospf_adjacencies.html',
		  'OSPF Info' => 'ospf_info.html',
		  'OSPF Interfaces' => 'ospf_interfaces.html',
		  'OSPF Path Costs' => 'ospf_routes.html');

############################################################

sub set_vars { 
    my $q = "select count(*) from adjacencies";

    my $sth = $cq_isis->query($q);
    my ($isis_adj) = $sth->fetchrow_array();
    $isis_sum = ($isis_adj > 0);

    $sth = $cq_ospf->query($q);
    my ($ospf_adj) = $sth->fetchrow_array();
    $ospf_sum = ($ospf_adj > 0);


}



############################################################

sub make_index {

    my $idxfile = "$basedir/index.html";

    open (INDEX, ">$idxfile") || die "can't open $idxfile: $!\n";

    if ($isis_sum) {
	printf INDEX "<h3>ISIS Summary</h3><p>\n";
	printf INDEX "IGP Graph: [<a href=graph_igp.jpg>.jpg</a>] [<a href=graph_igp.ps>.ps</a>]\n";
	printf INDEX "<table>\n";
	foreach my $heading (keys %isis_files) {
	    next if ($heading =~ /info/i);
	    printf INDEX ("<tr><td><a href=%s>%s</a></td></tr>\n",
			  $isis_files{$heading}, $heading);
	}
	printf INDEX "</table>\n";
    }

    if ($ospf_sum) {
	printf INDEX "<h3>OSPF Summary</h3>\n";
	printf INDEX "<table>\n";
	foreach my $heading (keys %ospf_files) {
	    printf INDEX ("<tr><td><a href=%s>%s</a></td></tr>\n",
			  $ospf_files{$heading}, $heading);
	}
	printf INDEX "</table>\n";
    }



}

############################################################

sub isis_summary {
# ISIS Adjacencies

    open(ISIS_ADJ, ">$basedir/isis_adjacencies.html") || die "can't open outfile: $!\n";
    print ISIS_ADJ "<html><h3>ISIS Adjacencies</h3><center><table>\n";

    print ISIS_ADJ "<tr><td>Origin Router</td><td>Destination Router</td><td>Level 1 Metric</td><td>Level 2 Metric</td><td>IPv4 Address</td><td>Origin Interface</td><td>Level 1 Adjacency?</td><td>Level 2 Adjacency?</td><td>Inter-Area?</td></tr>\n";

# get output from the database table 
    my $q = "SELECT * from adjacencies";
    my $sth = $cq_isis->query($q);

    while (my ($origin,$dest,$lvl1_metric,$lvl2_metric,$ip4_addr,$origin_intf,$lvl1_adj,$lvl2_adj, $interarea) = $sth->fetchrow_array()) {
	printf ISIS_ADJ ("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
			 $origin,$dest,$lvl1_metric,$lvl2_metric,$ip4_addr,$origin_intf,$lvl1_adj,$lvl2_adj, $interarea);
    }

    print ISIS_ADJ "</table></html>\n";

    close(ISIS_ADJ);


# ISIS Router Info


    open(ISIS_INFO, ">$basedir/isis_info.html");
    print ISIS_INFO "<html><h3>ISIS Router Info</h3><center><table>\n";

    print ISIS_INFO "<tr><td>Router Name</td><td>ISO Address</td><td>IPv4 Address</td><td>IPv6 Address</td><td>Area Address</td><td>Authentication Type</td><td>Authentication Key (SHA-1 Hash)</td></tr>\n";

# get output from the database table 
    my $q = "SELECT * from router_info";
    my $sth = $cq_isis->query($q);

    while (my ($router,$iso_addr,$ipv4_addr,$ipv6_addr,$area_addr,$auth_type,$auth_key) = $sth->fetchrow_array()) {
	printf ISIS_INFO ("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
			  $router,$iso_addr,$ipv4_addr,$ipv6_addr,$area_addr,$auth_type,$auth_key);
    }

    print ISIS_INFO "</table></html>\n";

    close(ISIS_INFO);


# Router Interfaces


    open(ISIS_INTERFACES, ">$basedir/isis_interfaces.html") || die "can't open outfile: $!\n";
    print ISIS_INTERFACES "<html><h3>ISIS Router Interfaces</h3><center><table>\n";

    print ISIS_INTERFACES "<tr><td>Router Name</td><td>Interface Name</td><td>IPv4 Address</td><td>IPv6 Address</td><td>ISO Address</td><td>Level 1 Routing?</td><td>Level 2 Routing?</td><td>Level 1 Metric</td><td>Level 2 Metric</td><td>IPv4 MTU</td><td>IPv6 MTU</td><td>ISO MTU</td></tr>\n";

# get output from the database table 
    my $q = "SELECT * from router_interfaces";
    my $sth = $cq_isis->query($q);

    while (my ($router,$interface,$ipv4_addr,$ipv6_addr,$iso_addr,$lvl1_routing,$lvl2_routing,$lvl1_metric,$lvl2_metric,$mtu_ipv4,$mtu_ipv6,$mtu_iso) = $sth->fetchrow_array()) {
	printf ISIS_INTERFACES ("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
				$router,$interface,$ipv4_addr,$ipv6_addr,$iso_addr,$lvl1_routing,$lvl2_routing,$lvl1_metric,$lvl2_metric,$mtu_ipv4,$mtu_ipv6,$mtu_iso);
    }

    print ISIS_INTERFACES "</table></html>\n";

    close(ISIS_INTERFACES);


# Routes

    open(ISIS_ROUTES, ">$basedir/isis_routes.html") || die "can't open outfile: $!\n";;
    print ISIS_ROUTES "<html><h3>ISIS Routes</h3><center><table>\n";

    print ISIS_ROUTES "<tr><td>Origin Router</td><td>Destination Router</td><td>Cost</td></tr>\n";

# get output from the database table 
    my $q = "SELECT * from routes";
    my $sth = $cq_isis->query($q);

    while (my ($origin,$dest,$cost) = $sth->fetchrow_array()) {
	printf ISIS_ROUTES ("<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n",
			    $origin,$dest,$cost);
    }

    print ISIS_ROUTES "</table></html>\n";

    close(ISIS_ROUTES);
}


sub ospf_summary {

### OSPF
# OSPF adjacencies

    open(OSPF_ADJ, ">$basedir/ospf_adjacencies.html") || die "can't open outfile: $!\n";;
    print OSPF_ADJ "<html><h3>OSPF Adjacencies</h3><center><table>\n";

    print OSPF_ADJ "<tr><td>Origin Router</td><td>Destination Router</td><td>Metric</td><td>Origin Interface</td><td>IPv4 Subnet Address</td><td>Origin Area</td><td>Destination Area</td></tr>\n";

# get output from the database table 
    my $q = "SELECT * from adjacencies";
    my $sth = $cq_ospf->query($q);

    while (my ($origin,$dest,$metric,$interface,$ip4_addr,$origin_area,$dest_area) = $sth->fetchrow_array()) {
	printf OSPF_ADJ ("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
			 $origin,$dest,$metric,$interface,$ip4_addr,$origin_area,$dest_area);
    }

    print OSPF_ADJ "</table></html>\n";

    close(OSPF_ADJ);


# OSPF Area Info

    open(OSPF_AREA_INFO, ">$basedir/ospf_area_info.html") || die "can't open outfile: $!\n";;
    print OSPF_AREA_INFO "<html><h3>OSPF Area Info</h3><center><table>\n";

    print OSPF_AREA_INFO "<tr><td>Area</td><td>Stub?</td><td>NSSA?</td><td>Authentication Type</td></tr>\n";

# get output from the database table 
    my $q = "SELECT * from area_info";
    my $sth = $cq_ospf->query($q);

    while (my ($area,$stub,$nssa,$auth_type) = $sth->fetchrow_array()) {
	printf OSPF_AREA_INFO ("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
			       $area,$stub,$nssa,$auth_type);
    }

    print OSPF_AREA_INFO "</table></html>\n";

    close(OSPF_AREA_INFO);


# OSPF router info


    open(OSPF_ROUTER_INFO, ">$basedir/ospf_router_info.html") || die "can't open outfile: $!\n";;
    print OSPF_ROUTER_INFO "<html><h3>OSPF Router Info</h3><center><table>\n";

    print OSPF_ROUTER_INFO "<tr><td>Router</td><td>IPv4 Address</td><td>IPv6 Address</td></tr>\n";

# get output from the database table 
    my $q = "SELECT * from router_info";
    my $sth = $cq_ospf->query($q);

    while (my ($router,$ipv4_addr,$ipv6_addr) = $sth->fetchrow_array()) {
	printf OSPF_ROUTER_INFO ("<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n",
				 $router,$ipv4_addr,$ipv6_addr);
    }

    print OSPF_ROUTER_INFO "</table></html>\n";

    close(OSPF_ROUTER_INFO);


# OSPF Router Interfaces

    open(OSPF_ROUTER_INTERFACES, ">$basedir/ospf_router_interfaces.html") || die "can't open outfile: $!\n";;
    print OSPF_ROUTER_INTERFACES "<html><h3>OSPF Router Interfaces</h3><center><table>\n";

    print OSPF_ROUTER_INTERFACES "<tr><td>Router</td><td>Interface</td><td>IPv4 Address</td><td>IPv6 Address</td><td>Area</td><td>Metric</td><td>Enabled?</td><td>IPv4 MTU</td><td>IPv6 MTU</td><td>Authentication Type</td><td>Authentication Key</td></tr>\n";

# get output from the database table 
    my $q = "SELECT * from router_interfaces";
    my $sth = $cq_ospf->query($q);

    while (my ($router,$intf,$ipv4_addr,$ipv6_addr,$area,$metric,$enabled,$mtu_ipv4,$mtu_ipv6,$auth_type,$auth_key) = $sth->fetchrow_array()) {
	printf OSPF_ROUTER_INTERFACES ("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
				       $router,$intf,$ipv4_addr,$ipv6_addr,$area,$metric,$enabled,$mtu_ipv4,$mtu_ipv6,$auth_type,$auth_key);
    }

    print OSPF_ROUTER_INTERFACES "</table></html>\n";

    close(OSPF_ROUTER_INTERFACES);


# OSPF Routes

    open(OSPF_ROUTES, ">$basedir/ospf_routes.html") || die "can't open outfile: $!\n";;
    print OSPF_ROUTES "<html><h3>OSPF Routes</h3><center><table>\n";

    print OSPF_ROUTES "<tr><td>Origin Router</td><td>Destination Router</td><td>Cost</td></tr>\n";

# get output from the database table 
    my $q = "SELECT * from routes";
    my $sth = $cq_ospf->query($q);

    while (my ($origin,$dest,$cost) = $sth->fetchrow_array()) {
	printf OSPF_ROUTES ("<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n",
			    $origin,$dest,$cost);
    }

    print OSPF_ROUTES "</table></html>\n";

    close(OSPF_ROUTES);
}

############################################################

&set_vars();

&make_index();
&ospf_summary () if ($ospf_sum);
&isis_summary () if ($isis_sum);
