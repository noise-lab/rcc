#!/usr/bin/perl

package ConfigIF_Cisco;

use Data::Dumper;
use strict;

use CiscoTypes;
use ConfigCommon;
use ConfigParse;
use ConfigDB;

require Exporter;
use vars(qw(@ISA @EXPORT $configdir @db_tables));
@ISA = ('Exporter');


######################################################################
# Constructor

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);

    $self->{dbh} = &dbhandle($config_if);

    $self->{nodes};          # array of router names

    $self->{node_edges};     # router_name => adjacency list (router names)
    $self->{route_maps};     # router_name => list of maps

    $self->{router_options};   # global router options
    $self->{session_options}; # get the options for some session ID #
    $self->{session_id};       # get the session ID # for some (router, neighbor) tuple

    $self->{name_to_loopbacks};  # router_name => loopback IP address
    $self->{loopback_to_name};  # loopback IP address => router_name

    $self->{has_ebgp};       # has_ebgp{router} => yes/no
    $self->{import_fn};      # import{router}->{nei_lb} => canonical rep
    $self->{export_fn};      # export{router}->{nei_lb} => canonical rep
    
    $self->{canonical_rms};  # map canonical number to pattern
    $self->{my_asn};

    $self->{networks};       # networks advertised by each router
    $self->{routes};
    $self->{interfaces};

    $self->{parse_errors};
    @{$self->{global_options}} = (qw(asn 
				     no_synchronization
				     deterministic-med
				     compare-routerid
				     router-id
				     cluster-id));

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

    foreach my $rfile (@rfiles) {
	if ($rfile =~ /^.*\/($rtr_name)-confg/){
	    push(@{$self->{nodes}}, $1);
	}
    }
    
}


######################################################################
# get unidirectional edges in the iBGP flow graph

sub getEdgesWithRouteMaps {
    # note: each internal edge must have a corresponding route map that
    # describes how routes will be treated along that path
    # each route map is uniquely named, and a pointer to how that 
    # manipulation proceeds.

    # There's no notion of security levels in construction of the data flow 
    # graph itself.  That comes in when the lattice/policy gets applied to the 
    # flow graph

    my $self = shift;
    my $num_sessions = 0;

    my %router_to_lbadj = ();

    # eventually, we construct f: (router, neighbor_addr) -> canonical route map
    my %router_to_irm_canonical = ();
    my %router_to_orm_canonical = ();

    my %canonical_rms = ();
    my %canonical_acls = ();

    my $prefix_acls;
    my %pfx_acls_in_rm = ();
	

    
    foreach my $router (@{$self->{nodes}}) {

	my $rfilenames = &router_to_config($router);
	my $rfilename = @$rfilenames[0];

	print STDERR "$rfilename\n";
	open (RFILE, "$rfilename") || die "can't open $rfilename: $!\n";

	# router-specific stuff
	my %list = ();
	my %neighbor_to_irm_name = ();
	my %neighbor_to_orm_name = ();
	my %rm_name_to_canonical = ();
	my %rm_clauses = ();


	my %neighbor_to_pfxacl_in_name = ();
	my %neighbor_to_pfxacl_out_name = ();

	while (<RFILE>) {
	    chomp;
	    my $lb;

	    if ($_ =~ /$loopback_regexp/){
		my $line = "";
		do {
		    $line = <RFILE>;
		} while ($line !~ /ip\s+address\s+\@*(\d+\.\d+\.\d+\.\d+)\@*/ && $line);

		#last if (!$line);
		$lb = $1;
		print "$router has loopback $lb\n" if ($debug > 1);

		push(@{$self->{name_to_loopbacks}->{$router}}, $lb);
		$self->{loopback_to_name}->{$lb} = $router;

	    } elsif ($_ =~ /$interface_regexp/) {
		my $iname = $1;

		my $line = "";
		do {
		    $line = <RFILE>;		

		    if ($line =~ /$ip_mask_regexp/) {
			my $addr = $1;
			my $mask = $2;
			if ($addr != '') {
			    push(@{$self->{interfaces}->{$router}->{$iname}}, "$addr/$mask");
			}
		    }
		    

    
		} while (($line !~ /$eos/) && $line);
		
#	    } elsif ($_ =~ /$acl_ext_scope/) {

	    } elsif ($_=~ /$bgp_scope|$ipv4_scope/) {

		# figure out:
		# 1. BGP adjacencies
		# 2. route maps applied to those adjacencies
		if ($_ =~ /$bgp_scope/) {
		    my $this_asnum = $1;
		    $self->{my_asn} = $this_asnum;
		    
		    $self->{router_options}->{$router}->{'runs_bgp'} = 1;
		    $self->{router_options}->{$router}->{'asn'} = $this_asnum;
		}

		my $line = "";
		do {
		    $line = <RFILE>;
		    chomp($line);
		    
		    my $ibgp=0;
		    
		    ########################################
		    # look for global BGP options

		    if ($line =~ /no\s+synchronization/) {
			$self->{router_options}->{$router}->{'no_synchronization'} = 1;
		    }

		    # determine if this router has deterministic-med
		    if ($line =~ /deterministic-med/) {
			$self->{router_options}->{$router}->{'deterministic-med'} = 1;
		    }

		    # determine if this router has best path compare-routerid
		    if ($line =~ /compare-routerid/) {
			$self->{router_options}->{$router}->{'compare-routerid'} = 1;
		    }

		    if ($line =~ /router-id\s+($addr_mask)/) {
			my $rid = $1;
			$rid =~ s/\@//g;
			$self->{router_options}->{$router}->{'router-id'} = $rid;
		    }

		    if ($line =~ /cluster-id\s+(\d+)/) {
			$self->{router_options}->{$router}->{'cluster-id'} = $1;
		    }


		    ########################################
		    # look for options specific to BGP sessions

		    if ($line =~ /neighbor\s+($addr_mask)\s+remote-as\s+(\d+)/) {
			my $adjacency = $1;
			my $asnum = $2;

			my $nbr_ip = $adjacency;
			$nbr_ip =~ s/\@//g;

			if (!defined($self->{session_id}->{$router}->{$nbr_ip})) {
			    $self->{session_id}->{$router}->{$nbr_ip} = $num_sessions++;
			}

			$ibgp = ($asnum == $self->{my_asn});
			$self->{session_options}->{$self->{session_id}->{$router}->{$nbr_ip}}->{ebgp} = !$ibgp;
			$self->{session_options}->{$self->{session_id}->{$router}->{$nbr_ip}}->{asnum} = $asnum;

			$adjacency =~ s/\@//g;
			push(@{$router_to_lbadj{$router}}, $adjacency);
			print STDERR "$router: $adjacency\n" if ($debug > 1);

		    }


		    # see if next-hop-self is set for this session
		    if ($line =~ /neighbor\s+($addr_mask)\s+next-hop-self/) {
			my $adjacency = $1;
			$adjacency =~ s/\@//g;
			$self->{session_options}->{$self->{session_id}->{$router}->{$adjacency}}->{nh_self} = 1;
		    }


                    # see if this session is to a route-reflector client
		    if ($line =~ /neighbor\s+($addr_mask)\s+route-reflector-client/) {
			my $adjacency = $1;
			$adjacency =~ s/\@//g;
			$self->{session_options}->{$self->{session_id}->{$router}->{$adjacency}}->{rr_client} = 1;
		    }

                    # see if this session has the send-community value set
		    if ($line =~ /neighbor\s+($addr_mask)\s+send-community/) {
			my $adjacency = $1;
			$adjacency =~ s/\@//g;
			$self->{session_options}->{$self->{session_id}->{$router}->{$adjacency}}->{send_community} = 1;
		    }

                    # see if this session has remove-private-as
		    # or as-override
		    if ($line =~ /neighbor\s+($addr_mask)\s+(remove-private-as|as\-override)/) {
			my $adjacency = $1;
			$adjacency =~ s/\@//g;
			$self->{session_options}->{$self->{session_id}->{$router}->{$adjacency}}->{remove_private} = 1;
		    }


		    # see if this session is shutdown
		    if ($line =~ /neighbor\s+($addr_mask)\s+shutdown/) {
			my $adjacency = $1;
			$adjacency =~ s/\@//g;
			$self->{session_options}->{$self->{session_id}->{$router}->{$adjacency}}->{shutdown} = 1;
		    }




		    # these will be eBGP neighbors, typically
		    # (lots of of eBGP sessions with route maps)
		    if ($line =~ /neighbor\s+($addr_mask)\s+route-map\s+(\S+)\s+(in|out)/) {
			my $addr = $1;
			my $name = $2;
			my $in = ($3 =~ /in/);
			
			$addr =~ s/\@//g;
			
			if ($in) {
			    $neighbor_to_irm_name{$addr} = $name;
			} else {
			    $neighbor_to_orm_name{$addr} = $name;
			}
			print STDERR "$router->$addr: $name\n" if ($debug > 1);
		    }


		    # these will be eBGP neighbors, typically
		    # (lots of of eBGP sessions with route maps)
		    if ($line =~ /neighbor\s+($addr_mask)\s+(distribute-list|prefix-list)\s+(\S+)\s+(in|out)/) {
			my $addr = $1;
			my $name = $3;
			my $in = ($4 =~ /in/);
			
			$addr =~ s/\@//g;
			
			if ($in) {
			    $neighbor_to_pfxacl_in_name{$addr} = $name;
			} else {
			    $neighbor_to_pfxacl_out_name{$addr} = $name;
			}
			print STDERR "ACL: $router->$addr: $name\n" if ($debug > 1);
		    }


		    # what routes is BGP trying to originate here
		    if ($line =~ /$nw_mask_regexp/) { 
			my $network = $1;
			my $mask = $2;

			push(@{$self->{networks}->{$router}}, "$network/$mask");
		    } elsif ($line =~ /$nw_regexp/) {
			my $network = $1;
			push(@{$self->{networks}->{$router}}, "$network");
		    }

		    # note: we should eventually do some redistribution
		    # checks...


		} while ($line !~ /$eos/);
		
	    } elsif ($_ =~ /$rm_scope/) {
		# resolve route maps into a canonical rep

		my $rm_name = $1;
		my $rm_clause = ++$rm_clauses{$router}->{$rm_name};
		my $line = "";

		# assemble the canonical rep for the route map in this var
		my $canonical = "";

		# is this a deny clause?
		my $deny = ($_ =~ /deny/);
		
		do {
		    $line = <RFILE>;
		    chomp($line);

		    if ($line =~ /$match_ip_regexp/ ||
			$line =~ /$match_ip_pfx_regexp/) {
			my $clause = $1;

			$pfx_acls_in_rm{$router}->{$rm_name}->{$rm_clause} = $clause;

			if ($clause !~ /[A-Za-z]+/) {
			    my $clause_nums = $clause;
			    my @clause_num_arr = split(/\s+/, $clause_nums);
			    
			    foreach my $clause_num (@clause_num_arr) {
				
				my $list_type = 'acc';
				
				if (defined($list{$list_type}->{$clause_num})) {
				    
				    print STDERR "resolving ip access-list $clause_num\n" if $debug;
				    printf STDERR ("%s\n",
						   &resolve_clausenum($list{$list_type}->{$clause_num}, $list_type)) if $debug;
				    
				    # append to the canonical rep
				    $canonical .= "$list_type";
				    $canonical .= &resolve_clausenum($list{$list_type}->{$clause_num}, $list_type);
				    $canonical .= "::";
				} else {
				    print "ERROR: undefined $list_type $clause_num ($router, $rm_name)\n";
				    $self->{parse_errors}->{$router}->{$rm_name}->{$def_types{$list_type}}->{$clause_num} = 1;
				}
			    }
			} elsif ($line =~ /$match_ip_pfx_regexp/) {
			    # XXX resolve match ip address prefix-list
			    my $clause = $1;
			    $pfx_acls_in_rm{$router}->{$rm_name}->{$rm_clause} = $clause;
			}

			# remove trailing delimiter
			$canonical =~ s/::$//;

		    } elsif ($line =~ /$match_regexp/) {
			my $match_type = $1;
			my $clause_nums = $2;

			my @clause_num_arr = split(/\s+/, $clause_nums);

			foreach my $clause_num (@clause_num_arr) {


			    
			    my $list_type;
			    my $match = 1;
			    
			    # resolve the clause number into an 
			    # AS path regexp, community regexp, etc.
			    
			
			    if ($match_type eq 'as-path') {
				$list_type = 'asp';
				print STDERR "resolving AS path $clause_num...\n" if $debug;
			    } elsif ($match_type eq 'community') {
				$list_type = 'com';
				print STDERR "resolving community-list $clause_num...\n" if $debug;
			    } else {
				$match = 0;
			    }


			    if ($match && defined($list{$list_type}->{$clause_num})) {
				
				printf STDERR "%s\n", &resolve_clausenum($list{$list_type}->{$clause_num}) if $debug;
				
				# append to the canonical rep
				$canonical .= "$list_type";
				$canonical .= &resolve_clausenum($list{$list_type}->{$clause_num});
				$canonical .= "::";
			    } else {

				if ($match) {
				    print "ERROR: undefined $list_type $clause_num ($router, $rm_name)\n";
				    $self->{parse_errors}->{$router}->{$rm_name}->{$def_types{$list_type}}->{$clause_num} = 1;
				}
			    }
			}
			
			# remove trailing delimiter
			$canonical =~ s/::$//;

		    } elsif ($line =~ /$set_regexp/) {
			# probably should do some stronger error check here
			
			my $attribute = $1;
			my $value = $2;

			my $action = sprintf("<%s => %s>", $attribute, $value);
			$canonical .= $action;
		    }

		} while ($line !~ /$eos/);

		# assign canonical rep to the route map name
		$rm_name_to_canonical{$rm_name} .= "!" if $deny;
		$rm_name_to_canonical{$rm_name} .= "{$canonical}";


	    } elsif ($_ =~ /$acl_regexp/) {
		# this is where we define access-list, community-list, etc.

		my $refnum = $+;

		my $exp = $';   # ' 
		&trim_regexp(\$exp);

		my $listtype;
		
		if ($_ =~ /$pfx_list_regexp/) {

		    # ip prefix-list
		    $listtype = 'pfx';

		    my ($name, $pd, $pfx, $mask) =
			($1, $2, $3, $4);
		    my ($mask_min, $mask_max) = (0,32);		    
		    # XXX need to allow for two boundary specs XXX
		    my ($rel, $rel_mask);


		    if ($_ =~ /\/\d+\s+(le|ge|eq)\s+(\d+)/) {
			($rel, $rel_mask) = ($1, $2);
		    }

		    my $permit = $pd eq 'permit';
		    my $ip_min = &inet_aton_($pfx);
		    my $add = 2**(32-$mask) - 1;
		    my $ip_max = $ip_min + $add;

		    if ($rel eq 'le') {
			$mask_min = $mask;
			$mask_max = $rel_mask;
		    } elsif ($rel eq 'ge') {
			$mask_min = $rel_mask;
		    } elsif ($rel eq 'eq') {
			$mask_min = $mask;
			$mask_max = $mask;
		    }

		    push(@{$prefix_acls->{$router}->{$name}},
			 "$ip_min:$ip_max:$permit:$mask_min:$mask_max");


		} elsif ($_ =~ /$ip_acc_list_regexp/) {

		    # XXX this must be fixed to actually parse these route maps
		    my $name = $2;
		    push(@{$prefix_acls->{$router}->{$name}},
			 "0:4294967296:0:0:32");

		} elsif ($_ =~ /$com_list_regexp/) {
		    $listtype = 'com';
		} elsif ($_ =~ /$acc_list_regexp/) {

		    # access-list

		    $listtype = 'acc';
		    
		    # do some more stuff in here
		    # so we can set up filters

		    if ($_ =~ /$acl_scope/) {
			my ($num, $pd, $pfx, $wc) = ($1,$2,$3,$5);
			my $hostaddr = ($4 =~ /host/);
			
			my $permit = $pd eq 'permit';
			my $ip_min = &inet_aton_($pfx);

			my $add = &inet_aton_($wc);
			if ($hostaddr) {
			    $add = $add^(0xffffffff);
			}
			my $ip_max = $ip_min + $add;
			
			push(@{$prefix_acls->{$router}->{$num}},
			     "$ip_min:$ip_max:$permit:0:32");
			
		    } elsif ($_ =~ /$acl_scope_default/) {

			my ($num, $pd, $pfx) = ($1,$2,$3);
			my $hostaddr = ($4 =~ /host/);
			
			my $permit = $pd eq 'permit';
			my $ip_min = &inet_aton_($pfx);
			my $ip_max = $ip_min;
			
			push(@{$prefix_acls->{$router}->{$num}},
			     "$ip_min:$ip_max:$permit:0:32");


		    } elsif ($_ =~ /access-list\s+(\d+)\s+(permit|deny)\s+(ip|tcp|udp)\s+any/) {
			# stupid cisco syntax: handle "any"

			my ($num, $pd) = ($1,$2);
			my $permit = $pd eq 'permit';

			push(@{$prefix_acls->{$router}->{$num}},
			     "0:4294967295:$permit:0:32");
		    }

		    
		} elsif ($_ =~ /$asp_list_regexp/) {
		    $listtype = 'asp';
		}

		push(@{$list{$listtype}->{$refnum}}, "$exp");
				
	    } elsif ($_ =~ /$ip_route_regexp/) {

		my ($network, $mask) = ($1, $2);
		push(@{$self->{routes}->{$router}}, "$network/$mask");

	    } else {
#		print "$_\n";
	    }

	    # XXX handle ip prefix-list here
	}

	# Now we have lb->import-map-names and route-map-names->canonical rep, so join them
	# 1. for this router get list of neighbors
	# 2. for each router, get the name of the route map
	# 3. look up the canonical representation for it
	
	my %acl_nums;

	foreach my $neighbor (@{$router_to_lbadj{$router}}) {

	    my $sid = $self->{session_id}->{$router}->{$neighbor};

	    ##############################
	    # sort out the prefix-lists and distribute-lists

	    my $acl_in_name = $neighbor_to_pfxacl_in_name{$neighbor};
	    my $acl_out_name = $neighbor_to_pfxacl_out_name{$neighbor};
	    

	    my $acl_in_canonical;
	    my $count = 0;

	    foreach my $acl_name ($acl_in_name, $acl_out_name) {

		my $key = 'import_acl';
		if ($count++ > 0) {$key = 'export_acl';}


		if (!defined($acl_name)) {
		    $self->{session_options}->{$sid}->{$key} = 0;
		} else {

		    if (defined($prefix_acls->{$router}->{$acl_name})) {
			my $acl = join(';',@{$prefix_acls->{$router}->{$acl_name}});
			
			if (!defined($canonical_acls{$acl})) {
			    $canonical_acls{$acl} = scalar(keys %canonical_acls) + 1;
			    $self->{canonical_acls}->{$canonical_acls{$acl}} = $acl;
			}
			
			$self->{session_options}->{$sid}->{$key} =
			    $canonical_acls{$acl};
			
		    } else {
			printf STDERR "ERROR: undefined prefix-list/distribute list $acl_name ($router, $neighbor)\n";
			my $ipnum = &inet_aton_($neighbor);
			$self->{parse_errors}->{$router}->{$acl_name}->{$def_types{'acl'}}->{$ipnum} = 1;
		    }
		}
	    
	    }



	    ##############################

	    my %rm_names = ();

	    if (!defined($rm_name_to_canonical{$neighbor_to_irm_name{$neighbor}}) &&
		!($neighbor_to_irm_name{$neighbor} eq '')) {
		printf STDERR "ERROR: undefined import route map, $router, $neighbor_to_irm_name{$neighbor}\n";
	    }
	    if (!defined($rm_name_to_canonical{$neighbor_to_orm_name{$neighbor}}) &&
		!($neighbor_to_orm_name{$neighbor} eq '')) {
		printf STDERR "ERROR: undefined import route map, $router, $neighbor_to_orm_name{$neighbor}\n";
	    }


	    my $import_rm = $rm_name_to_canonical{$neighbor_to_irm_name{$neighbor}};
	    my $export_rm = $rm_name_to_canonical{$neighbor_to_orm_name{$neighbor}};

	    $rm_names{$import_rm} = $neighbor_to_irm_name{$neighbor};
	    $rm_names{$export_rm} = $neighbor_to_orm_name{$neighbor};


	    # Do a canonical number thingy here
	    foreach my $rm (($import_rm, $export_rm)) {

		my $rm_name = $rm_names{$rm};

		if (!defined($canonical_rms{$rm})) {
		    $canonical_rms{$rm} = scalar(keys %canonical_rms) + 1;

		    # construct the reverse mapping (number to pattern)
		    # and store this in the object so we can look it up later
		    $self->{canonical_rms}->{$canonical_rms{$rm}} = $rm;
		}

		foreach my $clause_num (keys %{$pfx_acls_in_rm{$router}->{$rm_name}}) {

		    # the ACLs that are defined in this route map
		    my $acl_name = $pfx_acls_in_rm{$router}->{$rm_name}->{$clause_num};

		    # handle undefined route maps
		    next if (!defined($prefix_acls->{$router}->{$acl_name}));


		    my $acl = join(';',
				   @{$prefix_acls->{$router}->{$acl_name}});
		    
		    if (!defined($canonical_acls{$acl})) {
			$canonical_acls{$acl} = scalar(keys %canonical_acls) + 1;
			$self->{canonical_acls}->{$canonical_acls{$acl}} = $acl;
		    }
			

		    $self->{prefix_filters_rm}->{$canonical_rms{$rm}}->{$clause_num} =
			$canonical_acls{$acl};

		}
		
	    }

	    # these assign route map NUMBERS to (router, neighbor) tuples
	    $router_to_irm_canonical{$router}->{$neighbor} = $canonical_rms{$import_rm};
	    $router_to_orm_canonical{$router}->{$neighbor} = $canonical_rms{$export_rm};

	    $self->{session_options}->{$sid}->{import_rm} =
		$canonical_rms{$import_rm};

	    $self->{session_options}->{$sid}->{export_rm} =
		$canonical_rms{$export_rm};



	}

	close(RFILE);
    }

    # now we have the router names to IP address mappings, so we can
    # now map routers to routers

    # this does the import/export route maps according to router name
    # should nix eBGP sessions from this warning message

    if (0) {
	foreach my $router (@{$self->{nodes}}) {
	    foreach my $lb (@{$router_to_lbadj{$router}}) {
		
		my $router_name = $lb;
		if (defined($self->{loopback_to_name}->{$lb})) {
		    $router_name = $self->{loopback_to_name}->{$lb};
		} else {
		    printf "ERROR: No Router with Loopback $lb\n";
		}
		
		push(@{$self->{node_edges}->{$router}}, $router_name);
		
		$self->{import_rm}->{$router}->{$router_name} = $router_to_irm_canonical{$router}->{$lb};
		$self->{export_rm}->{$router}->{$router_name} = $router_to_orm_canonical{$router}->{$lb};
	    }
	}
    }

}

######################################################################
# printing functions (all to STDOUT)

sub print_route_maps_for_all_routers {
    my $self = shift;
    
    foreach my $router (@{$self->{nodes}}) {

	for (my $i=0;$i<60;$i++) {print "*";}
	print "\n$router Import\n";
	my $rhash = $self->get_route_maps_for_router($router,1);
	foreach my $nbr (keys %$rhash) {
	    printf "%s: %d\n", $nbr, $rhash->{$nbr};
	}

	print "\n$router Export\n";
	$rhash = $self->get_route_maps_for_router($router,0);
	foreach my $nbr (keys %$rhash) {
	    printf "%s: %d\n", $nbr, $rhash->{$nbr};
	}

    }
}


sub print_all_canonical_route_maps {
    my $self = shift;

    foreach my $num (sort {$a <=> $b} keys %{$self->{canonical_rms}}) {
	printf "%d: %s\n", $num, $self->get_canonical_route_map($num);
    }

}


######################################################################
# individual operations
# fetch individual route maps, info about individual routers, etc.

sub get_route_maps_for_router {

    # return hash only (f: nbr -> route_map number)

    my $self  = shift;
    my ($router, $import_) = @_;

    my %nbr_to_rm = ();
    my $hash = ($import_)?$self->{import_rm}:$self->{export_rm};

    if (defined($self->{node_edges}->{$router})) {
	my @neighbors = @{$self->{node_edges}->{$router}};

	foreach my $nbr (@neighbors) {
	    $nbr_to_rm{$nbr} = $hash->{$router}->{$nbr};
	}

    } else {
	print "WARNING: $router has no BGP sessions/Route Maps\n";
    }

    return \%nbr_to_rm;
}

######################################################################

# retrieve the canonical route map representation for a
# canonical route map number
sub get_canonical_route_map {
    my $self = shift;
    my ($rm_number) = @_;
    
    return $self->{canonical_rms}->{$rm_number};
}


sub get_canonical_acl {
    my $self = shift;
    my ($acl_number) = @_;
    
    return $self->{canonical_acls}->{$acl_number};
}


######################################################################

sub get_all_routers {
    my $self = shift;
    return $self->{nodes};
}

sub get_all_route_maps {
    my $self = shift;
    return $self->{canonical_rms};
}

sub get_sessions_for_router {
    my $self = shift;
    my ($router) = @_;
    my @ids;
    
    foreach my $nbr (keys %{$self->{session_id}->{$router}}) {
	push(@ids, $self->{session_id}->{$router}->{$nbr});
    }

    return \@ids;
}

# retrieve loopback address for a given router name
sub get_loopbacks_for_router {
    my $self = shift;
    my ($router) = @_;
    return $self->{name_to_loopbacks}->{$router};
}

sub get_global_for_router {
    my $self = shift;
    my ($router, $option) = @_;
    
    if (!defined($self->{router_options}->{$router}->{$option})) {
	$self->{router_options}->{$router}->{$option} = 0;
    }

    return $self->{router_options}->{$router}->{$option};
}


######################################################################

sub clean_db {
    my $self = shift;
    foreach my $table (@db_tables) {
	$self->{dbh}->do("delete from $table");
    }
}

sub db_parse_errors {
    my $self = shift;

    foreach my $router (keys %{$self->{parse_errors}}) {
	foreach my $rm_name (keys %{$self->{parse_errors}->{$router}}) {
	    foreach my $def_type (keys %{$self->{parse_errors}->{$router}->{$rm_name}}) {
		foreach my $def_num (keys %{$self->{parse_errors}->{$router}->{$rm_name}->{$def_type}}) {
		    my $cmd = "insert into $parse_errors values ('$router', '$rm_name', '$def_type', '$def_num')";
		    $self->{dbh}->do($cmd);
		}
	    }
	}
    }
}


sub db_interfaces_for_router {
    my $self = shift;
    my ($router) = @_;

    foreach my $intn (keys %{$self->{interfaces}->{$router}}) {
	foreach my $intf (@{$self->{interfaces}->{$router}->{$intn}}) {
	    my ($ip, $mask) = split('/', $intf);
	    my $ip_num = &inet_aton_($ip);
	    my $mask_num = &inet_aton_($mask);
	    
	    my $min_ip = $ip_num & $mask_num;
#	my $max_ip = $ip_num | ($mask_num ^ (2^32-1));
	    
	    my $cmd = "insert into $interfaces values ('$router', '$intn', '$ip_num', '$min_ip', '$mask_num')";
	    $self->{dbh}->do($cmd);
	}

    }

}

sub db_routes_for_router {
    my $self = shift;
    my ($router) = @_;
    
    foreach my $rt (@{$self->{routes}->{$router}}) {
	my ($network, $mask) = split('/', $rt);
	my $nw_num = &inet_aton_($network);
	my $mask_num = &inet_aton_($mask);
	
	my $cmd = "insert into $routes values ('$router', '$nw_num', '$mask_num')";
	$self->{dbh}->do($cmd);
    }
}

sub db_networks_for_router {
    my $self = shift;
    my ($router) = @_;
    
    foreach my $rt (@{$self->{networks}->{$router}}) {
	my ($network, $mask) = split('/', $rt);

	my $nw_num = &inet_aton_($network);
	my $mask_num = &inet_aton_($mask);
	
	# XXX should insert the route map here, too
	my $cmd = "insert into $networks values ('$router', '$nw_num', '$mask_num', '0')";
	$self->{dbh}->do($cmd);
    }
}

sub db_sessions_for_router {
    my $self = shift;
    my ($router) = @_;

    my $sids = $self->get_sessions_for_router($router);
    foreach my $id (@$sids) {
	my $cmd = "insert into $router_sessions values ('$router', '$id')";
	$self->{dbh}->do($cmd);
    }
}

sub print_loopbacks_for_router {
    my $self = shift;
    my ($router) = @_;

    my $rlbs = $self->get_loopbacks_for_router($router);

    foreach my $lb (@$rlbs) {
	printf ("%s\tloopback\t%s\n", $router, $lb);
    }
}

sub db_loopbacks_for_router {
    my $self = shift;
    my ($router) = @_;

    my $rlbs = $self->get_loopbacks_for_router($router);

    foreach my $lb (@$rlbs) {
	my $lbnum = unpack("N", pack("C4", split(/\./,$lb)));
	my $cmd = "insert into $router_loopbacks values ('$router', '$lbnum')";
	$self->{dbh}->do($cmd);
    }

}

sub print_global_for_router {
    my $self = shift;
    my ($router) = @_;

    foreach my $option (@{$self->{global_options}}) {
	printf ("%s\t%s\t%s\n",
		$router, $option,
		$self->get_global_for_router($router, $option));

    }
}


sub db_global_for_router {
    my $self = shift;
    my ($router) = @_;


    # get the global options for router
    my $bgp = $self->get_global_for_router($router, 'runs_bgp');
    my $asn = $self->get_global_for_router($router, 'asn');
    my $no_sync = $self->get_global_for_router($router, 'no_synchronization');
    my $dm = $self->get_global_for_router($router, 'deterministic-med');
    my $compare_rid = $self->get_global_for_router($router, 'compare-routerid');
    my $rid = $self->get_global_for_router($router, 'router-id');
    my $cid = $self->get_global_for_router($router, 'cluster-id');

    my $ridnum = unpack("N", pack("C4", split(/\./,$rid)));

    my $cmd = "insert into $router_global values ('$router','0','$bgp','$asn','$no_sync', '$dm','$compare_rid','$ridnum','$cid')";
    $self->{dbh}->do($cmd);

}


sub print_session_info_for_router {
    my $self = shift;
    my ($router) = @_;
    
    foreach my $nbr (keys %{$self->{session_id}->{$router}}) {
	my $nbr_str = $nbr;
	$nbr_str =~ s/\@//g;

	my $sid = $self->{session_id}->{$router}->{$nbr};

	my $asn = $self->{session_options}->{$sid}->{asnum};
	my $ebgp = $self->{session_options}->{$sid}->{ebgp};
	my $nhs = $self->{session_options}->{$sid}->{nh_self};

	my $rrc = $self->{session_options}->{$sid}->{rr_client};

	my $irm = $self->{session_options}->{$sid}->{import_rm};
	my $erm = $self->{session_options}->{$sid}->{export_rm};


	my $iacl = $self->{session_options}->{$sid}->{import_acl};
	my $eacl = $self->{session_options}->{$sid}->{export_acl};

	my $shutdown = $self->{session_options}->{$sid}->{shutdown};

	printf ("%s\tneighbor\t%d\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n",
		$router, $sid, $nbr_str, $rrc, $asn, $ebgp, $nhs, $irm, $erm, $iacl, $eacl);
    }
    
}

sub db_session_info_for_router {
    my $self = shift;
    my ($router) = @_;

    $self->db_get_rmap_id_base();

    foreach my $nbr (keys %{$self->{session_id}->{$router}}) {
	my $nbrnum = unpack("N", pack("C4", split(/\./,$nbr)));

	my $sid = $self->{session_id}->{$router}->{$nbr};

	my $asn = $self->{session_options}->{$sid}->{asnum};
	my $ebgp = $self->{session_options}->{$sid}->{ebgp};
	my $nhs = $self->{session_options}->{$sid}->{nh_self};
	
	my $sc = $self->{session_options}->{$sid}->{send_community};
	my $rp = $self->{session_options}->{$sid}->{remove_private};

	my $rrc = $self->{session_options}->{$sid}->{rr_client};

	my $irm = $self->{session_options}->{$sid}->{import_rm} + $self->{rmap_id_base};
	my $erm = $self->{session_options}->{$sid}->{export_rm} + $self->{rmap_id_base};

	my $iacl = $self->{session_options}->{$sid}->{import_acl} + $self->{acl_id_base};
	my $eacl = $self->{session_options}->{$sid}->{export_acl} + $self->{acl_id_base};


	my $shutdown = $self->{session_options}->{$sid}->{shutdown};

	# assume iBGP sessions are down until we verify otherwise
	my $up = $ebgp;

	# these are global, but we need them for juniper compatibility,
	# where these options are session-specific

	my $cid = $self->get_global_for_router($router, 'cluster-id');
	my $loc_as = $self->get_global_for_router($router, 'asn');



	my $values = sprintf ("('%s','%d','%lu','%d','%d','%d','%d','%d','%d','%d','%d','%d','%d','%d','%d','%d')\n",
			      $router, $sid, $nbrnum, $rrc, $loc_as, $asn,
			      $irm, $erm, $iacl, $eacl, $ebgp, $cid,
			      $nhs, $sc, $rp, $up);

	# insert into the normal sessions table, unless it is shutdown:
	# in that case, insert into sessions_shutdown table
	my $cmd = "insert into $sessions values $values";
	if ($shutdown) {
	    $cmd = "insert into $sessions_shutdown values $values";
	}

	$self->{dbh}->do($cmd); 

    }
    
}


sub print_route_map_tabular {
    my $self = shift;
    my ($rmid) = @_;

    my $rmstr = $self->get_canonical_route_map($rmid);
    my @rm_clauses = split(/\}/, $rmstr);
    my $clause_num = 0;

    my $value_str;

    foreach my $clause (@rm_clauses) {

	$clause_num++;

	my $permit = 1;
	$permit = 0 if ($clause =~ /^\!/);

	$clause =~ s/[\{\!]//g;

	my ($as_regexp, $comm_regexp, $pfx, $mask);
	my ($localpref, $med, $origin, $community, $prepend);

	# XXX need to fix this so that it handles multiple clauses
	my $match = $clause;
	if ( $clause =~ /(.*)\</ ) {
	    $match = $1;
	}

	if ( $match =~ /([a-z]+)\((.*?)\)(.*)/ ) {
	    my $type = $1;

	    while ( $match =~ /\((.*?)\)(.*)/ ) {

		my $expression = $1;
		my $rest = $2;
		
		if ($type eq 'asp') {
		    $as_regexp .= sprintf "%s|", $expression;
		}
		
		if ($type eq 'com') {
		    $comm_regexp .= sprintf "%s|", $expression;
		}
		
		$match = $rest;
	    }
	}
	$as_regexp =~ s/\|$//;
	$comm_regexp =~ s/\|$//;


	my $sets = $clause;
	while ( $sets =~ /\<\s*(\S+)\s+\=\>\s+(.*?)\>(.*)/) {
	    my $attribute = $1;
	    my $value = $2;
	    my $rest = $3;

	    if ($attribute =~ /local-preference/) {
		$localpref = $value;
	    } 

	    if ($attribute =~ /community/) {
		$community = $value;
	    } 

	    if ($attribute =~ /as-path/) {

		# handle prepending
		if ($value =~ /prepend\s+(.*)/) {
		    $prepend = $1;
		}
	    } 
	    
	    $sets = $rest;
	}

	# need this for juniper compatibility
	# in cisco, this is set as a global option
	# for the router
	my $nh_self = 0;

	my $aclnum = $self->{prefix_filters_rm}->{$rmid}->{$clause_num};

	my $values = sprintf ("('%d','%d','%d','%d','%s','%s','%d','%d','%d','%s','%s','%d')\n",
			      $rmid, $clause_num, $aclnum, $permit,
			      $as_regexp, $comm_regexp,
			      $localpref, $med, $origin, $community, $prepend,
			      $nh_self);
	
	$value_str .= "$values";

    }
    return $value_str;

}


sub db_route_map {
    my $self = shift;
    my ($rmid) = @_;

    $self->db_get_rmap_id_base();
    $self->db_get_acl_id_base();

    my $value_str = $self->print_route_map_tabular($rmid);

    foreach my $values (split("\n", $value_str)) {

	my @varr = split(',',$values);
	
	# increment the route map id
	if ($varr[0] =~ /(\d+)/) {
	    my $rmid = $1;
	    $rmid += $self->{rmap_id_base};
	    $varr[0] = sprintf("('%d'", $rmid);
	}


	# increment the acl id
	if ($varr[2] =~ /(\d+)/) {
	    my $aclid = $1;
	    $aclid += $self->{acl_id_base};
	    $varr[2] = sprintf("'%d'", $aclid);
	}



	my $as_regexp = $varr[4];
	my $comm_regexp = $varr[5];
	my $community = $varr[9];


	############################################################
	# separate into tables to save space, etc.
	# 1. as path regexp
	# 2. community regexp
	# 3. set community value
	
	if (!($as_regexp eq '\'\'') && !($as_regexp eq '')) {
	    my $q = "select as_regexp_num from $as_regexps where as_regexp=$as_regexp";
	    my $sth = $self->{dbh}->prepare($q);
	    $sth->execute;
	    my ($asrnum) = $sth->fetchrow_array();
	    
	    if (!$asrnum) {
		my $q = "select max(as_regexp_num) from $as_regexps";
		my $sth = $self->{dbh}->prepare($q);
		$sth->execute;
		my ($max_asrnum) = $sth->fetchrow_array();
		$asrnum = $max_asrnum + 1;

		my $cmd = "insert into $as_regexps values('$asrnum',$as_regexp)";
		$self->{dbh}->do($cmd);
	    }
	    
	    $varr[4] = "\'$asrnum\'";
	    
	}

	if (!($comm_regexp eq '\'\'') && !($comm_regexp eq '')) {
	    my $q = "select comm_regexp_num from $comm_regexps where comm_regexp=$comm_regexp";
	    my $sth = $self->{dbh}->prepare($q);
	    $sth->execute;
	    my ($commrnum) = $sth->fetchrow_array();
	    
	    if (!$commrnum) {
		my $q = "select max(comm_regexp_num) from $comm_regexps";
		my $sth = $self->{dbh}->prepare($q);
		$sth->execute;
		my ($max_commrnum) = $sth->fetchrow_array();
		$commrnum = $max_commrnum + 1;

		my $cmd = "insert into $comm_regexps values('$commrnum',$comm_regexp)";
		$self->{dbh}->do($cmd);
	    }
	    
	    $varr[5] = "\'$commrnum\'";
	    
	}


	if (!($community eq '\'\'') && !($community eq '')) {
	    my $q = "select community_num from $comm where community=$community";
	    my $sth = $self->{dbh}->prepare($q);
	    $sth->execute;
	    my ($commnum) = $sth->fetchrow_array();
	    
	    if (!$commnum) {
		my $q = "select max(community_num) from $comm";
		my $sth = $self->{dbh}->prepare($q);
		$sth->execute;
		my ($max_commnum) = $sth->fetchrow_array();
		$commnum = $max_commnum + 1;

		my $cmd = "insert into $comm values('$commnum',$community)";
		$self->{dbh}->do($cmd);
	    }
	    
	    $varr[9] = "\'$commnum\'";
	    
	}




	$values = join(',', @varr);
	my $cmd =  "insert into $route_maps values $values";
	$self->{dbh}->do($cmd);
    }


}

sub db_prefix_acls {

    my $self = shift;
    my $router = shift;

    $self->db_get_acl_id_base();
    
    foreach my $num (keys %{$self->{canonical_acls}}) {

	my $canonical_acl = $self->{canonical_acls}->{$num};
	my $clause_num = 1;

	foreach my $str (split(';',$canonical_acl)) {
	    my ($ip_min, $ip_max, $permit, $mask_min, $mask_max) = split(':',$str);
	    
	    my $cmd = sprintf("insert into $prefix_acls values ('%d','%d','%lu','%lu','%d','%d','%d')",
			      $num+$self->{acl_id_base},
			      #$num,
			      $clause_num++,$ip_min,
			      $ip_max,$mask_min,$mask_max,$permit);
	    $self->{dbh}->do($cmd);
	}
	
    }
}



sub resolve_clausenum {
    my ($arr_ref, $type) = @_;
    my @exparr = @$arr_ref;

    my $exp = join('::', @exparr);
    if ($type eq 'acc') {
	$exp =~ s/\@//g;
    }

    return $exp;
}


sub db_get_rmap_id_base {
    my $self = shift;
    

    if (!defined($self->{rmap_id_base})) {
	my $q = "select max(rmap_id) from route_maps";
	my $sth = $self->{dbh}->prepare($q);
	$sth->execute;
	my ($x) = $sth->fetchrow_array();
	$self->{rmap_id_base} = $x;

	if (!($self->{rmap_id_base}>0)) {
	    $self->{rmap_id_base} = 0;
	} else {
	    $self->{rmap_id_base}++;
	}

    }
    return $self->{rmap_id_base};
}


sub db_get_acl_id_base {
    my $self = shift;
    

    if (!defined($self->{acl_id_base})) {
	my $q = "select max(num) from prefix_acls";
	my $sth = $self->{dbh}->prepare($q);
	$sth->execute;
	my ($x) = $sth->fetchrow_array();
	$self->{acl_id_base} = $x;

	if (!($self->{acl_id_base}>0)) {
	    $self->{acl_id_base} = 0;
	} else {
	    $self->{acl_id_base}++;
	}

    }
    return $self->{acl_id_base};
}




1;
