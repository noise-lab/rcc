#!/usr/bin/perl

BEGIN {
    push(@INC, "../../lib");
}


use strict;
use ConfigParse;
my %keywords; 
my $gentok = "./gen_cmd_list.pl |";
$gentok = "./cmdlist.txt";

sub gen_keyword_hash {
    my $rkeywords = shift;
    my $ruledir = "../pattern-rules/rules/";

    return if (!defined($ruledir));

    my %all_keywords;

    # build a hash of all known tokens
    print STDERR "generating token list...\n";
    open (TLIST, "$gentok") || die "Can't run $gentok: $!\n";
    while (<TLIST>) {
	chomp;
	$all_keywords{$_} = 1;
    }


    # see which tokens show up in any of the rules we're trying
    # to test...

    print STDERR "matching against known rules...\n";
    my @rulefiles = <$ruledir/*.pm>;
    foreach my $rf (@rulefiles) {
	open (RF, "$rf") || die "Can't open $rf: $!\n";
	while (<RF>) {
	    # look for FSM transition statement
	    if (/transition\(\'(.*?)\'\)/) {
		my $statement = $1;
		my @tokens = split('\s+', $statement);
		my $stm = "";
		foreach my $tok (@tokens) {
		    if (defined($all_keywords{$tok})) {
			$stm .= "$tok ";
		    } elsif (!($stm eq "")) {
			chop($stm);
			$rkeywords->{$stm} = 1;
			$stm = "";
		    }
		}
	    }
	}
    }
}


#&gen_keyword_hash(\%keywords, $ARGV[1]);
&parse_config_cisco($ARGV[0], $ARGV[1]);
