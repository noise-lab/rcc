#!/usr/bin/perl

package ConfigIF_Juniper;

use Data::Dumper;
use strict;

use JuniperTypes;
use ConfigCommon;
use ConfigParse;
use ConfigDB;

require Exporter;
use vars(qw(@ISA @EXPORT $configdir @db_tables));
@ISA = ('Exporter');

my $debug = 0;

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

    $self->{router_options};  # global router options
    $self->{session_options}; # get the options for some session ID #
    $self->{session_id};      # get the session ID # for some (router, neighbor) tuple

    $self->{name_to_loopbacks};  # router_name => loopback IP address
    $self->{loopback_to_name};  # loopback IP address => router_name

    $self->{has_ebgp};       # has_ebgp{router} => yes/no
    $self->{import_fn};      # import{router}->{nei_lb} => canonical rep
    $self->{export_fn};      # export{router}->{nei_lb} => canonical rep
    
#    $self->{meta_canonical_rms} # map canonical number to list of canonical numbers
    $self->{canonical_rms};     # map canonical number to pattern
    $self->{my_asn};

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
    my @rfiles = <$configdir/*-jconfg>;

    foreach my $rfile (@rfiles) {
	if ($rfile =~ /^.*\/($rtr_name)-jconfg/){
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
    my $session_id = 0;

    my %router_to_lbadj = ();

    my %canonical_rms = ();

    # JEEZ.  Juniper allows definition of multiple
    # import/export policies for a single session!
    my %meta_canonical_rms = ();
    my %rm_name_to_canonical = ();

    # (router_name, rm_name) => canonical num
    my %rm_name_to_rm_num = ();

    # (router_name, rm_name) => next-hop-self?
    my %rm_name_to_nhself = ();

    # session => import_rm, etc.
    my %session_to_irm = ();
    my %session_to_orm = ();
    my %session_to_nhself = ();

    
	
    foreach my $router (@{$self->{nodes}}) {

	my $rfilenames = &router_to_config($router, 1);
	my $rfilename = @$rfilenames[0];

	print STDERR "ConfigIF_Juniper: Looking at $rfilename\n";
	open (RFILE, "$rfilename") || die "can't open $rfilename: $!\n";

	# router-specific stuff

	my %session_to_irm_name = ();
	my %session_to_orm_name = ();

	my %unresolved_rm_from = ();
	my %unresolved_rm_then = ();
	

	my %community_defn;
	my %aspath_defn;

	while (<RFILE>) {
	    chomp;


	    # checking interfaces for loopback definition
	    if ($_ =~ /^interfaces\s+\{/) {
		print STDERR "parsing interfaces..." if $debug;;
		my $scope=1;
		
		do {
		    my $line = <RFILE>;
		    $self->check_scope($line, \$scope);

		    if ($line =~ /lo0/) {
			my $lb_scope = 1;

			do {
			    my $lb_line = <RFILE>;
			    $self->check_scope($lb_line, \$scope);
			    $self->check_scope($lb_line, \$lb_scope);



			    if ($lb_line =~ /unit\s+0/) {
				my $unit_scope = 1;

				do {
				    my $unit_line = <RFILE>;
				    $self->check_scope($unit_line, \$scope);
				    $self->check_scope($unit_line, \$lb_scope);
				    $self->check_scope($unit_line, \$unit_scope);

				    if ($unit_line =~ /family\s+inet/) {
					my $inet_scope = 1;
					
					do {
					    my $inet_line = <RFILE>;
					    $self->check_scope($inet_line, \$scope);
					    $self->check_scope($inet_line, \$lb_scope);
					    $self->check_scope($inet_line, \$unit_scope);
					    $self->check_scope($inet_line, \$inet_scope);

					    if ($inet_line =~ /address\s+($addr)\/32/) {
						my $lb = $1;
						push(@{$self->{name_to_loopbacks}->{$router}}, $lb);
						$self->{loopback_to_name}->{$lb} = $router;

					    }
					} while ($inet_scope);
				    }
				} while ($unit_scope);
			    }
			} while ($lb_scope);

		    }
		    elsif ($line =~ /(.*)\{/) {
				my $main_int = $1;	
				$main_int =~ s/\s//g;    #remove space from main_int

				print STDERR "Got $main_int\n" if $debug>1;
				
				my $main_int_scope = 1;
				do {
					my $main_int_line = <RFILE>;
					$self->check_scope($main_int_line, \$scope);
					$self->check_scope($main_int_line, \$main_int_scope);
					if ($main_int_line =~ /unit\s+(\d+)/) {
						my $sub_int = $1;
						my $sub_int_scope = 1;
						my $iname = $main_int.".".$sub_int;
						print STDERR "\tGot subint $iname..."  if $debug>1;
						do {
							my $sub_int_line = <RFILE>;
							$self->check_scope($sub_int_line, \$scope);
							$self->check_scope($sub_int_line, \$main_int_scope);
							$self->check_scope($sub_int_line, \$sub_int_scope);
							if ($sub_int_line =~ /address\s+(\d+\.\d+\.\d+\.\d+)\/(\d+)/) {
								my ($addr, $mask) = ($1, $2);
								push(@{$self->{interfaces}->{$router}->{$iname}}, "$addr/$mask");		
							}
						} while ($sub_int_scope);
						print STDERR "done.\n"  if $debug>1;
					}
				} while ($main_int_scope);	
				print STDERR "done with interface $main_int\n\n" if $debug>1;
			}
		} while ($scope);
		print STDERR "done.\n" if $debug;;
	    }
	    
	    if ($_ =~ /routing-options\s+\{/) {
		print STDERR "parsing routing-options..."  if $debug;;
		my $scope=1;

		do {
		    my $line = <RFILE>;
		    $self->check_scope($line, \$scope);
		    

		    # router-id
		    if ($line =~ /router-id\s+($addr)/) {
			$self->{router_options}->{$router}->{'router-id'} = $1;
		    }

		    # autonomous system number
		    if ($line =~ /autonomous-system\s+(\d+)/) {
			$self->{router_options}->{$router}->{'asn'} = $1;
		    }

			# REB - grab jnpr static routes
			if ($line =~ /static/) {
				my $scope_static = 1;
				do {
			    	my $line_static = <RFILE>;
			    	$self->check_scope($line_static, \$scope);
			    	$self->check_scope($line_static, \$scope_static);
			    	if ($line_static =~ /$static_regexp/) {
						my ($network, $mask) = ($1, $2);
						push(@{$self->{routes}->{$router}}, "$network/$mask");
			    	} elsif ($line_static =~ /$static_discard/) {
					} elsif ($line_static =~ /$static_stanza_regexp/) {
						my ($network, $mask) = ($1, $2);
						push(@{$self->{routes}->{$router}}, "$network/$mask");
						my $scope_route = 1;
						do {
			    			my $line_route = <RFILE>;
			    			$self->check_scope($line_route, \$scope);
			    			$self->check_scope($line_route, \$scope_static);
			    			$self->check_scope($line_route, \$scope_route);
							if ($line_route =~ /$static_nexthop/) {
							}
						} while ($scope_route);
					} 
				} while ($scope_static);
			}
		    
		} while ($scope);
		print STDERR "done.\n"  if $debug;;
	    }

	    # parsing the protocol section of the config file
	    # BGP, etc.

	    if ($_ =~ /^protocols\s+\{/) {
		print STDERR "parsing protocols..."  if $debug;;
		my $scope = 1;

		do {
		    my $line = <RFILE>;
		    $self->check_scope($line, \$scope);

		    if ($line =~ /$bgp_regexp/) {

			# set some juniper DEFAULTS
			# juniper is smart and these things
			# are on by default

			$self->{router_options}->{$router}->{'runs_bgp'} = 1;
			$self->{router_options}->{$router}->{'deterministic-med'} = 1;
			$self->{router_options}->{$router}->{'no_synchronization'} = 1;
			$self->{router_options}->{$router}->{'compare-routerid'} = 1;

			# in juniper, cluster-id is session-specific: 'cluster'

			my $scope_bgp = 1;
			do {
			    my $line_bgp = <RFILE>;
			    $self->check_scope($line_bgp, \$scope);
			    $self->check_scope($line_bgp, \$scope_bgp);
			    
			    if ($line_bgp =~ /path-selection cisco-non-deterministic/) {
				$self->{router_options}->{$router}->{'deterministic-med'} = 0;
			    }

			    # note: global option in juniper, but session option in Cisco
			    if ($line_bgp =~ /remove-private/) {
				$self->{router_options}->{$router}->{'remove-private'} = 1;
			    }


			    if ($line_bgp =~ /group\s+([\w\d\-]+)\s+\{/) {
				my $scope_session = 1;
				my %group = ();
				
				my $min_session_id = $session_id+1;

				do {
				    my $line_s = <RFILE>;
				    $self->check_scope($line_s, \$scope);
				    $self->check_scope($line_s, \$scope_bgp);
				    $self->check_scope($line_s, \$scope_session);
				    

				    # get iBGP/eBGP
				    if ($line_s =~ /type\s+(internal|external)/) {
					if ($1 eq 'internal') {
					    $group{ebgp} = 0;
					} else {
					    $group{ebgp} = 1;
					}
				    }

				    # get remote-as
				    if ($line_s =~ /peer-as\s+(\d+)/) {
					$group{asnum} = $1;
				    }
				    
				    # get local-as
				    if ($line_s =~ /local-as\s+(\d+)/) {
					$group{local_asnum} = $1;
				    }
				    

				    # get whether this is an RR-client session
				    # and the cluster ID for this session
				    if ($line_s =~ /cluster\s+($addr)/) {
					# this is a RR client session if the 'cluster' option is set
					$group{rr_client} = 1;
					$group{cluster_id} = &inet_aton_($1);
				    }


				    if ($line_s =~ /import\s+(.*?);/) {
					my $import_names = $1;
					
					if ($import_names =~ /\[\s*(.*)\s*\]/) {
					    @{$group{irm_name}} = split('\s+', $1);
					} else {
					    push(@{$group{irm_name}}, $1);
					}
				    }


				    if ($line_s =~ /export\s+(.*?);/) {
					my $export_names = $1;

					if ($export_names =~ /\[\s*(.*)\s*\]/) {
					    @{$group{orm_name}} = split('\s+', $1);
					} else {
					    push(@{$group{orm_name}}, $1);
					}
				    }
				    



				    ##############################
				    # get neighbor
				    if ($line_s =~ /neighbor\s+($addr)/) {

					my $scope_neighbor = 1;
					$num_sessions++;
					$session_id++;
					my $nbr_ip = $1;


					do {
					    my $line_n = <RFILE>;
					    $self->check_scope($line_n, \$scope);
					    $self->check_scope($line_n, \$scope_bgp);
					    $self->check_scope($line_n, \$scope_session);
					    $self->check_scope($line_n, \$scope_neighbor);
	    
					    # get remote-as
					    if ($line_n =~ /peer-as\s+(\d+)/) {
						$self->{session_options}->{$session_id}->{asnum} = $1;
					    }
				    
					    # get local-as
					    if ($line_n =~ /local-as\s+(\d+)/) {
						$self->{session_options}->{$session_id}->{local_asnum} = $1;
					    }
				    
					    
					    # get whether this is an RR-client session
					    # and the cluster ID for this session
					    if ($line_n =~ /cluster\s+($addr)/) {
						# this is a RR client session if the 'cluster' option is set
						$self->{session_options}->{$session_id}->{rr_client} = 1;
						$self->{session_options}->{$session_id}->{cluster_id} = &inet_aton_($1);
					    }


					    if ($line_n =~ /import\s+(.*?);/) {
						my $import_names = $1;
						
						if ($import_names =~ /\[\s*(.*)\s*\]/) {
						    @{$session_to_irm_name{$session_id}} = split('\s+', $1);
						} else {
						    push(@{$session_to_irm_name{$session_id}}, $1);
						}
					    }


					    if ($line_n =~ /export\s+(.*?);/) {
						my $export_names = $1;
						
						if ($export_names =~ /\[\s*(.*)\s*\]/) {
						    @{$session_to_orm_name{$session_id}} = split('\s+', $1);
						} else {
						    push(@{$session_to_orm_name{$session_id}}, $1);
						}
					    }
				    
					    					    
					} while ($scope_neighbor);


					############################################################
					# group-based settings

					# set the local AS
					if (!defined($self->{session_options}->{$session_id}->{local_asnum})) {
					    if (defined($group{local_asnum})) {
						$self->{session_options}->{$session_id}->{local_asnum} = $group{local_asn};
					    } else {
						$self->{session_options}->{$session_id}->{local_asnum} = $self->{router_options}->{$router}->{'asn'};
					    }
					}
					

					# set the peer AS, rr client, and cluster ID vars
					foreach my $attr (qw(asnum rr_client cluster_id)) {
					    if (!defined($self->{session_options}->{$session_id}->{$attr})) {
						$self->{session_options}->{$session_id}->{$attr} = $group{$attr};
					    }
					}
					    

					# set the import names
					if (!defined($session_to_irm_name{$session_id})) {
					    foreach my $rmn (@{$group{irm_name}}) {
						push(@{$session_to_irm_name{$session_id}}, $rmn);
					    }
					}


					# set the export names
					if (!defined($session_to_orm_name{$session_id})) {
					    foreach my $rmn (@{$group{orm_name}}) {
						push(@{$session_to_orm_name{$session_id}}, $rmn);
					    }
					}



					############################################################
					
					# set eBGP variable for the session
					$self->{session_options}->{$session_id}->{ebgp} = $group{ebgp};
					    
					# set the remote AS for iBGP sessions
					if (!$group{ebgp}) {
					    $self->{session_options}->{$session_id}->{asnum} = $self->{router_options}->{$router}->{'asn'};
					}


				
					# apply this to each session, since we're associating this per-session
					# (Cisco does it that way)
					if ($self->{router_options}->{$router}->{'remove-private'}==1) {
					    $self->{session_options}->{$session_id}->{remove_private} = 1;
					}

					if (!defined($self->{session_id}->{$router}->{$nbr_ip})) {
					    $self->{session_id}->{$router}->{$nbr_ip} = $session_id;
					}

					# junOS enables "send-community" by default
					$self->{session_options}->{$session_id}->{send_community} = 1;

					push(@{$router_to_lbadj{$router}}, $nbr_ip);
									

				    }
				    

				} while ($scope_session);

			    }

			} while ($scope_bgp);
			
		    }

		} while ($scope);
		print STDERR "done.\n"  if $debug;;
	    }


	    if ($_ =~ /policy-options\s+\{/) {
		print STDERR "parsing policy options..."  if $debug;;
		my $canonical;
		my $scope = 1;

		do {
		    my $line = <RFILE>;
		    $self->check_scope($line, \$scope);

		    # this is the equivalent of a route-map
		    if ($line =~ /policy-statement\s+(\S+)/) {

			my $rm_scope = 1;
			my $rm_name = $1;
			my $clause_num = 0;

			do {
			    my $rm_line = <RFILE>;
			    $self->check_scope($rm_line, \$scope);
			    $self->check_scope($rm_line, \$rm_scope);

			    if ($rm_line =~ /term\s+(\S+)/) {
				my $term_scope = 1;
				$clause_num++;

				# each one of these terms will have a from/then
				# clause.

				do {
				    my $term_line = <RFILE>;
				    $self->check_scope($term_line, \$scope);
				    $self->check_scope($term_line, \$rm_scope);
				    $self->check_scope($term_line, \$term_scope);

				    # FROM terms -- push a bunch of terms for this clause
				    if ($term_line =~ /from\s+(.*)/) {

					my $fr_term = $1;

					# no scoping
					if ($fr_term !~ /\{/) {

					    $fr_term =~ s/;//g;
					    push(@{$unresolved_rm_from{$router}->{$rm_name}->{$clause_num}}, $fr_term);

					} else {
					    my $from_scope = 1;
					    
					    # XXX assumes '{' is on a line by itself.
					    #     likewise for '}'

					    do {
						my $from_line = <RFILE>;
						$self->check_scope($from_line, \$scope);
						$self->check_scope($from_line, \$rm_scope);
						$self->check_scope($from_line, \$term_scope);
						$self->check_scope($from_line, \$from_scope);

						$from_line =~ s/\s+(.*)\s*\;\s*/$1/;
						$from_line =~ s/;//g;
						chomp($from_line);
						if ($from_line !~ /\}/) {
						    push(@{$unresolved_rm_from{$router}->{$rm_name}->{$clause_num}}, $from_line);
						}

					    } while ($from_scope);

					}
				
				    }


				    # SET terms  -- push a bunch of terms for this clause
				    if ($term_line =~ /then\s+(.*)/) {
					# no scoping

					my $then_term = $1;

										# no scoping
					if ($then_term !~ /\{/) {

					    $then_term =~ s/;//g;
					    push(@{$unresolved_rm_then{$router}->{$rm_name}->{$clause_num}}, $then_term);

					} else {
					    my $then_scope = 1;
					    
					    # XXX assumes '{' is on a line by itself.
					    #     likewise for '}'

					    do {
						my $then_line = <RFILE>;
						$self->check_scope($then_line, \$scope);
						$self->check_scope($then_line, \$rm_scope);
						$self->check_scope($then_line, \$term_scope);
						$self->check_scope($then_line, \$then_scope);

						$then_line =~ s/\s+(.*)\s*\;\s*/$1/;
						$then_line =~ s/;//g;
						chomp($then_line);
						if ($then_line !~ /\}/) {
						    push(@{$unresolved_rm_then{$router}->{$rm_name}->{$clause_num}}, $then_line);
						}

					    } while ($then_scope);

					}
				

				
				    }



				} while ($term_scope);



			    }
			    
			    # should check here to see if all "accept" clauses have
			    # nexthop-self set.  if so, set if for the entire session.

			} while ($rm_scope);

		    }


		    ########################################
		    # community definition
		    if ($line =~ /community\s+(\S+)\s+members[\[\s]*(.*?)[\]\s]*;/) {

			my $cname = $1;
			my $cregexp = $2;

                       # REB - Handle extended community identifiers
#                       if ($cregexp =~ /\S+:(.+:.+)/) {
#                               $cregexp = $1;
#                       }

			$self->{community_defn}->{$router}->{$cname} = $cregexp;

		    }

		    if ($line =~ /as-path\s+(\S+)\s+(.*?);/) {

			my $asdef = $1;
			my $asregexp = $2;

			$self->{aspath_defn}->{$router}->{$asdef} = $asregexp;

		    }
		    

		} while ($scope);
		
		print STDERR "done.\n"  if $debug;

	    }
	}

	######################################################################
	# done parsing file, now resolve anything that 
	# needs to be resolved (e.g., route maps)
	# need to handle recursive policy statements...UGH.

	my @unresolved = keys %{$unresolved_rm_from{$router}};
	my $count = 0;

	while (scalar(@unresolved)) {

	    # ensure we don't go into an infinite loop resolving 
	    # circular policies

	    if ($count++ > 2) {
		printf ("ERROR: circular policy reference (%s).\n",
			join(',', @unresolved));
		last;
	    }


	    my @still_unresolved = ();

	    foreach my $rm_name (@unresolved) {

		my $canonical;
		
		# assume this session always does next-hop self
		# until we learn otherwise 

		$rm_name_to_nhself{$router}->{$rm_name} = 1;
		
		foreach my $clause_num (sort {$a <=> $b}
					keys %{$unresolved_rm_then{$router}->{$rm_name}} ) {
		    
		    $canonical .= "\{";
		    
		    if (defined($unresolved_rm_from{$router}->{$rm_name}->{$clause_num})) {
			printf STDERR ("$rm_name $clause_num %s\n",
				       join(',', @{$unresolved_rm_from{$router}->{$rm_name}->{$clause_num}})) if ($debug);
		    }

		    printf STDERR ("$rm_name $clause_num %s\n",
				   join(',', @{$unresolved_rm_then{$router}->{$rm_name}->{$clause_num}})) if ($debug);

		    

		    ##############################
		    # the FROM terms in the clause

		    foreach my $term (@{$unresolved_rm_from{$router}->{$rm_name}->{$clause_num}}) {
			my $rep = $self->resolve_statement($term, $router, $rm_name, $clause_num);
			$canonical = sprintf("%s%s::", $canonical, $rep) if (!($rep eq ''));
			
		    }
		    $canonical =~ s/^:://g;
		    $canonical =~ s/::$//;


		    ##############################
		    # the THEN terms in the clause


		    $canonical .= "<";

		    my ($set, $add);
		    foreach my $term (@{$unresolved_rm_then{$router}->{$rm_name}->{$clause_num}}) {
			$term =~ s/policy/pol/g;

			$set = '@' if ($term =~ /set/);
			$add = '+' if ($term =~ /add/);
			$add = '-' if ($term =~ /delete/);

			$term =~ s/set\s+//;
			$term =~ s/add\s+//;
			$term =~ s/delete\s+//;
		
			my $rep = $self->resolve_statement($term, $router, $rm_name, $clause_num);
			$set .= "$rep,";
		    }

		    $set =~ s/,$//;
		    $canonical =~ s/^:://g;
		    $canonical =~ s/::$//;
		    
		    $canonical .= $set;

		    if (($set !~ /reject/) &&
			($set !~ /next[\-\s]hop\s+self/)) {
			$rm_name_to_nhself{$router}->{$rm_name} = 0;
		    }

		    $canonical .= ">}";

		    # remove empty from clauses
		    $canonical =~ s/\<\>//g;
	
		}




		$self->{rm_defn}->{$router}->{$rm_name} = $canonical;

		if ($canonical =~ /[\{:]policy/) {
		    push(@still_unresolved, $rm_name);
		} else {
		    
		    if (!defined($canonical_rms{$canonical})) {
			$canonical_rms{$canonical} = scalar(keys %canonical_rms) + 1;
		    }
		    $rm_name_to_canonical{$router}->{$rm_name} = $canonical_rms{$canonical};
		    $self->{canonical_rms}->{$canonical_rms{$canonical}} = $canonical;
		}
	    }

	    @unresolved = ();
	    foreach (@still_unresolved) {
		push(@unresolved, $_);
	    }
	}
	############################################################

	# lots of jumping through hoops due to multiple route maps per 
	# session.

	foreach my $nbr (keys %{$self->{session_id}->{$router}}) {
	    my $sid = $self->{session_id}->{$router}->{$nbr};


	    my $cirm_str = "i:";
	    foreach my $irm_name (@{$session_to_irm_name{$sid}}) {
		$cirm_str .= sprintf("%d,",
				     $rm_name_to_canonical{$router}->{$irm_name});
	    }
	    $cirm_str =~ s/,+$//;
	    if (!defined($meta_canonical_rms{$cirm_str})) {
		$meta_canonical_rms{$cirm_str} = scalar(keys %meta_canonical_rms) + 1;
	    }



	    my $corm_str = "o:";
	    foreach my $orm_name (@{$session_to_orm_name{$sid}}) {
		$corm_str .= sprintf("%d,",
				     $rm_name_to_canonical{$router}->{$orm_name});

		# set next-hop-self as a sessions option (like Cisco)
		if ($rm_name_to_nhself{$router}->{$orm_name}) {
		    $self->{session_options}->{$sid}->{nh_self} = 1;
		}
	    }
	    $corm_str =~ s/,$//;
	    if (!defined($meta_canonical_rms{$corm_str})) {
		$meta_canonical_rms{$corm_str} = scalar(keys %meta_canonical_rms) + 1;
	    }


	    $self->{session_options}->{$sid}->{import_rm} = $meta_canonical_rms{$cirm_str};
	    $self->{key_to_meta_canonical}->{$meta_canonical_rms{$cirm_str}} = $cirm_str;


	    $self->{session_options}->{$sid}->{export_rm} = $meta_canonical_rms{$corm_str};
	    $self->{key_to_meta_canonical}->{$meta_canonical_rms{$corm_str}} = $corm_str;

	}


	
    }
}


######################################################################

sub check_scope {
    my $self = shift;
    my ($line, $rscope) = @_;

    if ($line =~ /\{/) { $$rscope++; }
    if ($line =~ /\}/) { $$rscope--; }

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

    my $canonical = "";

    # note: this is the "meta-canonical route map"
    # we must now split this to get all of the route maps

    foreach my $rm_number (split(',', $self->{key_to_meta_canonical}->{$rm_number})) {
	$rm_number =~ s/[io]\://;
	$canonical .= $self->{canonical_rms}->{$rm_number};
    }
#    print "$rm_number  $canonical\n" if ($rm_number==13);
    return $canonical;
}

######################################################################

sub get_all_routers {
    my $self = shift;
    return $self->{nodes};
}

sub get_all_route_maps {
    my $self = shift;
    return $self->{key_to_meta_canonical};
#    return $self->{canonical_rms};
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
	
        my $mask_num = &inet_aton_(join(".",@mask_parts));

        my $min_ip = $ip_num & $mask_num;
#   my $max_ip = $ip_num | ($mask_num ^ (2^32-1));

        my $cmd = "insert into $interfaces values ('$router', '$intn', '$ip_num', '$min_ip', '$mask_num')";
        $self->{dbh}->do($cmd);
    }
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
    # XXX need to write this bit
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

    my $bgp = $self->get_global_for_router($router, 'runs_bgp');
    my $asn = $self->get_global_for_router($router, 'asn');
    my $no_sync = $self->get_global_for_router($router, 'no_synchronization');
    my $dm = $self->get_global_for_router($router, 'deterministic-med');
    my $compare_rid = $self->get_global_for_router($router, 'compare-routerid');
    my $rid = $self->get_global_for_router($router, 'router-id');
    my $cid = $self->get_global_for_router($router, 'cluster-id');

    my $ridnum = unpack("N", pack("C4", split(/\./,$rid)));

    my $cmd = "insert into $router_global values ('$router','1','$bgp','$asn', '$no_sync', '$dm','$compare_rid','$ridnum','$cid')";
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

	printf ("%s\tneighbor\t%d\t%s\t%d\t%d\t%d\t%d\t%d\t%d\n",
		$router, $sid, $nbr_str, $rrc, $asn, $ebgp, $nhs, $irm, $erm);
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

	my $up = $ebgp;

	my $cid = $self->{session_options}->{$sid}->{cluster_id};
	my $loc_as = $self->{session_options}->{$sid}->{local_asnum};

	# XXX HELP!
	my $iacl = 0;
	my $eacl = 0;

	my $values = sprintf ("('%s','%d','%lu','%d','%d','%d','%d','%d','%d','%d','%d','%u','%d','%d','%d','%d')\n",
			      $router, $sid, $nbrnum, $rrc, $loc_as, $asn,
			      $irm, $erm, $iacl, $eacl, $ebgp, $cid, $nhs, $sc, $rp, $up);

	my $cmd = "insert into $sessions values $values";
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

	# see if this clause is a deny
	my $permit = 1;
	$permit = 0 if ($clause =~ /\<reject\>/);
	
	my ($from, $then);

	if ($clause =~ /(.*?)\<(.*?)\>/) {
	    $from = $1;
	    $then = $2;
	}

	my ($pfx, $mask);
	my ($as_regexp, $comm_regexp);

	if ($from =~ /com\((.*?)\)/) {
	    $comm_regexp = $1;
	}

	if ($from =~ /asp\(\"(.*?)\"\)/) {
	    $as_regexp = $1;
	}



	my ($localpref, $med, $origin, $community, $prepend, $nh_self);

	if ($then =~ /local-preference\s+(\d+)/) {
	    $localpref = $1;
	}

	if ($then =~ /metric\s+(\d+)/) {
	    $med = $1;
	}


	if ($then =~ /as-path-prepend\s+\"*(.*?)\"*,/) {
	    $prepend = $1;
	}


	if ($then =~ /com\((.*?)\)/) {
	    $community = $1;
	}

	if ($then =~ /next-hop[\s\-]+self/) {
	    $nh_self = 1;
	}

	my $aclnum;

	# we will actually need multiple of these for each clause num, due to 
	# route-filters, etc.
	my $values = sprintf ("('%d','%d','%d','%d','%s','%s','%d','%d','%d','%s','%s','%d')\n",
			      $rmid, $clause_num, $aclnum, $permit,
			      $as_regexp, $comm_regexp,
			      $localpref, $med, $origin, $community, $prepend, $nh_self);
	
	$value_str .= "$values";

    }
    return $value_str;

}




sub db_route_map {
    my $self = shift;
    my ($rmid) = @_;

    # get the base value so we don't override the 
    # canonical numbers from Cisco parsing

    $self->db_get_acl_id_base();
    $self->db_get_rmap_id_base();
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



# unravel the policy statement so we can get a canonical representation
sub resolve_statement {

    my $self = shift;
    my ($st, $router, $rm_name, $clause_num) = @_;

    my $canonical;
    
    if ($st =~ /community\s+(.*)/) {

	my $varstr = $1;
	my @vars;

	if ($varstr =~ /\[(.*)\]/) {
	    my $vars_ = $1;
	    $vars_ =~ s/^\s+//g;
	    $vars_ =~ s/\s+$//g;
	    @vars = split('\s+', $vars_);
        } elsif ($varstr =~ /=\s+(\S+)/) {
            my $vars_ = $1;
            push(@vars, $vars_);
        } elsif ($varstr =~ /\+\s+(\S+)/) {
            my $vars_ = $1;
            push(@vars, $vars_);
	} else {
	    push(@vars, $varstr);
	}

	if (!scalar(@vars)) {
	    return;
	}

	$canonical .= "com(";

	foreach my $var (@vars) {
	    if (defined(my $rep = $self->{community_defn}->{$router}->{$var})) {
		$canonical .= "$rep|";
	    } else {
		print "ERROR: undefined community $1\n";
		$self->{parse_errors}->{$router}->{$rm_name}->{$def_types{'com'}}->{$clause_num} = 1;
	    }
	}
	$canonical =~ s/\|$//;
	$canonical .= ")";

    } elsif ($st =~ /route-filter\s+(\d+\.\d+\.\d+\.\d+)\/(\d+)\s+(\w+)/) {

	my ($pfx,$mask) = ($1, $2);

	my $suffix;
	if ($3 =~ /longer/) {
	    $suffix = 'l';
	} elsif ($3 =~ /exact/) {
	    $suffix = 'e';
	} elsif ($3 =~ /shorter/) {
	    $suffix = 's';
	}
	
	$canonical .= "pfx($pfx/$mask$suffix)";


    } elsif ($st =~ /as-path\s+(.*)/) {



	my $varstr = $1;
	my @vars;


	if ($varstr =~ /\[(.*)\]/) {
	    my $vars_ = $1;
	    $vars_ =~ s/^\s+//g;
	    $vars_ =~ s/\s+$//g;
	    @vars = split('\s+', $vars_);
	} else {
	    push(@vars, $varstr);
	}

	if (!scalar(@vars)) {
	    return;
	}

	$canonical .= "asp(";

	foreach my $var (@vars) {
	    if (defined(my $rep = $self->{aspath_defn}->{$router}->{$var})) {
		$canonical .= "$rep|";
	    } else {
		print "ERROR: undefined aspath $1\n";
		$self->{parse_errors}->{$router}->{$rm_name}->{$def_types{'asp'}}->{$clause_num} = 1;
	    }
	}
	$canonical =~ s/\|$//;
	$canonical .= ")";

    } elsif ($st =~ /policy\s+(\S+)/) {

	if (defined(my $rep = $self->{rm_defn}->{$router}->{$1})) {
	    $canonical .= $rep;
	} else {
	    $canonical .= "policy $1";
#	    print "ERROR: undefined policy $1 on router $router\n";
	}


    } else {
	$canonical .= "$st";
    }
    
    return $canonical;
}

sub db_prefix_acls {
    my $self = shift;

    # should be addded...

}


######################################################################

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

