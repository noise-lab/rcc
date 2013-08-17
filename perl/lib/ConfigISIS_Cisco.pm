#!/usr/bin/perl

package ConfigISIS_Cisco;

use Data::Dumper;
use strict;

use CiscoTypes;
use ConfigCommon;
use ConfigParse;
use ConfigDB;

require Exporter;
use vars(qw(@ISA @EXPORT $configdir @isis_db_tables));
@ISA = ('Exporter');

my $debug = 1;

######################################################################
# Constructor

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);

    $self->{dbh} = &dbhandle($config_isis);

    $self->{nodes};               # array of router names
    $self->{edges};               # router_name => adjacency list (router nmes)
    $self->{router_options};      # router_name => reference(option_name => option_value)
    $self->{router_interfaces};   # router_name => reference(interface_name 
                                  #                    => reference(data_type => value))
    $self->{mesh_groups} = {};         # mesh_group_number => @mesh_group
    
    $self->{parse_errors};

    return $self;
}


######################################################################
# 

sub getNodes {

    my $self = shift;

    print "Config dir is: $configdir\n";

    # each node will have 
    # 1. a unique name
    # 2. predefined "programs" (i.e., route maps)
    my @rfiles = <$configdir/*-confg>;

    print STDERR  "Looping through router files.\n" if $debug;
    foreach my $rfile (@rfiles) {
	print STDERR  "Looking for $rfile.\n" if $debug;
	if ($rfile =~ /^.*\/(.*)-confg/){
	    print STDERR  "Found $rfile.\n" if $debug;
	    push(@{$self->{nodes}}, $1);
	}
    }
}

######################################################################
# get unidirectional edges in the IS-IS graph 

# For each router, get the router's interfaces configured for IS-IS
# Determine each interface's address
# Match up addresses to nodes to get edges


sub getInterfaces {
	
    my $self = shift;
    
    foreach my $router (@{$self->{nodes}}) {
	
	# interface_name => (data_type => data)
	my %interfaces;
	# add this to the hash
	$self->{router_interfaces}->{$router} = \%interfaces;

	# options
	$self->{router_options}->{$router}->{"isis_disabled"} = 0;
	$self->{router_options}->{$router}->{"wide_metrics_only_lvl1"} = 0;
	$self->{router_options}->{$router}->{"wide_metrics_only_lvl2"} = 0;
	$self->{router_options}->{$router}->{"auth_type"} = "none";
	# add more here
	

	# Open the file for parsing
	my $rfilename = $configdir . "/" . $router . "-confg";
	print STDERR  "ConfigISIS_Cisco: Looking at $rfilename.\n" if $debug;
	open (RFILE, "$rfilename") || die "can't open $rfilename: $!\n";
	
	# Parse the file
	while (<RFILE>) {
	    chomp;
	    my $line = $_;

	    # Look for interfaces
	    if ($line =~ /^interface\s+(.*)/) {
		my $intf_name = $1;
		print STDERR "Found interface: $intf_name.\n" if $debug;
		
		my $isis_enabled = 0;

		my %interface_data;
		$interface_data{"ipv4_address"}="none";
		$interface_data{"ipv6_address"}="none";
		$interface_data{"iso_address"}="none";

		$interface_data{"lvl1_metric"}=10;
		$interface_data{"lvl2_metric"}=10;

		$interface_data{"lvl1_enabled"}=1;
		$interface_data{"lvl2_enabled"}=1;

		$interface_data{"mtu_ipv4"}=0;
		$interface_data{"mtu_ipv6"}=0;
		$interface_data{"mtu_iso"}=0;
		getDefaultMTU($intf_name, \%interface_data);


		# start parsing other configuration information
		my $intf_line;
		do {
		    $intf_line = <RFILE>;
		    chomp;

		    # check if IS-IS is configured for this interface
		    if ($intf_line =~ /^\s*ip\srouter\sisis/) {
			$isis_enabled = 1;
		    }
		    
		    # IP address
		    if ($intf_line =~ /$ip_mask_regexp/) {
			my $addr = $1;
			my $mask = $2;

			if ($addr != '') {
			    $interface_data{"ipv4_address"} = calculateSubnetIP($addr,$mask);
			}
		    }

		    # ISO address
		    if ($intf_line =~ /^\s*net\s+(.*)/) {
			$interface_data{"iso_address"} = $1;
		    }

		    # Routing level
		    if ($intf_line =~ /^\s*isis\scircuit-type\slevel-1/) {
			$interface_data{"lvl1_enabled"}=1;
			$interface_data{"lvl2_enabled"}=0;
		    }
		    if ($intf_line =~ /^\s*isis\scircuit-type\slevel-1-2/) {
			# this is the default, do nothing
		    }
		    if ($intf_line =~ /^\s*isis\scircuit-type\slevel-2-only/) {
			$interface_data{"lvl1_enabled"}=0;
			$interface_data{"lvl2_enabled"}=1;
		    }

		    # Routing metric
		    if ($intf_line =~ /^\s*isis\smetric\s(.*)\slevel-1/) {
			$interface_data{"lvl1_metric"}=$1;
		    }
		    elsif ($intf_line =~ /^\s*isis\smetric\s(.*)\slevel-2/) {
			$interface_data{"lvl2_metric"}=$1;
		    }
		    elsif ($intf_line =~ /^\s*isis\smetric\s(.*)/) {
			# if no level is specified, use level 1
			$interface_data{"lvl1_metric"}=$1;
		    }

		    # MTU
		    if ($intf_line =~ /mtu\s(.*)/) {
			$interface_data{"mtu_ipv4"}=$1;
		    }

		    # Mesh Groups
		    if ($intf_line =~ /^\s*isis\smesh-group\s(.*)/) {
			my $mesh_num = $1;
			# check to see if this mesh group exists, and if so,
			# add this router
			push(@{$self->{mesh_groups}->{$mesh_num}}, $router . "\\" . $intf_name);
		    }
		    
			
		} while (($intf_line !~ /$eos/) && $intf_line);

		if ($isis_enabled == 1) {
		    # add this interface
		    $self->{router_interfaces}->{$router}->{$intf_name} = \%interface_data;
		}
	    }
	    
	    # Router IS-IS settings
	    elsif ($line =~ /^router\sisis/) {
		my $router_line;
		do {
		    $router_line = <RFILE>;
		    chomp;

		    # ISO address
		    if ($router_line =~ /^\s*net\s+(.*)/) {
			$self->{router_interfaces}->{"Loopback"}->{"iso_address"} = $1;
		    }
		}  while (($router_line !~ /$eos/) && $router_line);
	    }
	}

	foreach my $interface (keys(%interfaces)) {
	    # insert info into table
	    my $cmd = "INSERT into $router_interfaces values ('$router','$interface','$interfaces{$interface}->{ipv4_address}','$interfaces{$interface}->{ipv6_address}','$interfaces{$interface}->{iso_address}','$interfaces{$interface}->{lvl1_enabled}','$interfaces{$interface}->{lvl2_enabled}','$interfaces{$interface}->{lvl1_metric}','$interfaces{$interface}->{lvl2_metric}','$interfaces{$interface}->{mtu_ipv4}','$interfaces{$interface}->{mtu_ipv6}','$interfaces{$interface}->{mtu_iso}')";
	    
	    $self->{dbh}->do($cmd);
	}

    }
}


######################################################################
# Get IS-IS network graph edges

sub getEdges {

    my $self = shift;

    # Now generate the IS-IS network topological graph's edges
    foreach my $router (@{$self->{nodes}}) {
	# Get subnet addresses for each router	
	
	my $subnet_addrs = $self->{dbh}->selectcol_arrayref("SELECT ipv4_address FROM $router_interfaces WHERE router_name='$router' AND interface_name NOT REGEXP 'Loopback.*'");
	
	# Loop over these subnet addrs and find other routers 
	# with the same subnet addrs
	foreach my $addr (@{$subnet_addrs}) {
	    # skip if $addr = none
	    if ($addr eq "none") {
		next;
	    }
	    my $neighbor_routers = $self->{dbh}->selectcol_arrayref("SELECT router_name FROM $router_interfaces WHERE ipv4_address='$addr'");
	    
	    # Insert adjacencies into 'adjacencies' table
	    foreach my $neighbor (@{$neighbor_routers}) {
		# no loops back to self
		if ($neighbor eq $router) {
		    next;
		}
		my @metrics_and_intf = $self->{dbh}->selectrow_array("SELECT level1_metric,level2_metric, interface_name FROM $router_interfaces WHERE router_name='$router' AND ipv4_address='$addr'");

			# determine level of adjacency
		my @origin_isis_levels = $self->{dbh}->selectrow_array("SELECT level1_routing, level2_routing FROM $router_interfaces WHERE router_name='$router' AND ipv4_address='$addr'");
		my @neighbor_isis_levels = $self->{dbh}->selectrow_array("SELECT level1_routing, level2_routing FROM $router_interfaces WHERE router_name='$neighbor' AND ipv4_address='$addr'");
		
		my $level1 = 0;
		my $level2 = 0;
		if ($origin_isis_levels[0] eq $neighbor_isis_levels[0]) {
		    my $level1 = 1;
		}
		if ($origin_isis_levels[1] eq $neighbor_isis_levels[1]) {
		    my $level2 = 1;
		}

		# determine if adjacency is inter-area
		my @origin_area_addr = $self->{dbh}->selectrow_array("SELECT iso_address FROM $router_info WHERE router_name = '$router'");
		my @neighbor_area_addr = $self->{dbh}->selectrow_array("SELECT iso_address FROM $router_info WHERE router_name = '$neighbor'");
		my $interarea = 0;
		if (!($origin_area_addr[0] eq $neighbor_area_addr[0])) {
		    $interarea = 1;
		}

		my $cmd = "INSERT into $adjacencies VALUES ('$router','$neighbor',$metrics_and_intf[0],$metrics_and_intf[1],'$addr','$metrics_and_intf[2]','$level1','$level2','$interarea')";
		$self->{dbh}->do($cmd);
	    }
	}		
    }
}

######################################################################
# Organize Router Info for each router

sub getRouterInfo {

    my $self = shift;

    foreach my $router (@{$self->{nodes}}) {
	# Query DB for loopback interface
	my @router_info = $self->{dbh}->selectrow_array("SELECT iso_address,ipv4_address,ipv6_address FROM $router_interfaces WHERE interface_name REGEXP 'Loopback.*' and router_name = '$router'");

	# Compute Area address from ISO address
	my @addr_parts = split(/\./, $router_info[0]);
	my $area = $addr_parts[0] . "." . $addr_parts[1];
	
	# insert into 'router_info' table
	my $cmd = "INSERT INTO $router_info VALUES ('$router','$router_info[0]','$router_info[1]','$router_info[2]','$area','$self->{router_options}->{$router}->{auth_type}','$self->{router_options}->{$router}->{auth_key}')";
	$self->{dbh}->do($cmd);
    }
}


######################################################################
# Get Mesh Groups

sub getMeshGroups {

    my $self = shift;
    foreach my $mesh_num (keys(%{$self->{mesh_groups}})) {
	foreach my $member (@{$self->{mesh_groups}->{$mesh_num}}) {
	    my @member_info = split(/\\/, $member);
	    my $cmd = "INSERT INTO $mesh_groups VALUES ('$mesh_num', '$member_info[0]', '$member_info[1]')";
	    $self->{dbh}->do($cmd);
	}
    }

}

######################################################################
sub calculateSubnetIP {
    my ($ip, $mask) = @_;

    print STDERR "Address is $ip.\n" if $debug;
    
    my @ip_parts = split(/\./,$ip);
    my @mask_parts = split(/\./,$mask);;    
    
    # Bitwise And the IP and the mask together
    my @subnet_ip_parts;
    for (my $i = 0; $i < 4; $i++) {
	$subnet_ip_parts[$i] = $ip_parts[$i] & $mask_parts[$i];
    }
    
    my $subnet_ip = join(".",@subnet_ip_parts);    
    return $subnet_ip;
}


######################################################################
# Data from Table 15-10, Cisco IOS in a Nutshell

sub getDefaultMTU {
    my ($name, $data) = @_;
    
    if ($name =~ /Serial/) {
	$$data{"mtu_ipv4"} = 1500;
	$$data{"mtu_ipv6"} = 1500;
	$$data{"mtu_iso"} = 1500;
    }
    elsif ($name =~ /Ethernet/) {
	$$data{"mtu_ipv4"} = 1500;
	$$data{"mtu_ipv6"} = 1500;
	$$data{"mtu_iso"} = 1500;
    }
    else {
	$$data{"mtu_ipv4"} = 4470;
	$$data{"mtu_ipv6"} = 4470;
	$$data{"mtu_iso"} = 4470;
    }
    

}


1;
