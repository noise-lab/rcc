#!/usr/bin/perl


package ConfigParse;

use Data::Dumper;
use strict;
use CiscoTypes;
use ConfigCommon;

require Exporter;
use vars(qw(@ISA @EXPORT $config_basedir $configdir $rifprog));
@ISA = ('Exporter');
@EXPORT = (qw (parse_scoped_fexp parse_config_cisco $config_basedir),
	   qw (&router_to_config &config_to_router &trim_regexp));


# use the transformed files
# (these have the peer groups expanded, etc.)

$configdir = sprintf("%s/trans", $config_basedir);

######################################################################

sub trim_spaces {
    my $rstr = shift;
    $$rstr =~ s/^\s+//g;
    $$rstr =~ s/\s+$//g;
}

######################################################################
# convert router name to configuration file name
# and vice versa

sub router_to_config {
    my $router = shift;
    my $juniper = shift;

    # need to test if it's a bound variable or not
    # actually, can probably return a list of all files that match
    my @rfiles_match;

    my $suffix = "confg";
    $suffix = "jconfg" if $juniper;

    my $regexp_file = sprintf ("%s/%s-%s", $configdir, $router, $suffix);
    my @rfiles = <$configdir/*-$suffix>;

    foreach (@rfiles) {
	push(@rfiles_match, $_) if ($_ =~ /$regexp_file/);
    } 
    
    return \@rfiles_match; 
}

sub config_to_router {
    my $rfile = shift;
    if ($rfile =~ /^.*\/($rtr_name)-confg/){
	return $1;
    }
}


######################################################################



sub parse_scoped_fexp {
    my ($sexp, $rmatch) = @_;
    my ($router_exp, $rexp) = split(':', $sexp);
    my ($outer_scope, $inner_scope);
    my ($outer_match, $inner_match);

    if ($rexp =~ /(.*)\[\[(.*)\]\]/) {
	($outer_scope, $inner_scope) = ($1, $2);
	&trim_spaces(\$outer_scope);
	&trim_spaces(\$inner_scope);
    } else {
	$outer_scope = $rexp;
	&trim_spaces(\$outer_scope);
    }

    # get an array of all files that match $router_exp
    my $rfiles = &router_to_config($router_exp);

    # comb through each router config file that matches
    foreach my $rfile (@$rfiles) {
	my $router = &config_to_router($rfile);

	print STDERR "Router: $router, scope1: $outer_scope, scope2: $inner_scope\n" if $debug;

#	open (RF, "$rifprog $rfile |") || die "Can't open $rfile with $rifprog: $!\n";
	open (RF, "$rfile") || die "Can't open $rfile: $!\n";
	while (<RF>) {
	    chomp;
	    if ($_ =~ /($outer_scope)/) {
		
		$outer_match = $1;

		if (defined($inner_scope)) {
		    while ($_ !~ /^\!/) {
			chomp; 
			if ($_ =~ /($inner_scope)/) {
			    $inner_match = $1;
			    push (@{$rmatch}, sprintf("%s: %s [[ %s ]]", $router,
						      $outer_match, $inner_match));
			    printf STDERR ("HIT=> %s: %s [[ %s ]]\n", $router,
					   $outer_match, $inner_match) if $debug;
			}
			$_ = <RF>;
		    }
		} else {
		    push (@{$rmatch}, sprintf("%s: %s",
					      $router, $outer_match));
		    print STDERR "HIT!\n" if $debug;
		}
		
	    }
	}

    }

}

######################################################################
sub parse_config_cisco {
    
    # now: expand peer-groups
    # eventually: expand acls, etc.

    my $cfile = shift;
    my $outfile = shift;
    my $rkeywords = shift;
    my %pgrp_st;

    my $last_line;

    if (defined($outfile)) {
	open(OUT, ">$outfile") || die "can't open $outfile: $!\n";
	select(OUT);
    }


    # two pass.  first one, take care of address family shit

    my $addr_fam = `grep -c "address-family ipv4" $cfile`;
    chomp($addr_fam);

    if ($addr_fam > 1) {
	open (CF, "$cfile") || die "can't open $cfile: $!\n";
	my $line = <CF>;
	while ($line) {
	    if ($line =~ /address-family\s+ipv4\s*$/) {
		
		do {
		    while ($line =~ /neighbor\s+([\w\-]+)\s+(.*)$/) {
			chomp;
			$pgrp_st{$1}->{$2} = 1;
			$line = <CF>;
		    }
		    $line = <CF>;
		} while ($line !~ /exit\-address\-family/);
	    
	    }
	    $line = <CF>;
	}
	close(CF);
    } 



    open (CF, "$cfile") || die "can't open $cfile: $!\n";
    my $line = <CF>;
    while ($line) {
	chomp($line);

	if ($line =~ /neighbor\s+([\w\-]+)\s+peer\-group/) {

	    ## ** keep track of what the peer-group means, but don't print out

	    my $pgrp_name = $1;
	    $line = <CF>;
	    while ($line =~ /^\s+neighbor\s+$pgrp_name\s+(.*)$/) {
		chomp;
		$pgrp_st{$pgrp_name}->{$1} = 1;
		$line = <CF>;
	    }
	} elsif ($line =~ /^(.*neighbor)\s+([\d\.]+)\s+peer\-group\s+([\w\-]+)/) {

	    ## ** dereference the peer-group listing **

	    my $preamble = $1;
	    my $ip = $2;
	    my $pgrp_name = $3;
	    
	    my @statements = keys %{$pgrp_st{$pgrp_name}};
	    foreach my $st (@statements) {
		print "$preamble $ip $st\n";
	    }
	    $line = <CF>;
	} elsif ($line =~ /(ip address)\s+([\d\.]+)\s+255\.255\.255\.255/) {
	    print "$1 $2\n";
	    $line = <CF>;
	} elsif (scalar(keys %$rkeywords)) {
	    foreach my $token (keys %$rkeywords) {
		if ($line =~ /^\s*$token\s+/ || ($line =~/^\!/ && $last_line !~ /^\!/)) {
		    print "$line\n";
		    $last_line = $line;
		    last;
		}
	    }
	    $line = <CF>;
	} elsif ($line =~ /$stop_words/) {
	    print "\@STOP\@\n$line\n";
	    $line = <CF>;
	} else {
	    print "$line\n";
	    $line = <CF>;
	}

    }
    print "\n\@STOP\@\n";

    if (defined($outfile)) {
	close(OUT);
    }
   
}

######################################################################
# trim regexps as specified in access-lists, etc.
# so they are suitable perl regexps

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

    $$rexp =~ s/\_\(\.\*\)\_/ \.\* /g;
    $$rexp =~ s/^\_(.*?)\_$/\^$1\$| $1 |\^$1 | $1\$/g;
    $$rexp =~ s/^\_([\$\d]+)/\^$1| $1/g;
    $$rexp =~ s/([\^\d]+)\_$/$1 |$1\$/g;
    $$rexp =~ s/\_/ /g;

    $$rexp = sprintf("(%s)", $$rexp);

    if ($deny) {
	$$rexp = sprintf("!%s", $$rexp);
    }

}


1;
