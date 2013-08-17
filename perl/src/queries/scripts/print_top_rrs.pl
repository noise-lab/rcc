#!/usr/bin/perl

BEGIN {
    push(@INC, "../modules");
    
    # these are for the "menu.pl" script, which
    # requires different relative paths

    push(@INC, "../queries/modules/");
    push(@INC, "../../lib/");
}

use ibgp;

my $ibgp = new ibgp;
$ibgp->print_top_level_rrs();
