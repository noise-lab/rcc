#!/usr/bin/perl

package ConfigFSM;
use strict;
use ConfigCommon;
use ConfigParse;
use ConfigUtils;
use Data::Dumper;


######################################################################
# Constructor 

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);
    
    $self->{rslots_};            # regular expressions indicating type
    $self->{slots_filled};       # indicates specific variable bindings
    &reset_pf();

    return $self;
}

######################################################################

sub parse_constraints {
    my $self = shift;
    my $rexp = shift;
    
    my @constraints;

    if ($$rexp =~ /\<(.*)\>/) {
	push(@constraints, $1);
	$$rexp =~ s/\<.*\>//g;
    }

    return \@constraints;
}

sub apply_constraints {
    my $self = shift;
    my $constraint = shift;
    my $rbindings = shift;

    my @good_bindings;

    foreach my $rbind_hash (@$rbindings) {
	# let's test whether this set of bindings satisfies
	# the specified constraints

	my $tconstraint = $constraint;

	foreach my $key (keys %$rbind_hash) {
	    $tconstraint =~ s/$key/$rbind_hash->{$key}/g;
	}

	print STDERR "applying <$tconstraint> to list of bindings\n" if $debug;	
	if ($tconstraint =~ /(\S+)\((.*)\)/) {
	    my @cargs;

	    my ($cmd, $args) = ($1, $2);
	    foreach my $arg (split(',', $args)) {
		$arg =~ s/\s+//g;
		push (@cargs, $arg);
	    }
	    my $sr = $utils->{$cmd};
	    my $res = &$sr(@cargs);

	    if ($res) {
		push(@good_bindings, $rbind_hash);
	    }
	}
    }
    return \@good_bindings;
}

######################################################################

sub reset_pf {
    my $self = shift;
    $self->{pass} = 0;
    $self->{fail} = 0;
}


sub reset_bindings {
    my $self = shift;
    my $rbind = shift;

    print STDERR "RESETTING BINDINGS\n" if $debug;
    $self->unbind_all_slots();
    foreach my $slot (keys %{$rbind}) {
	print STDERR "$slot => $rbind->{$slot}\n" if $debug;
	$self->bind_slot($slot, $rbind->{$slot});
    }
}

sub print_bindings {
    my $self = shift; 
    foreach my $slot (keys %{$self->{slots_filled}}) {
	print STDERR "$slot => $self->{slots_filled}->{$slot}\n";
    }
}


######################################################################
sub substitute_all_bindings {
    my $self = shift;
    my $pattern = shift;
    my $regexp = $pattern;

    foreach my $slot (keys %{$self->{slots_filled}}) {
	$regexp =~ s/$slot/$self->{slots_filled}->{$slot}/g;
    }

    # substitute regexps in for unbound variables
    foreach my $slot (keys %{$self->{rslots_}}) {
	$regexp =~ s/$slot/$self->{rslots_}->{$slot}/g;
    }


    return $regexp;
}

######################################################################
sub substitute_def_bindings {
    my $self = shift;
    my $pattern = shift;
    my $regexp = $pattern;

    foreach my $slot (keys %{$self->{slots_filled}}) {
	$regexp =~ s/$slot/$self->{slots_filled}->{$slot}/g;
    }
    return $regexp;
}


######################################################################
sub figure_bindings {
    my $self=shift;
    my ($pattern, $rmatches, $rbindings) = @_;

    # remove constraint sepecifications
    $pattern =~ s/\<.*\>//g;
    
    foreach my $match (@$rmatches) {
	print STDERR "matching $pattern to $match\n" if $debug;
	my %bindings = ();

	foreach my $slot (keys %{$self->{rslots_}}) {
	    
	    if ($pattern !~ /$slot/) {
		next;
	    }

	    # test each binding one at a time so we can keep track

	    my $bindtest = $pattern;
	    $bindtest =~ s/\[\[/\\[\\[/g;
	    $bindtest =~ s/\]\]/\\]\\]/g;
	    

	    $bindtest =~ s/\s+/\\s+/g;
	    $bindtest =~ s/$slot/\($self->{rslots_}->{$slot}\)/g;


	    $bindtest = $self->substitute_all_bindings($bindtest);
	    if ($match =~ /$bindtest/) {
		my $value = $1;
		$bindings{$slot} = $value;
		print "$slot => $value\n" if $debug;
	    } 

	}


	foreach my $slot (keys %{$self->{slots_filled}}) {
	    print STDERR "($slot => $self->{slots_filled}->{$slot})\n" if $debug;
	    $bindings{$slot} = $self->{slots_filled}->{$slot};
	}

	push(@{$rbindings}, \%bindings);
    }
    
}




######################################################################
sub evaluate_pattern {
    my $self = shift;
    my $pattern = shift;
    my $rbindings = shift;

    printf STDERR "evaluating $pattern\n" if $debug;

    # substitute bound variables with bindings
    # and unbound variables with regular expressions
    my $regexp = $self->substitute_all_bindings($pattern);
    $self->parse_constraints(\$regexp);
    printf STDERR "regexp $regexp\n" if $debug;

    # substitute only variables that are already bound
    my $bound_pattern = $self->substitute_def_bindings($pattern);

    # parse out the constraints
    my $rconstraints = $self->parse_constraints(\$bound_pattern);



    # this should return the matched expressions
    # that way we can figure out what slots we need to bind in $pattern
    my @matches;
    &parse_scoped_fexp($regexp,\@matches);
    $self->figure_bindings($bound_pattern, \@matches, $rbindings);

    # here, let's remove the matches and bindings
    # that don't satisfy the constraints

    foreach my $constraint (@$rconstraints) {
	$rbindings = $self->apply_constraints($constraint, $rbindings);
    }

    return (scalar(@$rbindings));
}


######################################################################
# if we find a regular expression match, execute the transition
# otherwise, fall through
sub transition {
    my $self = shift;
    next if ($self->{pass});

    my ($pattern) = shift;
    my $noreset = shift;

    my @bindings;
    # evaluate the pattern given the appropriate bindings
    my $res = $self->evaluate_pattern($pattern, \@bindings);

    if ($res && !$self->{pass}) {
	return sub {
	    my $cont = shift;

	    # depth-first: hit this test equal to the number of matches
	    # ** test with different bindings each time **
	    # REBIND ONLY CHANGED VARS
   
	    for (my $i=0; $i<$res; $i++) {
		$self->reset_pf() if !$noreset;
		$self->reset_bindings($bindings[$i]);
		&$cont();
	    }
	}
    } else {
	return sub { return 0; };
    }

}

######################################################################
# control of pass variable 
sub pass {
    my $self = shift;
    print "**PASSED**\n\n"; 
    $self->{pass} = 1;
}

sub passed {
    my $self = shift;
    return $self->{pass};
}

######################################################################
# control of fail variable 
sub fail {
    my $self = shift;
    print "FAILED\n\n"; 
    $self->{fail} = 1;
}

sub failed {
    my $self = shift;
    return $self->{fail};
}

######################################################################
# control of abort
sub abort {
    my $self = shift;
    $self->{fail} = 1;
    $self->{pass} = 1;
}



######################################################################
# assigns the slot to a regular expression
sub slots {
    my $self = shift;
    $self->{rslots_} = shift;
}
######################################################################
# return the value for a particular slot (if bound)
sub get_slot {
    my $self = shift;
    my $key = shift;
    return $self->{slots_filled}->{$key};
}

######################################################################
# undefine all previously defined slots
sub unbind_all_slots {
    my $self = shift;

    %{$self->{slots_filled}} = ();
}


######################################################################
# bind the slot to a value 
sub bind_slot {
    my $self = shift;
    my ($key, $val) = @_;

    # XXX possibly should do some primitive type checking
    $self->{slots_filled}->{$key} = $val;
}


1;
