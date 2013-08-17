#!/usr/bin/perl

BEGIN {
    push(@INC, "../../lib");
}

use ConfigCommon;
use strict;


sub rename {
    my ($file, $suffix) = @_;

    my $newf = $file;
    if ($file !~ /$suffix$/) {
	$newf = sprintf("%s-%s", $file, $suffix);
	system("mv $file $newf\n");
    }

}

sub rename_files {
    my ($dir) = @_;
    my @files = <$dir/*>;
    
    foreach my $f (@files) {
	my $ws = "\[ \\t\]";
	my $cisco_count = `$grep -c "^interface$ws" $f`;
	chomp($cisco_count);
	my $junos_count = `$grep -c "^interfaces$ws" $f`;
	chomp($junos_count);

	if ($cisco_count > 0) {
	    print "$f is a Cisco-style config\n";
	    my $newf = &rename($f, 'confg');
	}
	if ($junos_count > 0) {
	    print "$f is a JunOS-style config\n";
	    my $newf = &rename($f, 'jconfg');
	}
	

    }
}

&rename_files($ARGV[0]);
