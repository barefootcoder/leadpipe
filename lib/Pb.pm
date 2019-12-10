package Pb;

use 5.14.0;
use warnings;
use autodie ':all';

# VERSION

use Moo;
use CLI::Osprey;

use Safe::Isa;


# This is a global, sort of ... it has a global lifetime, certainly, but not global visibility.
# Think of it like a singleton.  Most of our methods can either be called as object methods, in
# which case they operate on the object invocant, or just as straight functions, in which case they
# operate on this guy.  `$CMD` is set by `Pb->go` (which is down at the very bottom of this file).
my $CMD;

# And this is how we implement that optional invocant.
sub _pb_args { $_[0]->$_can('_osprey_config') ? @_ : ($CMD, @_) }


##################
# CONTEXT OBJECT #
##################

our %FLOW =
(
	DEBUG			=>	0,
	# can't fill in ME here, because we don't know it yet
);


####################
# SUPPORT ROUTINES #
####################

sub fatal
{
	my ($self, $msg) = &_pb_args;
	say STDERR "$FLOW{ME}: $msg";
	exit 1;
}


####################
# DEFAULT COMMANDS #
####################

subcommand help => sub { shift->osprey_help };
subcommand commands => sub
{
	my $class = shift;
	my %sc = $class->_osprey_subcommands;
	say foreach sort keys %sc;
};

subcommand info => sub
{
	my $self = shift;
	foreach (@_)
	{
		$self->fatal("no such setting [$_]") unless exists $FLOW{$_};
		say $FLOW{$_};
	}
};


##############
# GO GO GO!! #
##############

# Osprey needs this internally, even though we're not using it for anything (yet).
sub run {}

sub go
{
	shift @ARGV and $FLOW{DEBUG} = $1 if @ARGV and $ARGV[0] =~ /^DEBUG=(\d+)$/;

	$CMD = shift->new_with_options;

	# This little dance is to find the ultimate parent command in case we end up with an inline
	# subcommand or somesuch (viz. CLI::Osprey::InlineSubcommand).
	my $top_level = $CMD;
	$top_level = $top_level->parent_command while $top_level->can('parent_command') and $top_level->parent_command;
	$FLOW{ME} = $top_level->invoked_as;

	$CMD->run;
}


1;



# ABSTRACT: a workflow system made from Perl and bash
# COPYRIGHT


=head1 SYNOPSIS


=head1 DESCRIPTION


=head1 USAGE


=head1 BUGS, CAVEATS and NOTES

=cut