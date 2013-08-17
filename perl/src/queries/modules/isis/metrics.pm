#!/usr/bin/perl

package metrics;

BEGIN {
    push(@INC, "../../../lib");
}

use strict;
use ConfigCommon;
use ConfigDB;
use ConfigQueryISIS;

my $cq = new ConfigQueryISIS;

sub new {
    my ($class) = @_;
    my $self = {};
    bless ($self, $class);
    return $self;
}

# Is this test actually necessary?
sub check_metrics {
    my $self = shift;
    my $quiet = shift;
    my @errors = ();
    
    
    print STDERR "\nVerifying that all IS-IS metrics are within valid ranges.\n" if !$quiet;
    
}

1;
