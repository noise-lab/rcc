package Path;

use strict;
use vars qw($VERSION @ISA);
use Heap::Elem;

require Exporter;

@ISA = qw(Exporter Heap::Elem);

$VERSION = 0.01;

=head1 NAME

Graph::HeapElem - internal use only

=head1 SYNOPSIS

=head1 DESCRIPTION

B<INTERNAL USE ONLY> for the Graph module

=head1 COPYRIGHT

Copyright 1999, O'Reilly & Associates.

This code is distributed under the same copyright terms as Perl itself.

=cut

# Preloaded methods go here.

sub new {
    my $class = shift;
    $class = ref($class) || $class;

    # two slot array, 0 for the vertex, 1 for use by Heap
    my $self = [ [ @_ ], undef ];

    return bless $self, $class;
}

# get or set vertex slot
sub vertex {
    my $self = shift;
    @_ ? ($self->[0]->[0] = shift) : $self->[0]->[0];
}

# get or set weight slot
sub weight {
    my $self = shift;
    @_ ?
      ($self->[0]->[1]->{ $self->vertex } = shift) :
       $self->[0]->[1]->{ $self->vertex };
}

# get or set parent slot
sub parent {
    my $self = shift;
    @_ ?
      ($self->[0]->[2]->{ $self->vertex } = shift) :
       $self->[0]->[2]->{ $self->vertex };
}

# get or set heap slot
sub heap {
    my $self = shift;
    @_ ? ($self->[1] = shift) : $self->[1];
}

# compare two vertices
sub cmp {
    my ($u, $v) = @_;

    my ($uw, $vw) = ( $u->weight, $v->weight );

    if ( defined $uw ) {
        return defined $vw ? $uw <=> $vw : -1;
    } else {
        return defined $vw ? 1 : 0;
    }
}

1;
