#!/usr/bin/perl

package ConfigWeb;

BEGIN {
    push(@INC, "../../../lib");
}

use ConfigCommon;
use ConfigDB;

use CGI::Pretty qw/:standard :html3/;
use CGI::Carp  qw(fatalsToBrowser);
use Algorithm::Diff qw/diff/;
use Data::Dumper;

require Exporter;
use vars(qw());

@ISA = ('Exporter');
@EXPORT = (qw(&show_ases &show_routers),
	   qw(&show_policies_for_as &show_policies_for_router),
	   qw(&show_routemap &diff_routemap));

my $limitnum = 200;
my $limit = "limit $limitnum";

sub show_ases {
    my ($page, $limitnum_, $dbh, $this) = @_;

    my @rows;


    ####################
    # paging stuff
    $page = 0 if (!defined($page));
    $limitnum = $limitnum_ if (defined($limitnum_));
    my $last_pg = $page-1;
    my $next_pg = $page+1;
    my $min = $page * $limitnum;
    my $max = ($page+1) * $limitnum;
    my $limit = "limit $min,$max";

    my $q = "select count(distinct neighbor_asn) from $cf_sessions";
    my $sth = $dbh->prepare($q);
    $sth->execute;
    my ($num_rows) = $sth->fetchrow_array();
    ####################


    my $q = "select neighbor_asn, count(*) as x from sessions where import=0 group by neighbor_asn order by x desc, neighbor_asn $limit";
    my $sth = $dbh->prepare($q);
    $sth->execute;

    push(@rows, th({-align=>RIGHT}, ['AS', 'Sessions']));
    while (my ($asn, $cnt) = $sth->fetchrow_array()) {

	push(@rows, td({-align=>RIGHT},
		       [
			$asn,
			a({href => "$this?as=$asn"}, $cnt)
			]));
    }
    print table({-width=>'30%'},caption(b('Neighbor ASes')),Tr(\@rows));


    printf p;

    printf (a({href=>"$this?mode=as&page=$last_pg&limit=$limitnum"},
	      'Last Page')) if ($page>0);
    printf (a({href=>"$this?mode=as&page=$next_pg&limit=$limitnum"},
	      'Next Page')) if ($next_pg*$limitnum < $num_rows);


}





sub show_routers {
    my @rows;

    my ($ebgp, $page, $limitnum_, $dbh, $this) = @_;

    ####################
    # paging stuff
    $page = 0 if (!defined($page));
    $limitnum = $limitnum_ if (defined($limitnum_));
    my $last_pg = $page-1;
    my $next_pg = $page+1;
    my $min = $page * $limitnum;
    my $max = ($page+1) * $limitnum;
    my $limit = "limit $min,$max";

    my $q = "select count(distinct neighbor_asn) from $cf_sessions";
    my $sth = $dbh->prepare($q);
    $sth->execute;
    my ($num_rows) = $sth->fetchrow_array();
    ####################



    my $restrictions = "";
    $restrictions = "and has_ebgp=1" if (defined($ebgp) && $ebgp);
    $restrictions = "and has_ebgp=0" if (defined($ebgp) && !$ebgp);

    my $q = "select router, inet_ntoa(loopback) from $cf_routers where is_ebgp=0 $restrictions order by router $limit";
    my $sth = $dbh->prepare($q);
    $sth->execute;

    push(@rows, th(['Router', 'Loopback']));
    
    while (my ($router, $lb) = $sth->fetchrow_array()) {
	push (@rows, td({-align=>'CENTER'},
			[a({href => "$this?router=$router&import=2"}, $router), $lb,
			 a({href => "$this?router=$router&import=0"}, 'Export Only'),
			 a({href => "$this?router=$router&import=1"}, 'Import Only')
			 ]));
    }

    print table({-width=>'60%'},caption(b('Routers')),Tr(\@rows));



    printf p;

    printf (a({href=>"$this?page=$last_pg&limit=$limitnum"},
	      'Last Page')) if ($page>0);
    printf (a({href=>"$this?page=$next_pg&limit=$limitnum"},
	      'Next Page')) if ($next_pg*$limitnum < $num_rows);

}

sub show_policies_for_as {
    
    my ($asn, $import_, $sort, $page, $limitnum_, $dbh, $this) = @_;
    my @rows;
    my %rms;
    my %rms_ei;

    my $rm_cap;
    if (!$import_) {
	$rm_cap = " -- Outbound Policies";
    } elsif($import_==1) {
	$rm_cap  = " -- Inbound Policies";
    }
    
    ####################
    # paging stuff
    $page = 0 if (!defined($page));
    $limitnum = $limitnum_ if (defined($limitnum_));
    my $last_pg = $page-1;
    my $next_pg = $page+1;
    my $min = $page * $limitnum;
    my $max = ($page+1) * $limitnum;
    my $limit = "limit $min,$max";

    my $q = "select count(*) from $cf_sessions where neighbor_asn=$asn";
    my $sth = $dbh->prepare($q);
    $sth->execute;
    my ($num_rows) = $sth->fetchrow_array();
    ####################

    if ($import_ < 2) {

	push(@rows, th(['Router', 'Neighbor', 'Neighbor AS',
			a({href => "$this?page=$page&limit=$limitnum&as=$asn&import=$import_&sort=$import_"} ,'Route Map')
			]));

	
	my $q = "select router, neighbor, neighbor_asn, route_map from $cf_sessions where neighbor_asn=$asn and import=$import_ order by neighbor $limit";
	my $sth = $dbh->prepare($q);
	$sth->execute;
	
	while (my ($router, $neighbor, $neighbor_asn, $route_map) =
	       $sth->fetchrow_array()) {
	    push(@rows, td({-align=>'CENTER'},
			   [a({href => "$this?router=$router&import=$import_"}, $router),
			    a({href => "$this?router=$neighbor&import=$import_"}, $neighbor),
			    a({href => "$this?as=$neighbor_asn&import=$import_"}, $neighbor_asn),
			    a({href => "$this?rm=$route_map"}, $route_map)
			    ]));
	    $rms{$route_map} = 1;
	}
    } else {


	my %route_maps;

	my %rm_index;
	my %routers;

	push(@rows, th(['Router', 'Neighbor', 'Neighbor AS',
			a({href => "$this?page=$page&limit=$limitnum&as=$asn&import=$import_&sort=1"} ,'Import Route Map'),
			a({href => "$this?page=$page&limit=$limitnum&as=$asn&import=$import_&sort=0"} ,'Export Route Map')
			]));

	# doing both import and export

	
	for (my $i=0; $i<2; $i++) {
	    my $q = "select router, neighbor, neighbor_asn, route_map from $cf_sessions where neighbor_asn=$asn and import=$i order by router,neighbor $limit";

	    my $sth = $dbh->prepare($q);
	    $sth->execute;

	    while (my ($router, $neighbor, $neighbor_asn, $route_map) =
		   $sth->fetchrow_array()) {

		# building up a hash of the route maps
		$route_maps{$router}->{$neighbor}->{$i} = $route_map;

		# keep track of all route maps defined for this query
		$rms{$route_map} = 1;
		$rms_ei{$i}->{$route_map} = 1;

		# keep track of rm index, in case we have to sort on this
		push(@{$rm_index{$i}->{$route_map}}, $neighbor);
		$routers{$neighbor} = $router;


	    }
	}

	if (!defined($sort)) {

	    # output rows with import/export, sorted by router and neighbor ASN
	    foreach my $router (sort keys %route_maps) {
		foreach my $neighbor (keys %{$route_maps{$router}}) {
		    push(@rows, td({-align=>'CENTER'},
				   [a({href => "$this?router=$router&import=$import_"}, $router),
				    a({href => "$this?router=$neighbor&import=$import_"}, $neighbor),
				    a({href => "$this?as=$asn&import=$import_"}, $asn),
				    a({href => "$this?rm=$route_maps{$router}->{$neighbor}->{1}"},
				      $route_maps{$router}->{$neighbor}->{1}),
				    a({href => "$this?rm=$route_maps{$router}->{$neighbor}->{0}"},
				      $route_maps{$router}->{$neighbor}->{0})
				    ]));

		}
	    }
	} else {

	    # sort based on route map index
	    foreach my $rm (sort {$a <=> $b} keys %{$rm_index{$sort}}) {

		foreach my $neighbor (sort {
		    if($routers{$a} <=> $routers{$b}) {
			return $routers{$a} <=> $routers{$b};
		    } else {
			return $a cmp $b;
		    }
		} @{$rm_index{$sort}->{$rm}}) {

		    my $router = $routers{$neighbor};
		    push(@rows, td({-align=>'CENTER'},
				   [a({href => "$this?router=$router&import=$import_"}, $router),
				    a({href => "$this?router=$neighbor&import=$import_"}, $neighbor),
				    a({href => "$this?as=$asn&import=$import_"}, $asn),
				    a({href => "$this?rm=$route_maps{$router}->{$neighbor}->{1}"},
				      $route_maps{$router}->{$neighbor}->{1}),
				    a({href => "$this?rm=$route_maps{$router}->{$neighbor}->{0}"},
				      $route_maps{$router}->{$neighbor}->{0})
				    ]));
		}
		
	    }

	}


    }

    if ($import_>1) {
	my $rmi_str = sprintf("%s", join(',', sort {$a <=> $b} keys %{$rms_ei{1}}));
	my $rme_str = sprintf("%s", join(',', sort {$a <=> $b} keys %{$rms_ei{0}}));

	push(@rows, td({-align=>'CENTER'},
		       ['','','',
			a({href =>"$this?rm=$rmi_str"}, 'Show All Import'),
			a({href =>"$this?rm=$rme_str"}, 'Show All Export')]));
    }


    print table({-width=>'80%'},caption(b("Routers Peering with AS $asn $rm_cap")),
		Tr(\@rows));



    printf (a({href=>"$this?rm=%s"}, 'Show All Route Maps'), join(',', sort {$a <=> $b} keys %rms));

    printf p;

    printf (a({href=>"$this?page=$last_pg&limit=$limitnum&as=$asn&import=$import_"},
	      'Last Page')) if ($page>0);
    printf (a({href=>"$this?page=$next_pg&limit=$limitnum&as=$asn&import=$import_"},
	      'Next Page')) if ($next_pg*$limitnum < $num_rows);

}

sub show_policies_for_router {

    my ($router, $import_, $sort, $page, $limitnum_, $dbh, $this) = @_;
    my @rows;
    my %rms;
    my %rms_ei;

    my $sort_order = "order by neighbor_asn,neighbor";
    if (defined($sort)) {
	$sort_order = "order by route_map, neighbor_asn, neighbor";
    }

    my $rm_cap;
    if (!$import_) {
	$rm_cap = " -- Outbound Policies";
    } elsif($import_==1) {
	$rm_cap  = " -- Inbound Policies";
    }

    ####################
    # paging stuff
    $page = 0 if (!defined($page));
    $limitnum = $limitnum_ if (defined($limitnum_));
    my $last_pg = $page-1;
    my $next_pg = $page+1;
    my $min = $page * $limitnum;
    my $max = ($page+1) * $limitnum;
    my $limit = "limit $min,$max";

    my $q = "select count(*) from $cf_sessions where router='$router'";
    my $sth = $dbh->prepare($q);
    $sth->execute;
    my ($num_rows) = $sth->fetchrow_array();
    ####################


    if ($import_ < 2) {
	# in this case, we're showing only the import or export route map

	push(@rows, th(['Router', 'Neighbor', 'Neighbor AS',
			a({href => "$this?page=$page&limit=$limitnum&router=$router&import=$import_&sort=$import_"} ,'Route Map')
			]));
	
	my $q = "select router, neighbor, neighbor_asn, route_map from $cf_sessions where router='$router' and import=$import_ $sort_order $limit";
	my $sth = $dbh->prepare($q);
	$sth->execute;
	
	while (my ($router, $neighbor, $neighbor_asn, $route_map) =
	       $sth->fetchrow_array()) {
	    push(@rows, td({-align=>'CENTER'},
			   [a({href => "$this?router=$router&import=$import_"}, $router),
			    a({href => "$this?router=$neighbor&import=$import_"}, $neighbor),
			    a({href => "$this?as=$neighbor_asn&import=$import_"}, $neighbor_asn),
			    a({href => "$this?rm=$route_map"}, $route_map)
			    ]));
	    $rms{$route_map} = 1;
	}
    } else {

	my %route_maps;

	my %rm_index;
	my %neighbor_asns;

	push(@rows, th(['Router', 'Neighbor', 'Neighbor AS',
			a({href => "$this?page=$page&limit=$limitnum&router=$router&import=$import_&sort=1"} ,'Import Route Map'),
			a({href => "$this?page=$page&limit=$limitnum&router=$router&import=$import_&sort=0"} ,'Export Route Map')
			]));
	

	# do both import and export policy

	for (my $i=0; $i<2; $i++) {
	    my $q = "select router, neighbor, neighbor_asn, route_map from $cf_sessions where router='$router' and import=$i order by neighbor_asn, neighbor $limit";
	    my $sth = $dbh->prepare($q);
	    $sth->execute;

	    while (my ($router, $neighbor, $neighbor_asn, $route_map) =
		   $sth->fetchrow_array()) {

		# build a hash of the route maps
		$route_maps{$neighbor}->{$neighbor_asn}->{$i} = $route_map;

		# keep track of all canonical route maps defined for this query
		$rms{$route_map} = 1;
		$rms_ei{$i}->{$route_map} = 1;

		# keep track of rm index, in case we have to sort on this
		push(@{$rm_index{$i}->{$route_map}}, $neighbor);
		$neighbor_asns{$neighbor} = $neighbor_asn;


	    }
	}


	if (!defined($sort)) {

	    # output rows with import/export, sorted by router and neighbor ASN
	    # XXX shorting should be numerically on ASN
	    foreach my $neighbor (sort keys %route_maps) {
		foreach my $neighbor_asn (keys %{$route_maps{$neighbor}}) {
		    push(@rows, td({-align=>'CENTER'},
				   [a({href => "$this?router=$router&import=$import_"}, $router),
				    a({href => "$this?router=$neighbor&import=$import_"}, $neighbor),
				    a({href => "$this?as=$neighbor_asn&import=$import_"}, $neighbor_asn),
				    a({href => "$this?rm=$route_maps{$neighbor}->{$neighbor_asn}->{1}"},
				      $route_maps{$neighbor}->{$neighbor_asn}->{1}),
				    a({href => "$this?rm=$route_maps{$neighbor}->{$neighbor_asn}->{0}"},
				      $route_maps{$neighbor}->{$neighbor_asn}->{0})
				    ]));

		}
	    }
	} else {
	    
	    # sort based on route map index

	    foreach my $rm (sort {$a <=> $b} keys %{$rm_index{$sort}}) {

		# XXX this should also do a secondary sort based on router name
		foreach my $neighbor (sort {
		    if($neighbor_asns{$a} <=> $neighbor_asns{$b}) {
			return $neighbor_asns{$a} <=> $neighbor_asns{$b};
		    } else {
			return $a cmp $b;
		    }
		} @{$rm_index{$sort}->{$rm}}) {
		    my $neighbor_asn = $neighbor_asns{$neighbor};
		    push(@rows, td({-align=>'CENTER'},
				   [a({href => "$this?router=$router&import=$import_"}, $router),
				    a({href => "$this?router=$neighbor&import=$import_"}, $neighbor),
				    a({href => "$this?as=$neighbor_asn&import=$import_"}, $neighbor_asn),
				    a({href => "$this?rm=$route_maps{$neighbor}->{$neighbor_asn}->{1}"},
				      $route_maps{$neighbor}->{$neighbor_asn}->{1}),
				    a({href => "$this?rm=$route_maps{$neighbor}->{$neighbor_asn}->{0}"},
				      $route_maps{$neighbor}->{$neighbor_asn}->{0})
				    ]));
		}
		
	    }

	}

    }

    if ($import_>1) {
	my $rmi_str = sprintf("%s", join(',', sort {$a <=> $b} keys %{$rms_ei{1}}));
	my $rme_str = sprintf("%s", join(',', sort {$a <=> $b} keys %{$rms_ei{0}}));

	push(@rows, td({-align=>'CENTER'},
		       ['','','',
			a({href =>"$this?rm=$rmi_str"}, 'Show All Import'),
			a({href =>"$this?rm=$rme_str"}, 'Show All Export')]));
    }



    print table({-width=>'80%'},caption(b("Neighbor Routers for $router $rm_cap")),
		Tr(\@rows));

    printf (a({href=>"$this?rm=%s"}, 'Show All Route Maps'), join(',', sort {$a <=> $b} keys %rms));


    printf p;

    printf (a({href=>"$this?page=$last_pg&limit=$limitnum&router=$router&import=$import_"},
	      'Last Page')) if ($page>0);
    printf (a({href=>"$this?page=$next_pg&limit=$limitnum&router=$router&import=$import_"},
	      'Next Page')) if ($next_pg*$limitnum < $num_rows);


}

sub show_routemap {
    my ($index, $dbh) = @_;

    my $q = "select rep from $cf_rms where idx=$index";
    my $sth = $dbh->prepare($q);
    $sth->execute;
    
    my ($rep) = $sth->fetchrow_array();
    $rep =~ s/\</\&lsaquo /g;
    $rep =~ s/\>/\&rsaquo /g;
    $rep =~ s/\}/\}\<br\>/g;
    
    print h3("Route Map $index");

    print "$rep\n";

}

sub diff_routemap {
    my ($idx1, $idx2, $dbh) = @_;

    my $q = "select rep from $cf_rms where idx=$idx1";
    my $sth = $dbh->prepare($q);
    $sth->execute;
    my ($rep1) = $sth->fetchrow_array();
    my @rep1a = split(/\}/, $rep1);


    $q = "select rep from $cf_rms where idx=$idx2";
    $sth = $dbh->prepare($q);
    $sth->execute;
    my ($rep2) = $sth->fetchrow_array();
    my @rep2a = split(/\}/, $rep2);
    
    my $diffs = diff( \@rep1a, \@rep2a );

    print h3("<font color=red>Diff Output</font> (zero-indexed)");
    print "<table>";

    foreach my $diff1 (@$diffs) {
	foreach my $diff (@$diff1) {
	    my $diffstr = join (",", @$diff);
	    $diffstr =~ s/\</\&lsaquo /g;
	    $diffstr =~ s/\>/\&rsaquo /g;
	    $diffstr =~ s/,/<\/td><td>/g;

	    print "<tr><td>$diffstr}</td></tr>";

	}
    }

       print "</table>"; 
   
}




1;
