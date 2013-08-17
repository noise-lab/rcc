#!/usr/bin/perl

package ConfigISIS_Juniper;

use strict;

use JuniperTypes;
use ConfigCommon;
use ConfigParse;
use ConfigDB;

use Digest::SHA1 qw(sha1_hex);

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

    #$configdir = "/home/hongyihu/juniper";
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
	my $rfilename = $configdir . "/" . $router . "-jconfg";
	print STDERR  "ConfigISIS_Juniper: Looking at $rfilename.\n" if $debug;
	open (RFILE, "$rfilename") || die "can't open $rfilename: $!\n";
	
	# Parse the file
	while (<RFILE>) {
	    chomp;
	    
	    # Find protocols section
	    if ($_ =~ /^protocols\s+\{/) {
		print STDERR  "Parsing Protocols Section for IS-IS Configuration.\n" if $debug;
		my $scope=1;
		
		do {
		    # Look for IS-IS section
		    chomp(my $line = <RFILE>);
		    check_scope($line, \$scope);
		    #print STDERR  "Scope is $scope.\n" if $debug;
		    if ($line =~ /isis\s+\{/) {
			print STDERR  "Found IS-IS Protocols Section.\n" if $debug;
			
			
			print STDERR  "Parsing interfaces configured for IS-IS...\n" if $debug;		    
			my $if_scope=1;
			
			do {			
			    chomp(my $if_line = <RFILE>);
			    
			    # First, check to see if IS-IS is disabled			    
			    if ($if_line =~ /^\s*disable/) {
				$self->{router_options}->{$router}->{"isis_disabled"} = 1;
			    }

			    # Check the type of authentication
			    if ($if_line =~ /^\s*authentication-type\s+(.*);/) {
				$self->{router_options}->{$router}->{"auth_type"} = $1;
			    }

			    # Store hash of auth-key
			    if ($if_line =~ /^\s*authentication-key\s+(.*);/) {
				$self->{router_options}->{$router}->{"auth_key"} = sha1_hex($1);
			    }
			    

			    # Check if wide metrics are used
			    if ($if_line =~ /^(.*)wide-metrics-only;/) {
				my $level = $1;
				if ($1 =~ /level 1/) {
				    $self->{router_options}->{$router}->{"wide_area_metrics_lvl1"} = 1;
				}
				if ($1 =~ /level 2/) {
				    $self->{router_options}->{$router}->{"wide_area_metrics_lvl2"} = 1;
				}
				
			    }
			    
			    # Look for interfaces
			    
			    check_scope($if_line, \$scope);
			    check_scope($if_line, \$if_scope);
			    
			    #print STDERR  "If_Scope is $if_scope.\n";
			    if ($if_line =~ /interface\s+(.*)\s+\{/) {

				# get interface name
				my $intf_name = $1;

				# create hash table of data for the interface
				my %interface_data;

				# set default values of this interface
				$interface_data{"ipv4_address"}="none";
				$interface_data{"ipv6_address"}="none";
				$interface_data{"iso_address"}="none";

				$interface_data{"lvl1_metric"}=10;
				$interface_data{"lvl2_metric"}=10;

				$interface_data{"lvl1_enabled"}=1;
				$interface_data{"lvl2_enabled"}=1;

				$interface_data{"lvl1_priority"}=64;
				$interface_data{"lvl2_priority"}=64;

				# mtu
				$interface_data{"mtu_ipv4"}=0;
				$interface_data{"mtu_ipv6"}=0;
				$interface_data{"mtu_iso"}=0;
				getDefaultMTU($intf_name, \%interface_data);

				# put interface into hash
				$self->{router_interfaces}->{$router}->{$intf_name} = \%interface_data;

				print STDERR  "Got $intf_name.\n" if $debug;

				
				my $if_desc_scope=1;
				
				do {
				    chomp(my $if_desc_line = <RFILE>);
				
				    check_scope($if_desc_line, \$scope);
				    check_scope($if_desc_line, \$if_scope);
				    check_scope($if_desc_line, \$if_desc_scope);
				    
				    # Try to parse out other options:
				    
				    # Interface disabled?
				    if ($if_desc_line =~ /^\s*disable/) {
					$interface_data{"lvl1_enabled"} = 0;
					$interface_data{"lvl2_enabled"} = 0;
				    }

				    # Mesh group
				    if ($if_desc_line =~ /mesh-group\s+(.*)\s*;/) {
					my $mesh_num = $1;
					# check to see if this mesh group exists, and if so,
					# add this router
					push(@{$self->{mesh_groups}->{$mesh_num}}, $router . "\\" . $intf_name);
#					if (defined($self->{mesh_groups}->{$mesh_num})) {
#					    
# 					}
# 					else {
# 					    # create an entry for the mesh group
# 					    push(@{$self->{mesh_groups}->{$mesh_num}}, $mesh_num);
# 					}
				    }
				    
				    # Level 1 config info
				    if ($if_desc_line =~ /level 1(.*)/) {
					
					my $statement = $1;
					
					# start of a description block?
					if ($statement =~ /\{/) {
					    my $level_scope = 1;
					    
					    do {
						chomp (my $level_line = <RFILE>);
						
						check_scope($level_line, \$scope);
						check_scope($level_line, \$if_scope);
						check_scope($level_line, \$if_desc_scope);
						check_scope($level_line, \$level_scope);
						
						if ($level_line =~ /^\s*disable/) {
						    $interface_data{"lvl1_enabled"} = 0;
						}
						
						if ($level_line =~ /^\s*metric\s+(.*)\s*;/) {
						    $interface_data{"lvl1_metric"} = $1;
						}
						
						if ($level_line =~ /^\s*priority\s+(.*)\s*;/) {
						    $interface_data{"lvl1_priority"} = $1;
						}
						
						
					    } while ($level_scope);
					    
					}
					
					# or just a single statement?
					if ($statement =~ /disable/) {
					    $interface_data{"lvl1_enabled"} = 0;
					}
					
					if ($statement =~ /metric\s+(.*)\s*;/) {
					    $interface_data{"lvl1_metric"} = $1;
					}
					
				    }
				    
				    # Level 2 config info
				    if ($if_desc_line =~ /level 2(.*)/) {
					
					my $statement = $1;
					
					# start of description block?
					if ($1 =~ /\{/) {
					    my $level_scope = 1;
					    
					    do {
						chomp (my $level_line = <RFILE>);
						
						check_scope($level_line, \$scope);
						check_scope($level_line, \$if_scope);
						check_scope($level_line, \$if_desc_scope);
						check_scope($level_line, \$level_scope);
												
						if ($level_line =~ /^\s*disable/) {
						    $interface_data{"lvl2_enabled"} = 0;
						}
						
						if ($level_line =~ /^\s*metric\s+(.*)\s*;/) {
						    $interface_data{"lvl2_metric"} = $1;
						}
						
						if ($level_line =~ /^\s*priority\s+(.*)\s*;/) {
						    $interface_data{"lvl2_priority"} = $1;
						}
						
					    } while ($level_scope);
					    
					}
					
					# or just a single statement?
					if ($statement =~ /disable/) {
					    $interface_data{"lvl2_enabled"} = 0;
					}
					
					if ($statement =~ /metric\s+(.*)\s*;/) {
					    $interface_data{"lvl2_metric"} = $1;
					}
				    }
				    
				
				} while ($if_desc_scope);
			    }
			} while ($if_scope);
			
		    }
		    else {
			# no interfaces are configured for IS-IS
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
		
	    # checking interfaces and filter for IS-IS configured
		if ($_ =~ /^interfaces\s*\{/) {
		    print STDERR  "Parsing addresses from IS-IS interfaces.\n" if $debug;
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


					    # IPv6 address
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
					    
					    
					    # ISO address
					    if ($unit_line =~ /family\s+iso\s*\{/) {
						print STDERR "Found $unit_line.\n" if $debug;
						my $iso_scope = 1;
						
						do {
						    chomp(my $iso_line = <RFILE>);
						    check_scope($iso_line, \$scope);
						    check_scope($iso_line, \$if_scope);
						    check_scope($iso_line, \$unit_scope);
						    check_scope($iso_line, \$iso_scope);
						    
						    # Parse for MTU
						    if ($iso_line =~ /mtu\s+(.*);/) {
							$interfaces{$interface}->{"mtu_iso"} = $1;
						    }

						    # get address
						    # should change this later to deal with lo0 having multiple addresses
						    if ($iso_line =~ /address\s+(.*);/) {
							my $addr = $1;
							print STDERR  "Got $addr.\n" if $debug;
							
							# put the address and subnet mask into hash table
							$interfaces{$interface}->{"iso_address"} = $addr;
							
							# break out;
							#last;
						    }

						} while ($iso_scope);
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
	    my $cmd = "INSERT into $router_interfaces values ('$router','$interface','$subnet_ip','$interfaces{$interface}->{ipv6_address}','$interfaces{$interface}->{iso_address}','$interfaces{$interface}->{lvl1_enabled}','$interfaces{$interface}->{lvl2_enabled}','$interfaces{$interface}->{lvl1_metric}','$interfaces{$interface}->{lvl2_metric}','$interfaces{$interface}->{mtu_ipv4}','$interfaces{$interface}->{mtu_ipv6}','$interfaces{$interface}->{mtu_iso}')";
	    
	    $self->{dbh}->do($cmd);
	}
	print STDERR "Done with $router.\n" if $debug;
	
	
    }
    
}


######################################################################
# Get IS-IS network graph edges

sub getEdges {

    my $self = shift;

    # Now generate the IS-IS network topological graph's edges
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
		my @metrics_and_intf = $self->{dbh}->selectrow_array("SELECT level1_metric,level2_metric, interface_name FROM $router_interfaces WHERE router_name='$router' AND ipv4_address='$addr'");

		# determine level of adjacency
		my @origin_isis_levels = $self->{dbh}->selectrow_array("SELECT level1_routing, level2_routing FROM $router_interfaces WHERE router_name='$router' AND ipv4_address='$addr'");
		my @neighbor_isis_levels = $self->{dbh}->selectrow_array("SELECT level1_routing, level2_routing FROM $router_interfaces WHERE router_name='$neighbor' AND ipv4_address='$addr'");
		
		my $level1 = 0;
		my $level2 = 0;
		if ($origin_isis_levels[0] eq $neighbor_isis_levels[0]) {
		    $level1 = 1;
		}
		if ($origin_isis_levels[1] eq $neighbor_isis_levels[1]) {
		    $level2 = 1;
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
# Compute Path Information
# This assumes that all the adjacencies are configured properly.

sub computePaths {
    my $self = shift;
    
    # loop through routers
    foreach my $router (@{$self->{nodes}}) {
	
	# for each router, compute the shortest path to every other router
	foreach my $dest (@{$self->{nodes}}) {
	    if ($router eq $dest) {
		# skip, no need to compute shortest path to self
		next;
	    }

	    # determine if the destination is in the same level 1 routing domain
	    my $router_iso = $self->{router_interfaces}->{$router}->{"lo0.0"}->{"iso_address"};
	    my $dest_iso = $self->{router_interfaces}->{$dest}->{"lo0.0"}->{"iso_address"};
	    if ($router_iso eq $dest_iso) {
		
	    }
	    elsif (1) {
		# check if external routing info is being leaked to level 1 routers
		# this would mean that the search can start directly from the origin
		# instead of the closest area border router
	    }
	    else {
		# otherwise, find the closest area border router and search from there
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
	my @router_info = $self->{dbh}->selectrow_array("SELECT iso_address,ipv4_address,ipv6_address FROM $router_interfaces WHERE interface_name = 'lo0.0' and router_name = '$router'");

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

sub db_router_interfaces {
    my $self = shift;    
    
    foreach my $router (keys %{$self->{router_interfaces}}) {
	foreach my $interface (keys %{$self->{router_interfaces}->{$router}}) {
	    # insert into table
	    my $cmd = "INSERT into $router_interfaces values ('$router','$interface','$self->{router_interfaces}->{$interface}->{ipv4_address}','$self->{router_interfaces}->{$interface}->{ipv6_address}','$self->{router_interfaces}->{$interface}->{iso_address}','$self->{router_interfaces}->{$interface}->{lvl1_enabled}','$self->{router_interfaces}->{$interface}->{lvl2_enabled}','$self->{router_interfaces}->{$interface}->{lvl1_metric}','$self->{router_interfaces}->{$interface}->{lvl2_metric}','$self->{router_interfaces}->{$interface}->{mtu_ipv4}','$self->{router_interfaces}->{$interface}->{mtu_ipv6}','$self->{router_interfaces}->{$interface}->{mtu_iso}')";
	    
	    $self->{dbh}->do($cmd);
	}
    }
}

sub db_adjacencies {
}

sub db_router_info {
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
	$$data{"mtu_iso"} = 4470;
    }

    if ($name =~ /ge/) {
	$$data{"mtu_ipv4"} = 1500;
	$$data{"mtu_iso"} = 1497;
    }

    if ($name =~ /at/) {
	$$data{"mtu_ipv4"} = 4470;
	$$data{"mtu_ipv6"} = 4470;
	$$data{"mtu_iso"} = 4470;
    }
    

}


######################################################################
sub is_isis_disabled {
    
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
	#my $subnet_ip = $subnet_ip_parts[0] . "." . $subnet_ip_parts[1] . "." . $subnet_ip_parts[2] . "." . $subnet_ip_parts[3];
	my $subnet_ip = join(".",@subnet_ip_parts);
	
	return $subnet_ip;
    }
}

1;
