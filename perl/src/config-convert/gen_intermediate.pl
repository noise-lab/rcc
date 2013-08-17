#!/usr/bin/perl

BEGIN {
    push(@INC, "../../lib");
}

use ConfigCommon;
use ConfigIF_External;
use ConfigIF_Cisco;
use ConfigIF_Juniper;
use ConfigISIS_Juniper;
use ConfigISIS_Cisco;
use ConfigOSPF_Juniper;
use ConfigOSPF_Cisco;
use Getopt::Long;
use Data::Dumper;

my %options;
GetOptions(\%options, "debug=s", "db", "no-clean-db", "configdir=s");


if (!defined($options{'configdir'})) {
    print STDERR "ERROR: must specify location of config files with the 'configdir' option\n";
    exit;
}

if (defined($options{'debug'})) {
    $debug = $options{'debug'};
}



my $ccf = new ConfigIF_Cisco;
my $jcf = new ConfigIF_Juniper;

my $j_isis_cf = new ConfigISIS_Juniper;
my $c_isis_cf = new ConfigISIS_Cisco;

my $j_ospf_cf = new ConfigOSPF_Juniper;
my $c_ospf_cf = new ConfigOSPF_Cisco;

my $cf_ext = new ConfigIF_External;
if (defined($options{'db'})) {
    $cf_ext->clean_db();
    $cf_ext->db_bogon_list();
}

# For BGP stuff
my @cfs = ($ccf, $jcf);


if (defined($options{'configdir'})) {
    &set_configdir($options{'configdir'});
}

############################################################

foreach my $cf (@cfs) {
    # clean the DB
    if (defined($options{'db'}) &&
	!defined($options{'no-clean-db'})) {
	$cf->clean_db();
    }

    # construct the flow graph
    $cf->getNodes();
    $cf->getEdgesWithRouteMaps();
}

# put a '0', '' into the regexp tables
$cf_ext->db_regexp_init();

############################################################
# OUTPUT

foreach my $cf (@cfs) {

    my $routers = $cf->get_all_routers();
    my $rmaps = $cf->get_all_route_maps();
    
    if (!defined($options{'db'})) {
	foreach my $rtr (@$routers) {
	    $cf->print_loopbacks_for_router($rtr);
	    $cf->print_global_for_router($rtr);
	    $cf->print_session_info_for_router($rtr);
	}
	
	foreach my $rm (sort {$a <=> $b} keys %$rmaps) {
	    print $cf->print_route_map_tabular($rm);
	}
	
	
    } else {


	printf STDERR "Inserting into DB...";
	$cf->db_parse_errors();
	
	foreach my $rtr (@$routers) {
	    $cf->db_sessions_for_router($rtr);
	    $cf->db_loopbacks_for_router($rtr);
	    $cf->db_global_for_router($rtr);
	    $cf->db_session_info_for_router($rtr);
	    $cf->db_routes_for_router($rtr);
	    $cf->db_networks_for_router($rtr);
	    $cf->db_interfaces_for_router($rtr);
	}
	printf STDERR "done.\n";
	
	printf STDERR "Inserting ACLs...";
	$cf->db_prefix_acls();
	foreach my $rm (sort {$a <=> $b} keys %$rmaps) {
	    $cf->db_route_map($rm);
	}
	printf STDERR "done.\n";
	
    }
}

# Testing IS-IS stuff
print STDERR "Running IS-IS code...\n";
# Juniper
$j_isis_cf->getNodes();
$j_isis_cf->getInterfaces();
$j_isis_cf->getEdges();
$j_isis_cf->getRouterInfo();
$j_isis_cf->getMeshGroups();

# Cisco
$c_isis_cf->getNodes();
$c_isis_cf->getInterfaces();
$c_isis_cf->getEdges();
$c_isis_cf->getRouterInfo();
$c_isis_cf->getMeshGroups();

print STDERR "Done Running IS-IS code.\n";


# Testing OSPF
print STDERR "Running OSPF code...\n";
# Juniper
$j_ospf_cf->getNodes();
$j_ospf_cf->getInterfaces();
$j_ospf_cf->getEdges();
$j_ospf_cf->getAreaInfo();

# Cisco
$c_ospf_cf->getNodes();
$c_ospf_cf->getInterfaces();
$c_ospf_cf->getEdges();
$c_ospf_cf->getAreaInfo();

print STDERR "Done Running OSPF code.\n";

