#!/usr/bin/perl

package SSSP_Dijkstra;

use strict;
use HeapElement;
use ConfigDB;

require Exporter;
use vars(qw(@ISA @EXPORT @isis_db_tables @ospf_db_tables));
@ISA = ('Exporter');

my $debug = 1;

######################################################################
# Constructor

sub new {

    my ($class, $dbh) = @_;
    my $self = {};
    bless($self, $class);

    return $self;
}

# SSSP_Dijkstra_OSPF

sub SSSP_Dijkstra_OSPF {
    my $self = shift;
    my $origin = shift;

    use Heap::Fibonacci;

    # This algorithm takes a origin node and searches the graph to
    # produce the shortest route between the origin and all other
    # reachable nodes in the graph.

    # In this algorithm, nodes are simply represented by strings.
    # Paths are simply arrays of nodes, with the start node at index 0
    # and the end node at index -1.  What the Fib. Heap stores is a
    # HeapElement, which contains a Path, but also other information
    # such as the cost of the path.

    # pqueue is a Fib Heap being used as a priority queue.  It contains
    # HeapElements which are paths.
    my $pqueue = Heap::Fibonacci->new;

    # in_pqueue keeps track of the nodes that are the destinations of
    # the paths on the priority queue.  finished keeps track of which
    # nodes for which we already have the shortest paths.
    my ( %in_pqueue, %finished);

    my $startpath = HeapElement->new();
    $startpath->add_node($origin,0);

    # add this to the queue
    $pqueue->add( $startpath );
    $in_pqueue->{ $origin } = $origin;


    # Walk the edges at the current BFS front
    # in the order of their increasing weight.
    while ( defined $pqueue->minimum ) {
        my $upath = $pqueue->extract_minimum;
	my $u = @{$upath->{nodes}}[-1];
        delete $in_pqueue{ $u };
	
	# iterate over children of $u

	# First, check what kind of area $u is in.  This dictates
	# which other nodes $u can reach.

	# first, get these children from the MySQL database
	my $q = "SELECT dest_router_name, metric, origin_area, dest_area FROM $adjacencies WHERE origin_router_name = '$u',";
	my $sth = $dbh->query($q);

	while (my ($child, $metric, $origin_area, $dest_area) = $sth->fetchrow_array()) {
	    # check that 

	    # need code to copy paths, check if this works
	    my $childpath = $upath;
	    $childpath->add_node($child, $metric);

	    if (!defined($finished{$child} && !defined($in_pqueue{$child}))) {
		# put $childpath in the p. queue
		$pqueue->add{$childpath};
		$in_pqueue->{$child} = $child;
	    }
	    
	}

	# We now have a path to $u, so we should insert it into the finished set
	$finished{$child} = $child;
	# insert the path information into the MYSQL database
	my $cmd = "INSERT INTO $routes VALUES ('$origin', '$u', '$upath->get_cost()')";
	$dbh->do($cmd);

	
    }

    # execution reaches here if the pqueue becomes empty    

}

# SSSP_Dijkstra_ISIS

sub SSSP_Dijkstra_ISIS {
    my $self = shift;
    my $origin = shift;

    use Heap::Fibonacci;

    # This algorithm takes a origin node and searches the graph to
    # produce the shortest route between the origin and all other
    # reachable nodes in the graph.

    # In this algorithm, nodes are simply represented by strings.
    # Paths are simply arrays of nodes, with the start node at index 0
    # and the end node at index -1.  What the Fib. Heap stores is a
    # HeapElement, which contains a Path, but also other information
    # such as the cost of the path.

    # In this (IS-IS) version, the paths depends on which destination
    # is currently being sought, so we will need to run Dijkstra
    # independently for each possible destination in the graph for
    # each possible origin in the graph.

    # First, get a list of all possible destinations for this origin.
    my $destinations = $dbh->selectcol_arrayref("SELECT router_name FROM $router_info WHERE $router_name != '$origin'");
    
    # Loop over the list of destinations
    foreach my $dest (@{$destinations}) {

	# get destination's ISO area address
	my $area_addrs = $dbh->selectcol_arrayref("SELECT area_address FROM $router_info WHERE router_name = '$dest'");
	my $dest_area_addr = $area_addrs[0];


	# pqueue is a Fib Heap being used as a priority queue.  It contains
	# HeapElements which are paths.
	my $pqueue = Heap::Fibonacci->new;
	
	# in_pqueue keeps track of the nodes that are the destinations of
	# the paths on the priority queue.  finished keeps track of which
	# nodes for which we already have the shortest paths.
	my ( %in_pqueue, %finished);
	
	my $startpath = HeapElement->new();
	$startpath->add_node($origin,0);

	# add this to the queue
	$pqueue->add( $startpath );
	$in_pqueue->{ $origin } = $origin;
	
	
	# Walk the edges at the current BFS front
	# in the order of their increasing weight.
	while ( defined $pqueue->minimum ) {
	    my $upath = $pqueue->extract_minimum;
	    my $u = @{$upath->{nodes}}[-1];
	    delete $in_pqueue{ $u };

	    # Check if $u is the destination
	    if ($u eq $dest) {
		# insert the path information into the MYSQL database
		my $cmd = "INSERT INTO $routes VALUES ('$origin', '$u', '$upath->get_cost()')";
		$dbh->do($cmd);
	    }
	    
	    # otherwise, iterate over children of $u
	    	    
	    # first, get these children from the MySQL database
	    my $q1 = "SELECT dest_router_name, level1_metric, level2_metric, level1_adjacency, level2_adjacency FROM $adjacencies WHERE origin_router_name = '$u',";
	    my $sth = $dbh->query($q1);
	    
	    while (my ($child, $lvl1_metric, $lvl2_metric, $lvl1_adjacency, $lvl2_adjacency) = $sth->fetchrow_array()) {
		
		# Check what ISO area the child is in, and whether this
		# child is configured for level 1 routing, level 2 routing
		# or both.
		
		# If the child is only configured for level 1 routing, but
		# is in the same area as the goal router, then the child
		# would advertise a route to the goal, so we can go
		# through this child. Otherwise, we cannot go through this
		# child unless IS-IS is configured to leak routes into the
		# level 1 domains.
		
		# Get child's area address
		my $area_addrs = $dbh->selectrow_array("SELECT area_address FROM $router_info WHERE router_name = '$child'");
		my $child_area_addr = $area_addrs[0];

		# determine if routes are leaked
		# FIXME
		my $are_routes_leaked = 0;

		if (!($child_area_addr eq $dest_area_addr) && !$area_routes_leaked) {
		    # Skip this child and go on to the next one
		    next;
		}
		
		
		# need code to copy paths, check if this works
		my $childpath = $upath;
		$childpath->add_node($child, $metric);

		if (!defined($finished{$child} && !defined($in_pqueue{$child}))) {
		    # put $childpath in the p. queue
		    $pqueue->add{$childpath};
		    $in_pqueue->{$child} = $child;
		}
	    
	    }
	    
	    # We now have a path to $u, so we should insert it into the finished set
	    $finished{$child} = $child;
	}
	

	# execution reaches here if the pqueue becomes empty, so there
	# is no path to the selected destination
	
    }

    # Finished looping through destinations
}


1;
