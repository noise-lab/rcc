#!/usr/bin/perl

package ConfigOSPF_Cisco;

use Data::Dumper;
use strict;

use CiscoTypes;
use ConfigCommon;
use ConfigParse;
use ConfigDB;

require Exporter;
use vars(qw(@ISA @EXPORT $configdir @ospf_db_tables));
@ISA = ('Exporter');

my $debug = 1;

# Note: for Cisco config files, we will change all instances of area 0
# to area 0.0.0.0 for compatibility with Juniper

######################################################################
# Constructor

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);

    $self->{dbh} = &dbhandle($config_ospf);

    $self->{nodes};               # array of router names
    $self->{edges};               # router_name => adjacency list (router nmes)
    $self->{router_options};      # router_name => reference(option_name => option_value)
    $self->{router_interfaces};   # router_name => reference(interface_name => reference(data_type => value))
    $self->{areas};               # area => reference(option_name => option_value)

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
# get unidirectional edges in the OSPF graph 

# For each router, get the router's interfaces configured for OSPF
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
	$self->{router_options}->{$router}->{"ospf_disabled"} = 0;
	$self->{router_options}->{$router}->{"ospf_version"} = 2;
	# add more here

	my @networks;

	# Open the file for parsing
	my $rfilename = $configdir . "/" . $router . "-confg";
	print STDERR  "ConfigOSPF_Cisco: Looking at $rfilename.\n" if $debug;
	open (RFILE, "$rfilename") || die "can't open $rfilename: $!\n";
	
	# Parse the file
	while (<RFILE>) {
	    chomp;
	    my $line = $_;
	    
	    # Router OSPF settings
	    if ($line =~ /^router\sospf/) {
		my $router_line;
		do {
		    $router_line = <RFILE>;
		    chomp;

		    if ($router_line =~ /^\s*network\s+($ip_mask_regexp)\s+area\s+(.*)/) {
			my $addr = $1;
			my $mask = $2;
			my $area = $3;
			
			# if $area == 0, set $area = 0.0.0.0
			if ($area == 0) {
			    $area = "0.0.0.0";
			}

			push(@networks, join("\\", $addr, $mask, $area));

			# Check if area is already defined
			if (!defined($self->{areas}->{$area})) {
			    my %area_options;
			    $area_options{"stub"}=0;
			    $area_options{"nssa"}=0;
			    
			    $area_options{"auth_type"}="none";
			    
			    $self->{areas}->{$area} = \%area_options;
			}
		    }

		    # authentication
		    if ($router_line =~ /area\s+(.*)\s+authentication\s+message-digest/) {
			$self->{areas}->{$1}->{"auth_type"} = "md5";
		    }
		    elsif ($router_line =~ /area\s+(.*)\s+authentication/) {
			$self->{areas}->{$1}->{"auth_type"} = "simple";
		    }
		    
		}  while (($router_line !~ /$eos/) && $router_line);
	    }
	}

	# Now find interfaces for these addresses

	foreach my $triplet (@networks) {
	    
	    # separate address, subnet mask and area number
	    my ($address,$subnet_mask,$area) = split(/\\/, $triplet);

	    # Close and reopen the file now to parse interfaces
	    close(RFILE);
	    open(RFILE, "$rfilename") || die "can't open $rfilename: $!\n";

	    while (<RFILE>) {
		chomp;
		my $line = $_;

		if ($line =~ /^interface\s+(.*)/) {
		    my $intf_name = $1;
		    print STDERR "Found interface: $intf_name.\n" if $debug;

		    my $intf_line;
		    do {
			$intf_line = <RFILE>;
			chomp;

			my $match = 0;
			if ($intf_line =~ /$ip_mask_regexp/) {
			    my $intf_addr = $1;
			    my $intf_mask = $2;

			    if (($address eq $intf_addr) && ($subnet_mask eq $intf_mask)) {
				# we have a match
				
				$match = 1;

				my %interface_data;
					
				# set default values of this interface
				$interface_data{"ipv4_address"}= calculateSubnetIP($intf_addr,$intf_mask);
				$interface_data{"ipv6_address"}="none";
				
				$interface_data{"area"}=$area;
				
				$interface_data{"metric"}=1;
				
				$interface_data{"enabled"}=1;

				# authentication
				$interface_data{"auth_type"}="none";
				$interface_data{"auth_key"}="";
				
				# mtu
				$interface_data{"mtu_ipv4"}=0;
				$interface_data{"mtu_ipv6"}=0;
				getDefaultMTU($intf_name, \%interface_data);
				
				# put interface into hash
				$self->{router_interfaces}->{$router}->{$intf_name} = \%interface_data;
				
				print STDERR  "Got $intf_name.\n" if $debug;
			    }
			}
			
			# authentication
			if ($match && ($intf_line =~ /ip\sospf\sauthentication-key\s+(.*)/)) {
			    $self->{router_interfaces}->{$router}->{$intf_name}->{"auth_type"} = "simple";
			    $self->{router_interfaces}->{$router}->{$intf_name}->{"auth_key"} = sha1_hex($1);
			    
			}
			if ($match && ($intf_line =~ /ip\sospf\smessage-digest-key\s+(.*)\smd5\s(.*)/)) {
			    $self->{router_interfaces}->{$router}->{$intf_name}->{"auth_type"} = "md5";
			    $self->{router_interfaces}->{$router}->{$intf_name}->{"auth_key"} = sha1_hex($1.$2);
			    
			}

		    } while (($intf_line !~ /$eos/) && $intf_line);		    
		}
	    }
	}
		
	foreach my $interface (keys(%{$self->{router_interfaces}->{$router}})) {
	    # insert info into table
	    my $cmd = "INSERT into $router_interfaces values ('$router','$interface','$interfaces{$interface}->{ipv4_address}','$interfaces{$interface}->{ipv6_address}','$interfaces{$interface}->{area}','$interfaces{$interface}->{metric}','$interfaces{$interface}->{enabled}','$interfaces{$interface}->{mtu_ipv4}','$interfaces{$interface}->{mtu_ipv6}', '$interfaces{$interface}->{auth_type}', '$interfaces{$interface}->{auth_key}')";
	    
	    $self->{dbh}->do($cmd);
	}
    }

}


######################################################################
# Get OSPF network graph edges

sub getEdges {

    my $self = shift;

    # Now generate the OSPF network topological graph's edges
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
		my @metrics_and_intf = $self->{dbh}->selectrow_array("SELECT metric, interface_name, area FROM $router_interfaces WHERE router_name='$router' AND ipv4_address='$addr'");
		my @neighbor_area = $self->{dbh}->selectrow_array("SELECT area FROM $router_interfaces WHERE router_name='$neighbor' AND ipv4_address='$addr'");
		my $cmd = "INSERT into $adjacencies VALUES ('$router','$neighbor','$metrics_and_intf[0]','$metrics_and_intf[1]','$addr','$metrics_and_intf[2]','$neighbor_area[0]')";
		$self->{dbh}->do($cmd);
	    }
	}
	
	# Insert manually configured neighbors
	foreach my $interface (keys(%{$self->{router_interfaces}->{$router}})) {
	    if (defined($self->{router_interfaces}->{$router}->{$interface}->{"ptm_neighbors"})) {
		foreach my $ptm_neighbor (@{$self->{$router_interfaces}->{$router}->{$interface}->{"ptm_neighbors"}}) {
		    my $cmd = "INSERT into $adjacencies VALUES ('$router','$ptm_neighbor',$self->{$router_interfaces}->{$router}->{$interface}->{metric},'$interface',$self->{$router_interfaces}->{$router}->{$interface}->{ipv4_addr})";
		    $self->{dbh}->do($cmd);
		}
	    }
	}
    }

}
######################################################################
# Organize Area Info for each router

sub getAreaInfo {

    my $self = shift;

    foreach my $area (keys(%{$self->{areas}})) {
	# Check that the $area isn't already in the database
	my @areas = $self->{dbh}->selectrow_array("SELECT area FROM $area_info WHERE area = '$area'");
	if ($areas[0] eq $area) {
	    # skip
	    next;
	}
	
	# insert into 'area_info' table
	my $cmd = "INSERT INTO $area_info VALUES ('$area','$self->{areas}->{$area}->{stub}','$self->{areas}->{$area}->{nssa}','$self->{areas}->{$area}->{auth_type}')";
	$self->{dbh}->do($cmd);
    }
}

######################################################################
# Organize info for each router

sub getRouterInfo {
    my $self = shift;

    foreach my $router (@{$self->{nodes}}) {
	# Query DB for loopback interface
	my @router_info = $self->{dbh}->selectrow_array("SELECT ipv4_address,ipv6_address FROM $router_interfaces WHERE interface_name REGEXP 'Loopback.*' AND router_name = '$router'");
	
	# insert into 'router_info' table
	my $cmd = "INSERT INTO $router_info VALUES ('$router','$router_info[0]','$router_info[1]')";
	$self->{dbh}->do($cmd);
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
    }
    elsif ($name =~ /Ethernet/) {
	$$data{"mtu_ipv4"} = 1500;
	$$data{"mtu_ipv6"} = 1500;
    }
    else {
	$$data{"mtu_ipv4"} = 4470;
	$$data{"mtu_ipv6"} = 4470;

    }
    

}


1;
