#!/usr/bin/perl

package ConfigQuery;

use Data::Dumper;
use strict;

use ConfigDB;
use ConfigCommon;

require Exporter;
use vars(qw(@ISA @EXPORT $config_if));
@ISA = ('Exporter');


######################################################################

sub new {
    my ($class, $db) = @_;
    my $self = {};
    bless($self, $class);

    $self->{dbh} = &dbhandle($config_if);

    if (defined($db)) {
	$self->set_db($db);
    }
    return $self;
}

sub set_db {
    my $self = shift;
    my ($db) = @_;

    $self->{dbh} = &dbhandle($db);

}

sub query {
    my $self = shift;
    my ($q) = @_;

    print STDERR "$q\n" if $debug;

    my $sth = $self->{dbh}->prepare($q);
    $sth->execute;

    return $sth;
}

sub cmd {
    my $self = shift;
    my ($q) = @_;

    $self->{dbh}->do($q);
}
