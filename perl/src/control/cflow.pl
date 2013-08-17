#!/usr/bin/perl


BEGIN {
    push(@INC, "../../lib");
}

use ConfigCommon;
use ConfigFlow;
use Getopt::Long;

my %options;
GetOptions(\%options, "db", "graph=s", "debug=s");

if (defined($options{'debug'})) {
    $debug = $options{'debug'};
}



my $cf = new ConfigFlow;

# construct the flow graph
$cf->getNodes();
$cf->getEdgesWithRouteMaps();

if (defined($options{'db'})) {

    # delete the data from the DB to prepare for
    # new insertion

    $cf->clean_db();

    # populate the config flow database tables
    $cf->populate_loopback_db();
    $cf->populate_session_db();
    $cf->populate_route_map_db();

} elsif (defined ($options{'graph'})) {

    # print a dot version of the graph
    # example --graph=dot,50,ebgp

    $cf->print_flow_graph($options{'graph'});

} else {
    
    # output the flow graph in text format
    $cf->print_route_maps_for_all_routers();
    $cf->print_loopbacks_for_all_routers();
    $cf->print_all_canonical_route_maps();

}
