#!/usr/bin/perl

package ConfigOSPF_Juniper;

use strict;

use JuniperTypes;
use ConfigCommon;
use ConfigParse;
use ConfigDB;

use Digest::SHA1 qw(sha1_hex);

require Exporter;
use vars(qw(@ISA @EXPORT $configdir @ospf_db_tables));
@ISA = ('Exporter');

my $debug = 1;

# Differences in OSPFv3 (from Juniper documentation)
#OSPFv3 is a modified version of OSPF that supports Internet Protocol version 6
#(IPv6) addressing. OSPFv3 differs from OSPFv2 in the following ways:
#
#    All neighbor ID information is based on a 32-bit router ID.
#
#    The protocol runs per link rather than per subnet.
#
#    Router and network link-state advertisements (LSAs) do not carry prefix information.
#
#    Two new LSA types are included: link-LSA and intra-area-prefix-LSA



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
    my @rfiles = <$configdir/*-jconfg>;

    print STDERR  "Looping through router files.\n" if $debug;
    foreach my $rfile (@rfiles) {
	print STDERR  "Looking for $rfile.\n" if $debug;
	if ($rfile =~ /^.*\/(.*)-jconfg/){
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
	

	# Open the file for parsing
	my $rfilename = $configdir . "/" . $router . "-jconfg";
	print STDERR  "ConfigOSPF_Juniper: Looking at $rfilename.\n" if $debug;
	open (RFILE, "$rfilename") || die "can't open $rfilename: $!\n";
	
	# Parse the file
	while (<RFILE>) {
	    chomp;
	    
	    # Find protocols section
	    if ($_ =~ /^protocols\s+\{/) {
		print STDERR  "Parsing Protocols Section for OSPF Configuration.\n" if $debug;
		my $scope=1;
		
		do {
		    # Look for OSPF section
		    chomp(my $line = <RFILE>);
		    check_scope($line, \$scope);
		    #print STDERR  "Scope is $scope.\n" if $debug;
		    if ($line =~ /ospf(.*)\s+\{/) {
			if ($1 =~ /3/) {
			    print STDERR  "Found OSPFv3 Section.\n" if $debug;
			    $self->{router_options}->{$router}->{"ospf_version"} = 3;
			}
			else {
			    print STDERR  "Found OSPFv2 Section.\n" if $debug;
			}
			
			print STDERR  "Parsing interfaces configured for OSPFv2\n" if $debug;		    
			my $if_scope=1;
			
			do {			
			    chomp(my $if_line = <RFILE>);
			    
			    check_scope($if_line, \$scope);
			    check_scope($if_line, \$if_scope);

			    # First, check to see if OSPF is disabled			    
			    if ($if_line =~ /^\s*disable/) {
				$self->{router_options}->{$router}->{"ospf_disabled"} = 1;
			    }

			    
			    # Look for areas

			    if ($if_line =~ /^\s*area\s(.*)\{/) {
				my $area = $1;

				# Check if the area is already defined
				if (!defined($self->{areas}->{$area})) {
				    my %area_options;
				    $area_options{"stub"}=0;
				    $area_options{"nssa"}=0;
				    
				    $area_options{"auth_type"}="none";
				    
				    $self->{areas}->{$area} = \%area_options;

				}
				# Look for interfaces and area configuration options		   
				my $area_scope = 1;

				do {
				    chomp(my $area_line = <RFILE>);
				    
				    check_scope($area_line, \$scope);
				    check_scope($area_line, \$if_scope);
				    check_scope($area_line, \$area_scope);

				    # area configuration options

				    if ($area_line =~ /stub/) {
					# area is configured as stub area
					$self->{areas}->{$area}->{"stub"} = 1;
				    }

				    if ($area_line =~ /nssa/) {
					# area is configured as stub area
					$self->{areas}->{$area}->{"nssa"} = 1;

					my $nssa_scope = 1;
					
					do {
					    chomp(my $nssa_line = <RFILE>);
				    
					    check_scope($nssa_line, \$scope);
					    check_scope($nssa_line, \$if_scope);
					    check_scope($nssa_line, \$area_scope);
					    check_scope($nssa_line, \$nssa_scope);
					    
					    # parse other options

					} while ($nssa_scope);
					
				    }

				    if ($area_line =~ /authentication-type\s(.*);/) {
					# none, simple or md5
					$self->{areas}->{$area}->{"auth_type"} = $1;
				    }
				    

				    # interface declaration with no braces
				    if ($area_line =~ /interface\s+(.*);/) {
					# get interface name
					my $intf_name = $1;
					
					# create hash table of data for the interface
					my %interface_data;
					
					# set default values of this interface
					$interface_data{"ipv4_address"}="none";
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

				    # interface declaration with braces
				    if ($area_line =~ /interface\s+(.*)\s+\{/){
					
					# get interface name
					my $intf_name = $1;
					
					# create hash table of data for the interface
					my %interface_data;
					
					# set default values of this interface
					$interface_data{"ipv4_address"}="none";
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
					
				    
					my $if_desc_scope=1;
				    
					do {
					    chomp(my $if_desc_line = <RFILE>);
					    
					    check_scope($if_desc_line, \$scope);
					    check_scope($if_desc_line, \$if_scope);
					    check_scope($if_desc_line, \$area_scope);
					    check_scope($if_desc_line, \$if_desc_scope);
					    
					    # Try to parse out other options:
					    
					    # Interface disabled?
					    if ($if_desc_line =~ /^\s*disable/) {
						$self->{router_interfaces}->{$router}->{$intf_name}->{"enabled"}=1;
					    }

					    # metric
					    if ($if_desc_line =~ /^\s*metric\s(.*)/) {
						$interface_data{"metric"}=$1;
					    }

					    # point-to-multipoint, OSPFv2 only
					    if ($if_desc_line =~ /^\s*neighbor\s+(.*);/) {
						push(@{$self->{router_interfaces}->{$router}->{$intf_name}->{"ptm_neighbors"}}, $1);
					    }

					    # Handle this later
# 					    # nonbroadcast mode, OSPFv2 only
# 					    if ($if_desc_line =~ /^\s*interface-type\snbma;/) {
						
# 						push(@{$self->{router_interfaces}->{$router}->{$intf_name}->{"nbma_neighbors"}}, $1);
# 					    }

					    # authentication
					    # FIXME

					    
					    
					} while ($if_desc_scope);
				    }
				    
				} while ($area_scope);
			    }

			} while ($if_scope);
			
		    }
		    else {
			# no interfaces are configured for OSPF
			#print STDERR  "No interfaces are configured for OSPF for $rfilename.\n" if $debug;
			# FIXME: What do we do?
		    }
		} while ($scope);
	    }
	}
	
	# Now find IP addresses for these interfaces
	my @intrfcs = keys(%interfaces);
	
	foreach my $interface (@intrfcs) {
	    	    
	    # separate interface name and unit number
	    # format is interface_name.unit_number e.g. "ge-0/0/0.11
	    # Assumes only one "."
	    my ($interface_name,$unit_number) = split('\.', $interface);
	    
	    # Close filehandle and reopen
	    close(RFILE);
	    open(RFILE, "$rfilename") || die "can't open $rfilename: $!\n";
	    
	    while (<RFILE>) {
		chomp;
		
	    # checking interfaces and filter for OSPF configured
		if ($_ =~ /^interfaces\s*\{/) {
		    print STDERR  "Parsing addresses from OSPF interfaces.\n" if $debug;
		    my $scope=1;
		    
		    do {
			chomp(my $line = <RFILE>);
			check_scope($line, \$scope);
			
			# Strip off " {" and trim
			$line =~ s/\s*\{//;
			$line =~ s/\s*//;
			
			# print STDERR "Comparing $line to $interface_name.\n" if $debug;
			
			if ($line eq $interface_name) {
			    # look for the unit number
			    print STDERR  "Found $line.  Looking for unit $unit_number.\n" if $debug;
			    my $if_scope = 1;
			    
			    do {
				chomp(my $if_line = <RFILE>);
				
				check_scope($if_line, \$scope);
				check_scope($if_line, \$if_scope);

				# Need to be a bit more complicated here
				# Check to see if the line is the start of
				# a unit description and increase the
				# scope if so, even if it's not the unit
				# we're looking for
				
				if ($if_line =~ /unit\s+.*\s*\{/) {

				    # increase scope
				    my $unit_scope = 1;
				    
				    # Strip off " {" and white spaces
				    $if_line =~ s/\s*\{//;
				    $if_line =~ s/\s*//;
				    
				    
				    print STDERR  "Comparing $if_line to unit $unit_number.\n" if $debug;
				    if ($if_line eq "unit " . $unit_number) {
					print STDERR  "Found $if_line.  Looking for address.\n" if $debug;
					# get addresses
					
					
					do {

					    chomp(my $unit_line = <RFILE>);
					    check_scope($unit_line, \$scope);
					    check_scope($unit_line, \$if_scope);
					    check_scope($unit_line, \$unit_scope);
					
					    print STDERR "Looking at $unit_line.\n" if $debug;
					    					    
					    print STDERR "Scope is $scope.\n" if $debug;
					    print STDERR "If_scope is $if_scope.\n" if $debug;
					    print STDERR "Unit_scope is $unit_scope.\n" if $debug;
					    
					    print STDERR "Current Interface is $interface.\n" if $debug;

					    # IPv4 address
					    if ($unit_line =~ /family\s+inet\s*\{/) {
						my $inet_scope = 1;
						
						do {
						    chomp(my $inet_line = <RFILE>);
						    check_scope($inet_line, \$scope);
						    check_scope($inet_line, \$if_scope);
						    check_scope($inet_line, \$unit_scope);
						    check_scope($inet_line, \$inet_scope);

						    # get address
						    print STDERR "Looking at $inet_line.\n" if $debug;
						    
						    print STDERR "Scope is $scope.\n" if $debug;
						    print STDERR "If_scope is $if_scope.\n" if $debug;
						    print STDERR "Unit_scope is $unit_scope.\n" if $debug;
						    print STDERR "inet_scope is $inet_scope.\n" if $debug;

						    # Parse for MTU
						    if ($inet_line =~ /mtu\s+(.*);/) {
							$interfaces{$interface}->{"mtu_ipv4"} = $1;
						    }
						
						    if ($inet_line =~ /address\s+(.*)\/(.*)\s*\{/) {
							my $addr = $1;
							my $subnet_mask = $2;

							# Put in hash table if we don't already 
							# have an address recorded
							if ($interfaces{$interface}->{"ipv4_address"} eq "none") {
							    print STDERR  "Got $addr and $subnet_mask.\n" if $debug;
							    $interfaces{$interface}->{"ipv4_address"} = $addr . "/" . $subnet_mask;
							    print STDERR "Address is $interfaces{$interface}->{ipv4_address}.\n" if $debug;
							}

							# check to see if this is the preferred address

							my $addr_scope = 1;
							do {
							
							    chomp(my $addr_line = <RFILE>);
							    check_scope($addr_line, \$scope);
							    check_scope($addr_line, \$if_scope);
							    check_scope($addr_line, \$unit_scope);
							    check_scope($addr_line, \$inet_scope);
							    check_scope($addr_line, \$addr_scope);

							    if ($addr_line =~ /preferred;/) {
								print STDERR  "Got $addr and $subnet_mask.\n" if $debug;
								
								# put the address and subnet mask into hash table
								$interfaces{$interface}->{"ipv4_address"} = $addr . "/" . $subnet_mask;
							    }

							} while ($addr_scope);

						    }
						    

						    if ($inet_line =~ /address\s+(.*)\/(.*);/) {
							my $addr = $1;
							my $subnet_mask = $2;

							# put the address and subnet mask into hash table 
							# unless we already
							# have one for it
							if ($interfaces{$interface}->{"ipv4_address"} eq "none") {
							    print STDERR  "Got $addr and $subnet_mask.\n" if $debug;
							    $interfaces{$interface}->{"ipv4_address"} = $addr . "/" . $subnet_mask;
							}
						    }

						} while ($inet_scope);
					    }


					    # IPv6 address, OSPFv3 only
					    if ($unit_line =~ /family\s+inet6\s*\{/) {
						my $inetv6_scope = 1;
						
						do {
						    chomp(my $inetv6_line = <RFILE>);
						    check_scope($inetv6_line, \$scope);
						    check_scope($inetv6_line, \$if_scope);
						    check_scope($inetv6_line, \$unit_scope);
						    check_scope($inetv6_line, \$inetv6_scope);
						
						    print STDERR "Looking at $inetv6_line.\n" if $debug;

						    # Parse for MTU
						    if ($inetv6_line =~ /mtu\s+(.*);/) {
							$interfaces{$interface}->{"mtu_ipv6"} = $1;
						    }

						    # get address
						    if ($inetv6_line =~ /address\s+(.*)\/(.*)\s*\{/) {
							my $addr = $1;
							my $subnet_mask = $2;

							# Put in hash table if we don't already 
							# have an address recorded
							if ($interfaces{$interface}->{"ipv6_address"} eq "none") {
							    print STDERR  "Got $addr and $subnet_mask.\n" if $debug;
							    $interfaces{$interface}->{"ipv6_address"} = $addr . "/" . $subnet_mask;
							}

							# check to see if this is the preferred address
							my $addr_scope = 1;
							do {
							
							    chomp(my $addr_line = <RFILE>);
							    check_scope($addr_line, \$scope);
							    check_scope($addr_line, \$if_scope);
							    check_scope($addr_line, \$unit_scope);
							    check_scope($addr_line, \$inetv6_scope);
							    check_scope($addr_line, \$addr_scope);

							    if ($addr_line =~ /preferred;/) {
								print STDERR  "Got $addr and $subnet_mask.\n" if $debug;
								
								# put the address and subnet mask into hash table
								$interfaces{$interface}->{"ipv6_address"} = $addr . "/" . $subnet_mask;
							    }

							} while ($addr_scope);
						    }
						    

						    if ($inetv6_line =~ /address\s+(.*)\/(.*);/) {
							my $addr = $1;
							my $subnet_mask = $2;

							# put the address and subnet mask into hash table 
							# unless already occupied
							if ($interfaces{$interface}->{"ipv6_address"} eq "none") {
							    print STDERR  "Got $addr and $subnet_mask.\n" if $debug;
							    $interfaces{$interface}->{"ipv6_address"} = $addr . "/" . $subnet_mask;
							}
						    }

						} while ($inetv6_scope);
					    }
					    
					} while ($unit_scope);
				    }
				    else {
					
					# unit number did not match up so
					# we just ignore everything to the
					# end of the block (before the
					# enclosing '}')
					
					do {
					    chomp(my $unit_line = <RFILE>);
					    check_scope($unit_line, \$scope);
					    check_scope($unit_line, \$if_scope);
					    check_scope($unit_line, \$unit_scope);
					} while ($unit_scope);
				    }
				}
			    } while ($if_scope);
			}
		    } while ($scope);
		} 
	    }
	    
	    # Figure out subnet
	    my $subnet_ip = calculateSubnetIP($interfaces{$interface}->{"ipv4_address"});

	    # put $subnet_ip into the %interface_data hash table
	    $interfaces{$interface}->{"subnet_ip"} = $subnet_ip;
	    
	    # insert into table
	    my $cmd = "INSERT into $router_interfaces values ('$router','$interface','$subnet_ip','$interfaces{$interface}->{ipv6_address}','$interfaces{$interface}->{area}','$interfaces{$interface}->{metric}','$interfaces{$interface}->{enabled}','$interfaces{$interface}->{mtu_ipv4}','$interfaces{$interface}->{mtu_ipv6}', '$interfaces{$interface}->{auth_type}', '$interfaces{$interface}->{auth_key}')";
	    
	    $self->{dbh}->do($cmd);
	}
	print STDERR "Done with $router.\n" if $debug;
	
	
    }
    
}


######################################################################
# Get OSPF network graph edges

sub getEdges {

    my $self = shift;

    # Now generate the OSPF network topological graph's edges
    foreach my $router (@{$self->{nodes}}) {
	# Get subnet addresses for each router	
	
	my $subnet_addrs = $self->{dbh}->selectcol_arrayref("SELECT ipv4_address FROM $router_interfaces WHERE router_name='$router' AND interface_name != 'lo0.0'");
	
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

	# otherwise, insert into 'area_info' table
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
	my @router_info = $self->{dbh}->selectrow_array("SELECT ipv4_address,ipv6_address FROM $router_interfaces WHERE interface_name = 'lo0.0' and router_name = '$router'");
	
	# insert into 'router_info' table
	my $cmd = "INSERT INTO $router_info VALUES ('$router','$router_info[0]','$router_info[1]')";
	$self->{dbh}->do($cmd);
    }

}

######################################################################

sub check_scope {
    my ($line, $rscope) = @_;
    
    if ($line =~ /\{/) {
	$$rscope++; 
    }
    if ($line =~ /\}/) { 
	$$rscope--; 
    }

}





######################################################################

# data from http://www.juniper.net/techpubs/software/junos/junos56/swconfig56-interfaces/html/interfaces-physical-config5.html

sub getDefaultMTU {
    my ($name, $data) = @_;
    
    if ($name =~ /so/) {
	$$data{"mtu_ipv4"} = 4470;
	$$data{"mtu_ipv6"} = 4470;
    }

    if ($name =~ /ge/) {
	$$data{"mtu_ipv4"} = 1500;
    }

    if ($name =~ /at/) {
	$$data{"mtu_ipv4"} = 4470;
	$$data{"mtu_ipv6"} = 4470;
    }
    

}


######################################################################
# Determine subnet IP from address of the form "18.238.2.232/30"

sub calculateSubnetIP {
    my $addr = shift;

    if ($addr eq "none") {
	return "none";
    }
    else {

	my ($ip, $mask) = split('/', $addr);
	print STDERR "Address is $ip.\n" if $debug;
        
	my @ip_parts = split(/\./,$ip);
	
	# Convert the mask from CIDR to 255.255.foo.bar form
	my $quotient = int($mask/8);
	my $remainder = $mask % 8;
	my @mask_parts;
	
	for (my $i = 0; $i < 4; $i++) {
	    if ($i < $quotient) { 
		$mask_parts[$i] = 255;
	    }
	    if ($i == $quotient) {
		# initialize to 0
		$mask_parts[$i] = 0;
		for (my $j = 1; $j < $remainder + 1; $j++) {
		    $mask_parts[$i] = $mask_parts[$i] + 2**(8-$j);
		}
	    }
	    if ($i > $quotient) {
		$mask_parts[$i] = 0;
	    }
	    # print STDERR "Mask part $i is $mask_parts[$i].\n" if $debug;
	}
	
	
	# Bitwise And the IP and the mask together
	my @subnet_ip_parts;
	for (my $i = 0; $i < 4; $i++) {
	    $subnet_ip_parts[$i] = $ip_parts[$i] & $mask_parts[$i];
	}
	
	# Put IP back together
	my $subnet_ip = join(".",@subnet_ip_parts);
	
	return $subnet_ip;
    }
}

1;
