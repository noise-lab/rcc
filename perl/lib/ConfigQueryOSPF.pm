#!/usr/bin/perl

package ConfigQueryOSPF;

use Data::Dumper;
use strict;

use ConfigDB;
use ConfigCommon;

require Exporter;
use vars(qw(@ISA @EXPORT $config_ospf));
@ISA = ('Exporter');


######################################################################

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);

    $self->{dbh} = &dbhandle($config_ospf);

    return $self;
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
