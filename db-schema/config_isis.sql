-- MySQL dump 9.11
--
-- Host: localhost    Database: config_isis
-- ------------------------------------------------------
-- Server version	4.0.23_Debian-3ubuntu2-log

--
-- Table structure for table `adjacencies`
--

CREATE TABLE `adjacencies` (
  `origin_router_name` varchar(40) default NULL,
  `dest_router_name` varchar(40) default NULL,
  `level1_metric` int(11) default NULL,
  `level2_metric` int(11) default NULL,
  `ipv4_subnet_address` varchar(20) default NULL,
  `origin_interface` varchar(20) default NULL,
  `level1_adjacency` bit(1) default NULL,
  `level2_adjacency` bit(1) default NULL,
  `inter_area` bit(1) default NULL
) TYPE=MyISAM;

--
-- Dumping data for table `adjacencies`
--


--
-- Table structure for table `mesh_groups`
--

CREATE TABLE `mesh_groups` (
  `mesh_group_number` int(11) default NULL,
  `router_name` varchar(30) default NULL,
  `interface_name` varchar(20) default NULL
) TYPE=MyISAM;

--
-- Dumping data for table `mesh_groups`
--


--
-- Table structure for table `router_info`
--

CREATE TABLE `router_info` (
  `router_name` varchar(30) default NULL,
  `iso_address` varchar(60) default NULL,
  `ipv4_address` varchar(20) default NULL,
  `ipv6_address` varchar(44) default NULL,
  `area_address` varchar(8) default NULL,
  `auth_type` varchar(10) default NULL,
  `auth_key` varchar(40) default NULL
) TYPE=MyISAM;

--
-- Dumping data for table `router_info`
--


--
-- Table structure for table `router_interfaces`
--

CREATE TABLE `router_interfaces` (
  `router_name` varchar(30) default NULL,
  `interface_name` varchar(20) default NULL,
  `ipv4_address` varchar(20) default NULL,
  `ipv6_address` varchar(44) default NULL,
  `iso_address` varchar(60) default NULL,
  `level1_routing` bit(1) default NULL,
  `level2_routing` bit(1) default NULL,
  `level1_metric` int(11) default NULL,
  `level2_metric` int(11) default NULL,
  `mtu_ipv4` int(11) default NULL,
  `mtu_ipv6` int(11) default NULL,
  `mtu_iso` int(11) default NULL
) TYPE=MyISAM;

--
-- Dumping data for table `router_interfaces`
--

--
-- Table structure for table `routes`
--

CREATE TABLE `routes` (
  `origin` varchar(30) default NULL,
  `destination` varchar(30) default NULL,
  `cost` varchar(40) default NULL
) TYPE=MyISAM;

--
-- Dumping data for table `routes`
--
