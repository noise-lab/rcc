#!/usr/bin/perl

BEGIN {
    push(@INC, "/home/feamster/bgp/src/rolex/perl/lib");  # NOTE: Change this to proper location.
    push(@INC, "../../../lib");
}

use ConfigCommon;
use ConfigDB;
use ConfigWeb;

use CGI::Pretty qw/:standard :html3/;
use CGI::Carp  qw(fatalsToBrowser);

use strict;

my $dbh = &dbhandle();
my $c = new CGI;
my $this = $c->url(-relative=>1);

my $params = $c->Vars();
$params->{'import'} = 2 if (!defined($params->{'import'}));


# NOTE: limits the number of rows that show up when displaying import/export
#       policies.  Crank it up if your browser can handle it.  Mine can't. :)
my $limit = "limit 200";


######################################################################

sub print_headers {
    print header, start_html("Control Flow Graph"), h1("Control Flow");
}

sub print_footers{
    print end_html;
}



######################################################################

&print_headers();

if (defined($params->{'mode'})) {

    ## different display mode -- by AS
    if ($params->{'mode'} eq 'as') {
	&show_ases($params->{'page'}, $params->{'limit'}, $dbh, $this);
    }


} elsif (defined($params->{'as'})) {

    # display the policies for an AS
    # parameters: neighbor AS, import/export

    &show_policies_for_as($params->{'as'}, $params->{'import'},
			  $params->{'sort'}, $params->{'page'}, 
			  $params->{'limit'},
			  $dbh, $this);

} elsif (defined($params->{'router'})) {

    #parameters: router and whether it's import/export policy
    &show_policies_for_router($params->{'router'}, $params->{'import'},
			      $params->{'sort'}, $params->{'page'},
			      $params->{'limit'},
			      $dbh,  $this);

} elsif (defined($params->{'rm'})) {

    my @rms = split(',', $params->{'rm'});

    # allow for showing multiple route maps at once
    foreach my $rm (@rms) {
	&show_routemap($rm, $dbh);
    }
    if (scalar(@rms)==2) {
	&diff_routemap($rms[0], $rms[1], $dbh);
    }

} else {
    
    # default behavior
    # provide a list of nodes in the graph
    # (ebgp indicates is some subset should be shown)
    &show_routers($params->{'ebgp'}, $params->{'page'},
		  $params->{'limit'},
		  $dbh, $this);
}

&print_footers();
