#!/usr/bin/perl

BEGIN {
    push(@INC, "../../lib");
    push(@INC, "../../rules");
}


use ConfigParse;

my $debug = 1;
my $riftrans = "./riftrans.pl";

my @configfiles = <$ARGV[0]/*-confg>;
my @junos_configfiles = <$ARGV[0]/*-jconfg>;

system("rm -rf $ARGV[0]/trans/");
system("mkdir -p $ARGV[0]/trans");

foreach my $configfile (@configfiles) {
    my $router;
    my $dir;
    if ($configfile =~ /(.*)\/([\w\d\-\.]+)-confg/) {
	($dir, $router) = ($1, $2);
    }

    if (defined($ARGV[1])) {
	$dir = $ARGV[1];
	system("mkdir -p $dir/trans");
    }

    my $cmd = sprintf("%s %s %s/trans/%s-confg",
		      $riftrans, $configfile, $dir, $router);
    print STDERR "$cmd\n" if $debug;
    system($cmd);
}


foreach my $configfile (@junos_configfiles) {
    system("cp $configfile $ARGV[0]/trans/");
}
