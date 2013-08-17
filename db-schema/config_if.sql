-- MySQL dump 8.23
--
-- Host: localhost    Database: config_if
---------------------------------------------------------
-- Server version	3.23.58

--
-- Table structure for table `as_regexps`
--

CREATE TABLE as_regexps (
  as_regexp_num int(10) unsigned default NULL,
  as_regexp text
) TYPE=MyISAM;

--
-- Table structure for table `bogon_list`
--

CREATE TABLE bogon_list (
  ip_min int(10) unsigned default NULL,
  ip_max int(10) unsigned default NULL,
  mask smallint(6) default NULL
) TYPE=MyISAM;

--
-- Table structure for table `comm_regexps`
--

CREATE TABLE comm_regexps (
  comm_regexp_num int(10) unsigned default NULL,
  comm_regexp text
) TYPE=MyISAM;

--
-- Table structure for table `communities`
--

CREATE TABLE communities (
  community_num int(10) unsigned default NULL,
  community varchar(100) default NULL
) TYPE=MyISAM;

--
-- Table structure for table `networks`
--

CREATE TABLE networks (
  router_name varchar(40) default NULL,
  prefix int(10) unsigned default NULL,
  mask int(10) unsigned default NULL,
  rmap_id smallint(5) unsigned default NULL
) TYPE=MyISAM;

--
-- Table structure for table `parse_errors`
--

CREATE TABLE parse_errors (
  router_name varchar(40) default NULL,
  route_map_name varchar(40) default NULL,
  def_type smallint(5) unsigned default NULL,
  def_num int(10) unsigned default NULL
) TYPE=MyISAM;

--
-- Table structure for table `prefix_acls`
--

CREATE TABLE prefix_acls (
  num smallint(5) unsigned default NULL,
  clause_num mediumint(8) unsigned default NULL,
  ip_min int(10) unsigned default NULL,
  ip_max int(10) unsigned default NULL,
  mask_min smallint(5) unsigned default NULL,
  mask_max smallint(5) unsigned default NULL,
  permit tinyint(1) default NULL,
  KEY rtrpfxidx (ip_min),
  KEY numidx (num)
) TYPE=MyISAM;

--
-- Table structure for table `route_maps`
--

CREATE TABLE route_maps (
  rmap_id int(10) unsigned default NULL,
  clause_num smallint(5) unsigned default NULL,
  pfxnum int(10) unsigned default NULL,
  permit tinyint(1) default '1',
  as_regexp_num int(10) unsigned default NULL,
  comm_regexp_num int(10) unsigned default NULL,
  localpref smallint(5) unsigned default NULL,
  med smallint(5) unsigned default NULL,
  origin char(1) default NULL,
  community_num int(10) unsigned default NULL,
  prepend varchar(30) default NULL,
  nh_self tinyint(1) default NULL
) TYPE=MyISAM;

--
-- Table structure for table `router_global`
--

CREATE TABLE router_global (
  router_name varchar(40) default NULL,
  vendor smallint(5) unsigned default NULL,
  bgp tinyint(1) default NULL,
  asn smallint(5) unsigned default NULL,
  no_sync tinyint(1) default NULL,
  deterministic_med tinyint(1) default NULL,
  compare_routerid tinyint(1) default NULL,
  routerid int(10) unsigned default NULL,
  clusterid int(10) unsigned default NULL,
  KEY rtrnameidx (router_name)
) TYPE=MyISAM;

--
-- Table structure for table `router_interfaces`
--

CREATE TABLE router_interfaces (
  router_name varchar(40) default NULL,
  int_name varchar(40) default NULL,
  address int(10) unsigned default NULL,
  ip_min int(10) unsigned default NULL,
  ip_max int(10) unsigned default NULL,
  KEY ipidx (ip_min)
) TYPE=MyISAM;

--
-- Table structure for table `router_loopbacks`
--

CREATE TABLE router_loopbacks (
  router_name varchar(40) default NULL,
  loopback int(10) unsigned default NULL
) TYPE=MyISAM;

--
-- Table structure for table `router_sessions`
--

CREATE TABLE router_sessions (
  router_name varchar(40) default NULL,
  session_id int(10) unsigned default NULL
) TYPE=MyISAM;

--
-- Table structure for table `routes`
--

CREATE TABLE routes (
  router_name varchar(40) default NULL,
  prefix int(10) unsigned default NULL,
  mask int(10) unsigned default NULL,
  KEY pfxidx (prefix)
) TYPE=MyISAM;

--
-- Table structure for table `sessions`
--

CREATE TABLE sessions (
  router_name varchar(40) default NULL,
  session_id int(10) unsigned default NULL,
  neighbor_ip int(10) unsigned default NULL,
  rr_client tinyint(1) default NULL,
  local_asn smallint(5) unsigned default NULL,
  asn smallint(5) unsigned default NULL,
  import_rm int(10) unsigned default NULL,
  export_rm int(10) unsigned default NULL,
  import_acl int(10) unsigned default NULL,
  export_acl int(10) unsigned default NULL,
  ebgp tinyint(1) default '0',
  clusterid int(10) unsigned default NULL,
  nh_self tinyint(1) default '0',
  send_comm tinyint(1) default NULL,
  remove_priv tinyint(1) default NULL,
  up tinyint(1) default NULL,
  KEY asnidx (asn),
  KEY rtridx (router_name)
) TYPE=MyISAM;

--
-- Table structure for table `sessions_shutdown`
--

CREATE TABLE sessions_shutdown (
  router_name varchar(40) default NULL,
  session_id int(10) unsigned default NULL,
  neighbor_ip int(10) unsigned default NULL,
  rr_client tinyint(1) default NULL,
  local_asn smallint(5) unsigned default NULL,
  asn smallint(5) unsigned default NULL,
  import_rm int(10) unsigned default NULL,
  export_rm int(10) unsigned default NULL,
  import_acl int(10) unsigned default NULL,
  export_acl int(10) unsigned default NULL,
  ebgp tinyint(1) default '0',
  clusterid int(10) unsigned default NULL,
  nh_self tinyint(1) default '0',
  send_comm tinyint(1) default NULL,
  remove_priv tinyint(1) default NULL,
  up tinyint(1) default NULL,
  KEY asnidx (asn),
  KEY rtridx (router_name)
) TYPE=MyISAM;

