#!/usr/bin/perl

use strict;
my $cmdlist = "./crgindx.htm";

sub gen_tok_list {

    my %printed = ();
    my $seen_aaa = 0;
    my $prev_first_word = 0;


    open (CL, "$cmdlist") || die "Can't open $cmdlist: $!\n";
    while (<CL>) {
	chomp;
	if (/aaa/) {$seen_aaa = 1;}
	next if (!$seen_aaa || $_ !~ /^[a-z]/);

	$_ =~ s/\<.*\>//g;
	
	my @words = split('\s');
	my $first_word = $words[0];

	next if ($prev_first_word gt $first_word);
	$prev_first_word = $first_word;

	# tokenize
	$_ =~ s/\s+$//;
	$_ =~ s/[\(\)]//g;
	my @tokens = split('\s+');

	foreach my $tok (@tokens) {
	    if (!$printed{$tok}) {
		$printed{$tok}=1;
		print "$tok\n";
	    }
	}
    }

}

&gen_tok_list();
