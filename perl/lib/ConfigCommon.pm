#!/usr/bin/perl

package ConfigCommon;

require Exporter;
use vars(qw(@ISA @EXPORT $config_basedir $configdir $rifprog $dbconfig),
	 qw($db_host $db_port $db_user $db_pass),
	 qw($grep $dot $diff $tmpdir $nodestyle),
	 qw($debug),
	 qw(%def_types @def_names));

@ISA = ('Exporter');

@EXPORT = (qw($config_basedir $configdir $rifprog $dbconfig),
	   qw($db_host $db_port $db_user $db_pass),
	   qw($grep $dot $diff $tmpdir $nodestyle),
	   qw($debug &set_debug &set_configdir &inet_aton_ &inet_ntoa_),
	   qw(%def_types @def_names));


######################################################################
# *** Fill in local specifics for these variables ****

# the location of your configuration files
# note that some scripts require the "trans/" subdir below this directory
# as well (see manual)

$config_basedir = "/home/feamster/.bgp-configs/";
$configdir =  sprintf("%s/trans", $config_basedir);

# location of 'grep'
$grep = "/bin/grep";

# location of 'dot' (graphviz) executable
$dot = "/usr/bin/dot";
$nodestyle = "[style=filled color=lightblue]";  # style of routers in dot graph

# where temporary/scratch output files should be written (e.g., /tmp)
$tmpdir = "/tmp";

# diff location (used for diffing route maps)
$diff = "/usr/bin/diff";


##############################
# database details
$db_host = "localhost";             # machine that runs mysql (or other DB)
$db_port = 3306;                    # port on which mysql is running
$db_user = "feamster";              # username
$db_pass = "";                      # password
##############################

######################################################################

%def_types = ('com' => 1,
	      'asp' => 2,
	      'acc' => 3,
	      'acl' => 4);

@def_names = ('',
	      'community-list',
	      'as-path list',
	      'ip access-list',
	      'prefix/distribute list');


$rifprog = "../src/riftrans.pl";

sub set_debug {
    $debug = 1;
}

sub set_configdir {
    my $dir = shift;
    $configdir = $dir;
}

######################################################################

sub inet_aton_ {
    my $lb = shift;
    my $lbnum = unpack("N", pack("C4", split(/\./,$lb)));
    return $lbnum;
}

sub inet_ntoa_ {
    my $lbnum = shift;
    my $lb = join('.', unpack("C4", pack("N",$lbnum)));
    return $lb;
}


1;
