package Path;

use strict;
use vars qw($VERSION @ISA);
use Heap::Elem;

require Exporter;

@ISA = qw(Exporter Heap::Elem);



sub new {
    my ($class) = @_;
    $class = ref($class) || $class;
    my $self = {};
    bless($self, $class);

    $self->{nodes} = ();   # nodes in the path
    $self->{cost} = 0;    # total cost of the path

    return $self;
}

# add node to end of the path
sub add_node {
    my $self = shift;
    my $node = shift;
    my $cost = shift;

    push(@{$self->{nodes}},$node);
    $self->{cost} = $self->{cost} + $cost;
}

# # get copy of the path
# sub copy_path {
#     my $self = shift;

#     my $new_path = $self->new();
#     $new_path->{nodes} = @{$self->{nodes}};
#     $new_path->{cost} = $self->{cost}

#     return $new_path;
# }

# get cost
sub get_cost {
    my $self = shift;
    return $self->{cost};
}

# compare two paths
sub cmp {
    my $self = shift;
    my $other = shift;

    if ($self->{cost} < $other->{cost}) {
	# lower cost path has high priority, should go higher on the heap
	return -1;
    }
    elsif ($self->{cost} == $other->{cost}) {
	return 0;
    }
    else {
	return 1;
    }
}

1;
