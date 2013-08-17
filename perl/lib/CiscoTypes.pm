#!/usr/bin/perl

package CiscoTypes;

@ISA = ('Exporter');
@EXPORT = (qw ($rtr_name $addr_mask $asnum $intname $quad_mask),
	   qw ($loopback_regexp $ipaddr_regexp $bgp_scope $eos),
	   qw ($rm_scope $match_regexp $set_regexp $acl_regexp $nw_regexp),
	   qw ($nw_mask_regexp $ip_mask_regexp $ip_route_regexp $ip_acc_list_regexp),
	   qw ($pfx_list_regexp $com_list_regexp $acc_list_regexp $asp_list_regexp),
	   qw ($match_ip_regexp $interface_regexp),
	   qw ($ipv4_scope $acl_scope $acl_scope_default $acl_ext_scope),
	   qw ($match_ip_pfx_regexp $stop_words));

use vars (qw (@ISA @EXPORT $rtr_name $addr_mask $asnum $intname),
	  qw ($loopback_regexp $ipaddr_regexp $bgp_scope $eos),
	  qw ($rm_scope $match_regexp $set_regexp $acl_regexp $nw_regexp),
	  qw ($nw_mask_regexp $ip_mask_regexp $ip_route_regexp $ip_acc_list_regexp),
	  qw ($pfx_list_regexp $com_list_regexp $acc_list_regexp $asp_list_regexp),
	  qw ($match_ip_regexp $interface_regexp),
	  qw ($ipv4_scope $acl_scope $acl_scope_default $acl_ext_scope),
	  qw ($match_ip_pfx_regexp $stop_words));


######################################################################
# defs for the config FSM stuff

$rtr_name = '[\w\d\-\.]+';
$addr_mask = '@*\d+\.\d+\.\d+\.\d+@*';
$addr = '\d+\.\d+\.\d+\.\d+';
$asnum = '\d+';
$intname = '[\w\d\/]+';
$quad_mask = '\d+\.\d+\.\d+\.\d+';

######################################################################
# defs for the config flow stuff

$loopback_regexp = '^interface\s+Loopback\s*\d+';
$ipaddr_regexp = 'ip\s+address\s+(\d+\.\d+\.\d+\.\d+)';
$bgp_scope = 'router\s+bgp\s+(\d+)';
$ipv4_scope = 'address-family\s+ipv4\s*$';

$ip_route_regexp = 'ip\s+route\s+@*(\d+\.\d+\.\d+\.\d+)@*\s+@*(\d+\.\d+\.\d+\.\d+)@*';
$nw_mask_regexp = 'network\s+@*(\d+\.\d+\.\d+\.\d+)@*\s+mask\s+@*(\d+\.\d+\.\d+\.\d+)@*';
$ip_mask_regexp = 'ip\s+address\s+@*(\d+\.\d+\.\d+\.\d+)@*\s+@*(\d+\.\d+\.\d+\.\d+)@*';
$interface_regexp = '^interface\s+(\S+)';
$nw_regexp = 'network\s+@*(\d+\.\d+\.\d+\.\d+)@*';
$rm_scope = '^route-map\s+([\S\(\)]+)\s+';#\s+\d+';
$match_regexp = 'match\s+(\S+)\s+(\d+\s*\d*)';
$match_ip_regexp = 'match\s+ip\s+address\s+(\d+)';
$match_ip_pfx_regexp = 'match\s+ip\s+address\s+prefix-list\s+(\S+)';
$set_regexp = 'set\s+(\S+)\s+(.+)';


$pfx_list_regexp = 'ip prefix-list\s+(\S+)\s+.*?(permit|deny)\s+\@*(\d+\.\d+\.\d+\.\d+)\@*\/(\d+)';
$ip_acc_list_regexp = 'ip access-list\s+(standard|extended)\s+(\S+)';
$com_list_regexp = 'ip community-list\s+(\d+)\s+\S+\s+';
$acc_list_regexp = '^access-list\s+(\d+)';
$asp_list_regexp = 'ip as-path access-list\s+(\d+)';

$acl_scope = 'access-list\s+(\d+)\s+(permit|deny).*?@*(\d+\.\d+\.\d+\.\d+)(.*?)(\d+\.\d+\.\d+\.\d+)';
$acl_scope_default = 'access-list\s+(\d+)\s+(permit|deny).*?@*(\d+\.\d+\.\d+\.\d+)';
$acl_ext_scope = 'XXX*not*implemented*XXX';

$acl_regexp = "$pfx_list_regexp|$com_list_regexp|$acc_list_regexp|$asp_list_regexp|$ip_acc_list_regexp";


#$eos = '^!';
$eos = '^@STOP@';
$stop_words = "^interface|^router|^route-map|^ip| address\-family";

1;
