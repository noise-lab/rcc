#!/usr/bin/perl

package ConfigDB;

use DBI;
use ConfigCommon;
use NetAddr::IP;
use strict;
use Data::Dumper;

use vars (qw(@ISA @EXPORT $VERSION),
	  qw($control_flow_db $cf_routers $cf_sessions $cf_rms),
	  qw($config_if $router_global $router_loopbacks $router_sessions $sessions),
	  qw($config_isis $config_ospf),
	  qw(@isis_db_tables $router_interfaces $adjacencies $router_info $mesh_groups),
	  qw(@ospf_db_tables $router_interfaces $adjacencies $area_info),
	  qw($as_regexps $comm_regexps $comm $route_maps $parse_errors),
	  qw(@db_tables $routes $networks $interfaces $sessions_shutdown),
	  qw($prefix_acls));

require Exporter;
$VERSION = '1.00';
@ISA = ('Exporter');

@EXPORT = (qw(&dbhandle &clean_db),
	   qw(&populate_loopback_ &populate_session_ &populate_route_map_),
	   qw($control_flow_db $cf_routers $cf_sessions $cf_rms),
	   qw($config_if $router_global $router_loopbacks $router_sessions $sessions),
	   qw($config_isis $config_ospf),
	   qw(@isis_db_tables $router_interfaces $adjacencies $router_info $mesh_groups),
	   qw(@ospf_db_tables $router_interfaces $adjacencies $area_info),
	   qw($as_regexps $comm_regexps $comm $route_maps $parse_errors),
	   qw(@db_tables $routes $networks $interfaces $sessions_shutdown),
	   qw($prefix_acls));


######################################################################
# Control Flow DB Tables

$control_flow_db = "config_control_flow";  # database name for control flow stuff
$cf_routers = "routers";
$cf_sessions = "sessions";
$cf_rms = "route_maps";


######################################################################
# Intermediate format DB tables

$config_if = "config_if";
$config_isis = "config_isis";
$config_ospf = "config_ospf";

$router_global = "router_global";
$router_loopbacks = "router_loopbacks";
$router_sessions = "router_sessions";
$sessions = "sessions";
$sessions_shutdown = "sessions_shutdown";
$as_regexps = "as_regexps";
$comm_regexps = "comm_regexps";
$comm = "communities";
$route_maps = "route_maps";
$parse_errors = "parse_errors";
$networks = "networks";
$routes = "routes";
$interfaces = "router_interfaces";
$prefix_acls = "prefix_acls";

@db_tables = ($router_global, $router_loopbacks, $router_sessions, $sessions,
	      $as_regexps, $comm_regexps, $comm, $route_maps, $parse_errors,
	      $networks, $routes, $interfaces, $sessions_shutdown,
	      $prefix_acls);

$router_interfaces = "router_interfaces";
$adjacencies = "adjacencies";
$router_info = "router_info";
$mesh_groups = "mesh_groups";

$area_info = "area_info";

@isis_db_tables = ($router_interfaces, $adjacencies, $router_info, $mesh_groups);
@ospf_db_tables = ($router_interfaces, $adjacencies, $area_info);

######################################################################

my @db_tables = (qw(route_maps sessions routers));

######################################################################
# autoconfigure from a config file
sub config_db {
    open(CONF, "$dbconfig") || die "Can't open $dbconfig: $!\n";
    while(<CONF>) {
	my ($key,$val) = split(/=/);
	if ($key eq 'host') {
	    $db_host = $val;
	} elsif ($key eq 'port') {
	    $db_port = $val;
	}
    }
}


# return a DB handle
sub dbhandle {
    my $database=$control_flow_db;
    
    my ($db) = @_;
    if (defined($db)) { $database = $db; }

    if (-e $dbconfig) { &config_db() };

    my $dsn = "DBI:mysql:database=$database;host=$db_host;port=$db_port";
    my $dbh = DBI->connect($dsn, $db_user, $db_pass);
    my $drh = DBI->install_driver("mysql");

    if (!defined($dbh)) { print "DB init failed\n"; }

    return $dbh;
}

# delete data from the DB tables
sub clean_db {

    my $dbh = &dbhandle();

    foreach my $table (@db_tables) {
	my $cmd = "delete from $table";
	$dbh->do($cmd);
    }
}

######################################################################
# accept reference to hash tables and
# populate database accordingly


sub populate_loopback_ {

    # take a reference to a ConfigFlow object
    my ($rcf) = shift;
    my $rhash = $rcf->{loopback_to_name};
    my $r_has_ebgp = $rcf->{has_ebgp};

    my $dbh = &dbhandle();

    foreach my $loopback (keys %$rhash) {
	my $loopback_ip = new NetAddr::IP($loopback);
	my $loopback_num = $loopback_ip->numeric();
	my $router_name = $rhash->{$loopback};

	my $has_ebgp = $r_has_ebgp->{$router_name};
	my $is_ebgp = ($router_name =~ /ebgp/);

	my $cmd = sprintf("insert into $cf_routers values ('%s', '%lu', '%d', '%d')",
			  $router_name, $loopback_num, $has_ebgp, $is_ebgp);
#	print STDERR "$cmd\n";
	$dbh->do($cmd);
    }

}


sub populate_session_ {

    # take a reference to a ConfigFlow object
    my ($rcf) = shift;

    my $dbh = &dbhandle();

    for (my $i=0; $i<2; $i++) {

	foreach my $router (@{$rcf->{nodes}}) {
	    my $rhash = $rcf->get_route_maps_for_router($router,$i);
	    foreach my $nbr (keys %$rhash) {

		my $asn = $rcf->{my_asn};

		if($nbr =~ /ebgp_AS(\d+)/) {
		    $asn = $1;
		}
		
		# insert session info into table
		my $cmd = sprintf("insert into $cf_sessions values ('%s', '%s', '%d', '%d', '%d')",
				  $router, $nbr, $asn, $i, $rhash->{$nbr});
#		print STDERR "$cmd\n";
		$dbh->do($cmd);
	    }
	}
	
    }


}

sub populate_route_map_ {
    # canonical route maps

    # take a reference to a ConfigFlow object
    my ($rcf) = shift;

    my $dbh = &dbhandle();

    foreach my $idx (keys %{$rcf->{canonical_rms}}) {
	my $cmd = sprintf("insert into $cf_rms values ('%d', '%s')",
			  $idx, $rcf->{canonical_rms}->{$idx});
	$dbh->do($cmd);
    }
}

