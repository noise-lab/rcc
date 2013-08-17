#!/usr/bin/perl

BEGIN {
    push(@INC, "../modules/isis");
    
    # these are for the "menu.pl" script, which
    # requires different relative paths

    push(@INC, "../queries/modules/");
    push(@INC, "../queries/modules/isis");
    push(@INC, "../../lib/");
}

use dup_addrs;
use adjacency;
use mtu_mismatch;
use authentication;
use routes;

use ConfigCommon;
use Getopt::Long;
my %options;
my $q;

GetOptions(\%options, "quiet", "summary", "files=s");
if (defined($options{'quiet'})) {
    $q = 1;
} elsif (defined($options{'summary'})) {
    $q = 2;
}

if (defined($options{'files'})) {
    system("mkdir -p $options{'files'}");
}


######################################################################

sub redirect {

    my ($filename, $append) = @_;
    my $d = ">";
    if ($append) {
	$d = ">>";
    }
    if (defined($options{'files'})) {
	my $basedir = $options{'files'};
	open(F, "$d $basedir/$filename");
	*STDOUT = *F;
    }

}

sub header {
    my ($header) = @_;

    if (!defined($options{'files'})) {
	printf "$header";
    }

}


sub make_index {

    my $basedir;
    if (defined($options{'files'})) {
	$basedir = $options{'files'};
	open(F, ">$basedir/index_isis.html");
	
	print F "<html><h3>rcc ISIS Error Summary</h3><center><table width=90% border=0>\n";

    } else {
	return;
    }

    my %title = (
		 'isis-duplicate-address' => 'Duplicate Address Check',
		 'isis-adjacency' => 'Adjacency Checks',
		 'isis-mtu-mismatch' => 'MTU Mismatch Checks',
		 'isis-authentication' => 'Authentication Checks',
		 'isis-routes' => 'Route Checks');

    my %contents = (
		    'isis-duplicate-address' => 'Check for duplicate network IDs',
		    'isis-adjacency' => 'Check for IS-IS adjacency misconfigurations',
		    'isis-mtu-mismatch' => 'Check that MTUs are not mismatched over adjacencies',
		    'isis-authentication' => 'Checks authentication type and key is consistent',
		    'isis-routes' => 'FIXME');



    my @files = (keys %title);

    foreach my $file (@files) {
	my $filename = sprintf("%s/%s.txt", $basedir, $file);
	my $filename_rel = sprintf("%s.txt", $file);

	my @stats = stat($filename);
	my $size = $stats[7];
	next if (!$size);

	printf F ("<tr><td><a href=%s>%s</a></td><td>%s</td></tr>\n",
		  $filename_rel,
		  $title{$file}, $contents{$file});

    }

    close(F);

}

######################################################################

&redirect("isis-duplicate-address.txt");
&header("\n\nDuplicate Address Check\n=====================\n");
my $dup_addrs = new dup_addrs;
$dup_addrs->check_duplicate_address($q);

&redirect("isis-adjacency.txt");
&header("\n\nAdjacency Check\n=====================\n");
my $adjacency = new adjacency;
$adjacency->check_dangling_adjacencies($q);
$adjacency->check_adjacency_levels($q);
$adjacency->check_area_adjacencies($q);

&redirect("isis-mtu-mismatch.txt");
&header("\n\nMTU Mismatch Check\n=====================\n");
my $mtu_mismatch = new mtu_mismatch;
$mtu_mismatch->check_mtu_mismatch($q);

&redirect("isis-authentication.txt");
&header("\n\nAuthentication Check\n=====================\n");
my $authentication = new authentication;
$authentication->check_auth_type($q);
$authentication->check_auth_key($q);

&redirect("isis-routes.txt");
&header("\n\nRoutes Check\n=====================\n");
my $routes = new routes;
$routes->build_shortest_paths_table($q);

&make_index();
