#!/usr/bin/perl

BEGIN {
    push(@INC, "../modules/ospf");
    
    # these are for the "menu.pl" script, which
    # requires different relative paths

    push(@INC, "../queries/modules/");
    push(@INC, "../queries/modules/ospf");
    push(@INC, "../../lib/");
}

use mtu_mismatch;
use authentication;
use area;
use links;
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
	open(F, ">$basedir/index_ospf.html");
	
	print F "<html><h3>rcc OSPF Error Summary</h3><center><table width=90% border=0>\n";

    } else {
	return;
    }

    my %title = (
		 );

    my %contents = (
		 );



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

&redirect("ospf-mtu-mismatch.txt");
&header("\n\nMTU Mismatch Check\n=====================\n");
my $mtu_mismatch = new mtu_mismatch;
$mtu_mismatch->check_mtu_mismatch($q);

&redirect("ospf-authentication.txt");
&header("\n\nAuthentication Check\n=====================\n");
my $authentication = new authentication;
$authentication->check_auth_type($q);
$authentication->check_auth_key($q);

&redirect("ospf-area.txt");
&header("\n\nArea Configuration Checks\n=====================\n");
my $area = new area;
$area->check_backbone_existence($q);
$area->check_stub($q);
$area->check_area_addresses($q);
$area->check_backbone_connectivity($q);

&redirect("ospf-links.txt");
&header("\n\nLink Checks\n=====================\n");
my $links = new links;
$links->check_dangling_links($q);

&redirect("ospf-routes.txt");
&header("\n\nRoute Checks\n=====================\n");
my $routes = new routes;
$routes->build_shortest_paths_table($q);

&make_index();
