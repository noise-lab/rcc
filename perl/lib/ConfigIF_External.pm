#!/usr/bin/perl

package ConfigIF_External;

use Data::Dumper;
use strict;

use CiscoTypes;
use ConfigCommon;
use ConfigParse;
use ConfigDB;

require Exporter;
use vars(qw(@ISA @EXPORT $configdir @db_tables));
@ISA = ('Exporter');


######################################################################
# Constructor

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);

    $self->{bogon_table} = "bogon_list";
    $self->{bogon_list} = "../../conf/bogons.txt";
    $self->{dbh} = &dbhandle($config_if);

    return $self;
}



sub clean_db {
    my $self = shift;
    $self->{dbh}->do("delete from $self->{bogon_table}");
}

sub db_bogon_list { 
    
    my $self = shift;

    open(B, "$self->{bogon_list}") || die "can't open $self->{bogon_list}:$!\n";
    while (<B>) {
	if ($_ =~ /(\d+\.\d+\.\d+\.\d+)\/(\d+)/) {
	    my $ip = $1;
	    my $mask = $2;

	    my $ip_min = &inet_aton_($ip);
	    my $ip_max = $ip_min + 2**(32-$mask) - 1;

	    my $cmd = "insert into bogon_list values ('$ip_min', '$ip_max', '$mask')";
	    $self->{dbh}->do($cmd);
	}
    }

}

sub db_regexp_init {

    my $self = shift;

    my $cmd = "insert into $as_regexps values('0','')";
    $self->{dbh}->do($cmd);

    my $cmd = "insert into $comm_regexps values('0','')";
    $self->{dbh}->do($cmd);


}
