-- MySQL dump 9.11
--
-- Host: localhost    Database: config_ospf
-- ------------------------------------------------------
-- Server version	4.0.23_Debian-3ubuntu2-log

--
-- Table structure for table `adjacencies`
--

CREATE TABLE `adjacencies` (
  `origin_router_name` varchar(40) default NULL,
  `dest_router_name` varchar(40) default NULL,
  `metric` int(11) default NULL,
  `origin_interface` varchar(20) default NULL,
  `ipv4_subnet_address` varchar(20) default NULL,
  `origin_area` varchar(20) default NULL,
  `dest_area` varchar(20) default NULL
) TYPE=MyISAM;

--
-- Dumping data for table `adjacencies`
--

--
-- Table structure for table `area_info`
--

CREATE TABLE `area_info` (
  `area` varchar(30) default NULL,
  `stub` bit(1) default NULL,
  `nssa` bit(1) default NULL,
  `auth_type` varchar(10) default NULL
) TYPE=MyISAM;

--
-- Dumping data for table `area_info`
--

--
-- Table structure for table `router_info`
--

CREATE TABLE `router_info` (
  `router_name` varchar(30) default NULL,
  `ipv4_address` varchar(20) default NULL,
  `ipv6_address` varchar(44) default NULL
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
  `ipv6_address` varchar(20) default NULL,
  `area` varchar(20) default NULL,
  `metric` int(11) default NULL,
  `enabled` int(11) default NULL,
  `mtu_ipv4` int(11) default NULL,
  `mtu_ipv6` int(11) default NULL,
  `auth_type` varchar(10) default NULL,
  `auth_key` varchar(10) default NULL
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

