#!/usr/bin/perl


package ConfigUtils;

use strict;
use NetAddr::IP;

require Exporter;
use vars(qw($utils @ISA @EXPORT));
@ISA = ('Exporter');
@EXPORT = (qw ($utils));

$utils = {
    'contains' => \&contains,
};

sub contains {
    my ($net, $ip_) = @_;
    $net =~ s/\@//g;
    $ip_ =~ s/\@//g;

    my ($net, $mask) = split ('/', $net);
    my $nm = new NetAddr::IP($net, $mask);
    my $ip = new NetAddr::IP($ip_);

    return $nm->contains($ip);
}
