#!/usr/bin/perl

package JuniperTypes;

@ISA = ('Exporter');
@EXPORT = (qw($addr $rtr_name $eos),
	   qw($loopback_regexp $bgp_regexp),
       qw($static_regexp $static_discard $static_stanza_regexp $static_nexthop));

use vars (qw (@ISA @EXPORT $asnum $intname),
	  qw ($addr $rtr_name $eos),
	  qw ($loopback_regexp $bgp_regexp));


######################################################################
# defs for the config flow stuff

$addr = '\d+\.\d+\.\d+\.\d+';
$rtr_name = '[\w\d\-\.]+';

$loopback_regexp = '\s+lo0\s+\{';
$bgp_regexp = '\s+bgp\s+\{';
$static_regexp = 'route\s+(\d+\.\d+\.\d+\.\d+)\/(\d+)\s+next-hop\s+(\d+\.\d+\.\d+\.\d+)';
$static_discard = 'route\s+(\d+\.\d+\.\d+\.\d+)\/(\d+)\s+discard';
$static_stanza_regexp = 'route\s+(\d+\.\d+\.\d+\.\d+)\/(\d+)\s+\{'; 
$static_nexthop = 'next-hop\s+(\d+\.\d+\.\d+\.\d+)';
$eos = '}';

1;
