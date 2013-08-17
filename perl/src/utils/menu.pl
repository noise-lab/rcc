#!/usr/bin/perl

BEGIN {
    push(@INC, "../../lib/");

}

use ConfigCommon;
use rccHTML;

 my %options = ('db_if' => 1,
		'db_isis' => 2,
		'db_ospf' => 3,
		'suffix' => 4,
		'preprocess' => 5,
		'parse' => 6,
		'verify' => 7,
		'quit' => 8);


my $mysql = "mysql";
my $last_entry;

sub print_menu {
    print <<EOM;

Enter option:
1. Create BGP database from scratch. (Database Setup)
2. Create IS-IS database from scratch. (Database Setup)
3. Create OSPF database from scratch. (Database Setup)
4. Add suffixes to files. (confg, jconfg, etc.)
5. Expand peer groups, etc.
6. Parse configs into mysql database. (Generate Intermediate Format)
7. Run verifier, produce reports.
8. Quit
EOM

print "Option: ";
    $option = <STDIN>;

    return $option;
}

while (1) {

    my $option = &print_menu();


    if ($option == $options{'db_if'}) {
	# BGP db
        system("echo 'drop database config_if' | mysql --user=$db_user --password=$db_pass");
        system("echo 'create database config_if' | mysql --user=$db_user --password=$db_pass");
        system("cat ../../../db-schema/config_if.sql | mysql --user=$db_user --password=$db_pass config_if");
    }

    if ($option == $options{'db_isis'}) {
        # IGP db
        system("echo 'drop database config_isis' | mysql --user=$db_user --password=$db_pass");
        system("echo 'create database config_isis' | mysql --user=$db_user --password=$db_pass");
        system("cat ../../../db-schema/config_isis.sql | mysql --user=$db_user --password=$db_pass config_isis");
    }

    if ($option == $options{'db_ospf'}) {
        # IGP db
        system("echo 'drop database config_ospf' | mysql --user=$db_user --password=$db_pass");
        system("echo 'create database config_ospf' | mysql --user=$db_user --password=$db_pass");
        system("cat ../../../db-schema/config_ospf.sql | mysql --user=$db_user --password=$db_pass config_ospf");
    }

    if ($option == $options{'suffix'}) {
	printf "Enter config directory: ";
	my $dir = <STDIN>;
	system("./rename_files.pl $dir");
    }

    if ($option == $options{'preprocess'}) {
	printf "Enter config directory: ";
	my $dir = <STDIN>;
	system("./riftrans_all.pl $dir");
	chomp($dir);
	printf "Output is in $dir/trans/\n";
    }

    if ($option == $options{'parse'}) {

	my $def;
	chomp($last_entry);
	if (length($last_entry)>1) {
	    $def = " [$last_entry]";
	}

	printf "Enter config directory$def: ";
	my $dir = <STDIN>;
	if (length($dir)<2) {
	    $dir = $last_entry;
	} else {
	    $last_entry = $dir;
	}

	system("perl ../config-convert/gen_intermediate.pl --db --configdir=$dir");
    }

    if ($option == $options{'verify'}) {
	printf "Enter directory for .html summary, or [enter] for STDOUT: ";
	my $dir = <STDIN>;
	chomp($dir);

	my $opt = "";
	if (!($dir eq '')) {
	    $opt = "--files=$dir";
	    
	    # make the rcc index.html page
	    &make_rcc_index($dir);
	}
	# BGP tests
	system("../queries/scripts/test_all.pl $opt");
	# IS-IS tests
	system("../queries/scripts/test_all_isis.pl $opt");
	# OSPF tests
	system("../queries/scripts/test_all_ospf.pl $opt");

	# Network graphs
	system("../queries/scripts/plot_network.pl $opt --format=jpg --bgp");
	system("../queries/scripts/plot_network.pl $opt --format=jpg --igp");
	system("../queries/scripts/plot_network.pl $opt --format=ps --bgp");
	system("../queries/scripts/plot_network.pl $opt --format=ps --igp");

	# Generate HTML Summaries
	if (!($dir eq '')) {
	    system("../queries/scripts/gen_bgp_html.pl --basedir=$dir");
	    system("../queries/scripts/gen_igp_html.pl --basedir=$dir");
	}
       
    }

    if ($option == $options{'quit'}) {
	exit(0);
    }

}
