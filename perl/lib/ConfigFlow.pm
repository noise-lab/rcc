#!/usr/bin/perl

package ConfigFlow;

use Data::Dumper;
use strict;

use CiscoTypes;
use ConfigCommon;
use ConfigParse;
use ConfigDB;

require Exporter;
use vars(qw(@ISA @EXPORT $configdir));
@ISA = ('Exporter');

######################################################################

$configdir =  sprintf("%s/trans", $config_basedir);


######################################################################
# Constructor

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);

    $self->{nodes};          # array of router names
    $self->{node_edges};     # router_name => adjacency list (router names)
    $self->{route_maps};     # router_name => list of maps

    $self->{name_to_loopback};  # router_name => loopback IP address
    $self->{loopback_to_name};  # loopback IP address => router_name

    $self->{has_ebgp};       # has_ebgp{router} => yes/no
    $self->{import_fn};      # import{router}->{nei_lb} => canonical rep
    $self->{export_fn};      # export{router}->{nei_lb} => canonical rep
    
    $self->{canonical_rms};  # map canonical number to pattern
    $self->{my_asn};

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

    my %router_to_lbadj = ();

    # eventually, we construct f: (router, neighbor_addr) -> canonical route map
    my %router_to_irm_canonical = ();
    my %router_to_orm_canonical = ();

    my %canonical_rms = ();

	
    my %ebgp_loopbacks = ();
    my %ebgp_rtr_ctr = ();

    foreach my $router (@{$self->{nodes}}) {

	my $rfilenames = &router_to_config($router);
	my $rfilename = @$rfilenames[0];

	print STDERR "$rfilename\n";# if $debug;

	open (RFILE, "$rfilename") || die "can't open $rfilename: $!\n";

	# router-specific stuff
	my %list = ();
	my %neighbor_to_irm_name = ();
	my %neighbor_to_orm_name = ();
	my %rm_name_to_canonical = ();

	while (<RFILE>) {
	    chomp;
	    my $lb;

	    if ($_ =~ /$loopback_regexp/){
		my $line = "";
		do {
		    $line = <RFILE>;
		} while ($line !~ /ip\s+address\s+\@(\d+\.\d+\.\d+\.\d+)\@/ && $line);

		#last if (!$line);
		$lb = $1;
		print "$router has loopback $lb\n" if ($debug > 1);
		$self->{name_to_loopback}->{$router} = $lb;
		$self->{loopback_to_name}->{$lb} = $router;
	    } elsif ($_=~ /$bgp_scope/) {

		# figure out:
		# 1. BGP adjacencies
		# 2. route maps applied to those adjacencies

		my $this_asnum = $1;
		$self->{my_asn} = $this_asnum;

		my $line = "";
		do {
		    $line = <RFILE>;
		    chomp($line);
		    
		    my $ibgp=0;

		    if ($line =~ /neighbor\s+($addr_mask)\s+remote-as\s+(\d+)/) {
			my $adjacency = $1;
			my $asnum = $2;

			$ibgp = ($asnum == $this_asnum);

			$adjacency =~ s/\@//g;
			push(@{$router_to_lbadj{$router}}, $adjacency);
			print STDERR "$router: $adjacency\n" if ($debug > 1);

			if (!$ibgp && !defined($self->{loopback_to_name}->{$adjacency})) {
			    
			    # note that this router has at least one eBGP session
			    $self->{has_ebgp}->{$router} = 1;

                            # we won't resolve this loopback, so give this external node a
			    # unique name
			    
			    # need a unique increment
			    # should be common across routers
			    # remove router name from name, and keep track of loopback


			    my $ebgp_router_name;
			    if (!defined($ebgp_loopbacks{$adjacency})) {
				my $ebgp_router_name_tmp = sprintf ("ebgp_AS%d", $asnum);
				$ebgp_router_name = sprintf ("%s_%d", $ebgp_router_name_tmp,
								$ebgp_rtr_ctr{$ebgp_router_name_tmp}++);

				$ebgp_loopbacks{$adjacency} = $ebgp_router_name;;
			    } else {
				$ebgp_router_name = $ebgp_loopbacks{$adjacency};
			    }
				
			    
			    $self->{loopback_to_name}->{$adjacency} = $ebgp_router_name;

			}

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

		} while ($line !~ /$eos/);
		
	    } elsif ($_ =~ /$rm_scope/) {
		# resolve route maps into a canonical rep

		my $rm_name = $1;
		my $line = "";

		# assemble the canonical rep for the route map in this var
		my $canonical = "";

		# is this a deny clause?
		my $deny = ($_ =~ /deny/);
		
		do {
		    $line = <RFILE>;
		    chomp($line);

		    if ($line =~ /$match_ip_regexp/) {
			my $clause_nums = $1;
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
				print "ERROR: undefined $list_type $clause_num ($router)\n";
			    }
				
			}

			# remove trailing delimiter
			$canonical =~ s/::$//;

		    } elsif ($line =~ /$match_regexp/) {
			my $match_type = $1;
			my $clause_nums = $2;

			my @clause_num_arr = split(/\s+/, $clause_nums);
#			my $clause_num = @clause_num_arr[0];

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
				print "ERROR: undefined $list_type $clause_num ($router)\n" if $match;
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
		    $listtype = 'pfx';
		} elsif ($_ =~ /$com_list_regexp/) {
		    $listtype = 'com';
		} elsif ($_ =~ /$acc_list_regexp/) {
		    $listtype = 'acc';
		} elsif ($_ =~ /$asp_list_regexp/) {
		    $listtype = 'asp';
		}

		push(@{$list{$listtype}->{$refnum}}, "$exp");
				
	    } 

	    # XXX handle ip prefix-list here
	}

	# XXX, derive:
	# 1. router->imported(neighbor, pfx,aspath) => yes or no
	# 2. router->lbadj->(lp,med,origin,community)
	# 3. router->exported(neighbor, pfx, aspath) => yes or no
	# (1 and 3 are basically closures)

	# Now we have lb->import-map-names and route-map-names->canonical rep, so join them
	# 1. for this router get list of neighbors
	# 2. for each router, get the name of the route map
	# 3. look up the canonical representation for it
	
	foreach my $neighbor (@{$router_to_lbadj{$router}}) {
	    my $import_rm = $rm_name_to_canonical{$neighbor_to_irm_name{$neighbor}};
	    my $export_rm = $rm_name_to_canonical{$neighbor_to_orm_name{$neighbor}};


	    # Do a canonical number thingy here
	    foreach my $rm (($import_rm, $export_rm)) {
		if (!defined($canonical_rms{$rm})) {
		    $canonical_rms{$rm} = scalar(keys %canonical_rms) + 1;

		    # construct the reverse mapping (number to pattern)
		    # and store this in the object so we can look it up later
		    $self->{canonical_rms}->{$canonical_rms{$rm}} = $rm;

		}
	    }

	    $router_to_irm_canonical{$router}->{$neighbor} = $canonical_rms{$import_rm};
	    $router_to_orm_canonical{$router}->{$neighbor} = $canonical_rms{$export_rm};

#	    print STDERR "$router->$neighbor\nIMPORT: $import_rm\nEXPORT($neighbor_to_orm_name{$neighbor}): $export_rm\n";
	}

	close(RFILE);
    }

    # now we have the router names to IP address mappings, so we can
    # now map routers to routers

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

#    print Dumper(%canonical_rms);

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

sub print_loopbacks_for_all_routers {
    my $self = shift;
    
    foreach my $router (@{$self->{nodes}}) {
	printf "%s: %s\n", $router, $self->get_loopback_for_router($router);
    }
}

sub print_all_canonical_route_maps {
    my $self = shift;

    foreach my $num (sort {$a <=> $b} keys %{$self->{canonical_rms}}) {
	printf "%d: %s\n", $num, $self->get_canonical_route_map($num);
    }

}


######################################################################
# graphing functions

sub print_flow_graph {
    my $self = shift;
    my ($options) = @_;

    my ($output, $min_degree, $ebgpopt, $rmopt) = split(',', $options);
    my $rnodes_;
    my %nodes;


    if (defined($min_degree)) {

	    # define nodes based on minimum degree ($min_degree should be int)

	foreach my $router (@{$self->{nodes}}) {
	
	    if ($ebgpopt eq 'ebgp') {
		# do ebgp-speaking routers only
		# skip anything that has no edges
		next if (!defined($self->{has_ebgp}->{$router}));
	    }
	
	    # skip anything that has no edges
	    next if (!defined($self->{node_edges}->{$router}));
	    
	    my $degree = scalar(@{$self->{node_edges}->{$router}});
	    if ($degree >= $min_degree) {
		$nodes{$router} = 1;
	    }
	
	    
	}

	my @rnodes = keys %nodes;
	$rnodes_ = \@rnodes;

    } else {
	$rnodes_ = \@{$self->{nodes}};
    }


    print STDERR "printing flow graph...\n";

    my $exec_dot = ($output eq 'eps');
    my $write_dot = ($exec_dot || $output eq 'dot');
    my $dotfile;

    if ($exec_dot || $write_dot) {
	$dotfile = "$tmpdir/flowgraph.dot";
	print STDERR "Writing dotfile: $dotfile\n";
	open(DOT, ">$dotfile") || die "Can't open $dotfile: $!\n";
	select(DOT);
    }

    print "digraph flowgraph {\n";
    foreach my $router (@$rnodes_) {
	
	print "\"$router\" $nodestyle\n";

	my $export = $rmopt eq 'export';

	# import OR export route maps/sessions
	my $rhash = $self->get_route_maps_for_router($router,!$export);
	foreach my $nbr (keys %$rhash) {

	    my ($from, $to);
	    if ($export) {
		$from = $router;
		$to = $nbr;
	    } else {
		$from = $nbr;
		$to = $router;
	    }

	    my $print_neighbor = (!defined($min_degree) || defined($nodes{$nbr}) ||
				  ($ebgpopt eq 'ebgp' && $nbr =~ /ebgp/));


	    if ($print_neighbor) { 
		printf "\"%s\" -> \"%s\" [label=%d]\n", $from, $to, $rhash->{$nbr};
	    }
	}

    }
    

    print "}\n";

    if ($exec_dot) {
	my $epsfile = $dotfile;
	$epsfile =~ s/\.dot/\.eps/;
	system("$dot -Tps $dotfile > $epsfile");
    }

    if ($exec_dot || $write_dot) {
	close(DOT);
    }

}


######################################################################
# database operations
# insert the graph representation into the database
# XXX passing the entire object is busted;  fix this.

sub populate_loopback_db {
    my $self = shift;
    &populate_loopback_($self);

}

sub populate_session_db {
    my $self = shift;
    &populate_session_($self);
}


sub populate_route_map_db {
    my $self = shift;
    &populate_route_map_($self);

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


# retrieve the canonical route map representation for a
# canonical route map number
sub get_canonical_route_map {
    my $self = shift;
    my ($rm_number) = @_;
    
    return $self->{canonical_rms}->{$rm_number};
}

# retrieve loopback address for a given router name
sub get_loopback_for_router {
    my $self = shift;
    my ($router) = @_;

    return $self->{name_to_loopback}->{$router};
}




######################################################################

# trim regexps as specified in access-lists, etc.
# so they are suitable perl regexps
# XXX move to ConfigParse.pm
sub trim_regexp {
    my $rexp = shift;
    my $deny = 0;

    $$rexp =~ s/^\s+//;
    $$rexp =~ s/\s+$//;
    $$rexp =~ s/permit\s+//;
    
    if ($$rexp =~ /deny/) {
	$$rexp =~ s/deny\s+//;
	$deny = 1;
    }

    $$rexp =~ s/^\_(\d+)\_$/\^$1\$| $1 |\^$1 | $1\$/g;
    $$rexp =~ s/^\_([\$\d]+)/\^$1| $1/g;
    $$rexp =~ s/([\^\d]+)\_$/$1 |$1\$/g;
    $$rexp =~ s/\_/ /g;

    $$rexp = sprintf("(%s)", $$rexp);

    if ($deny) {
	$$rexp = sprintf("!%s", $$rexp);
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

1;
