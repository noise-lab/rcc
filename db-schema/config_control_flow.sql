-- MySQL dump 8.22
--
-- Host: localhost    Database: config_control_flow
---------------------------------------------------------
-- Server version	3.23.56

--
-- Table structure for table 'route_maps'
--

CREATE TABLE route_maps (
  idx smallint(5) unsigned default NULL,
  rep text
) TYPE=MyISAM;

--
-- Table structure for table 'routers'
--

CREATE TABLE routers (
  router varchar(40) default NULL,
  loopback int(10) unsigned default NULL,
  has_ebgp tinyint(1) default NULL,
  is_ebgp tinyint(1) default NULL
) TYPE=MyISAM;

--
-- Table structure for table 'sessions'
--

CREATE TABLE sessions (
  router varchar(40) default NULL,
  neighbor varchar(40) default NULL,
  neighbor_asn smallint(5) unsigned default NULL,
  import tinyint(1) default NULL,
  route_map smallint(5) unsigned default NULL
) TYPE=MyISAM;

