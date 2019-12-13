package Pb;

use 5.14.0;
use warnings;
use autodie ':all';

# VERSION

use Exporter;
our @EXPORT =
(
	qw< command log_to flow >,						# structure of the command itself
	qw< verify SH >,								# keywords inside a flow
	qw< %FLOW >,									# variable containers that flows need access to
);

use Moo;
use CLI::Osprey;

use Safe::Isa;
use File::Path			qw< make_path >;
use PerlX::bash;
use Time::Piece;
use Import::Into;
use File::Basename;


sub import
{
	my $caller = caller;
	strict->import::into($caller);
	warnings->import::into($caller);
	feature->import::into($caller, ':5.14');
	autodie->import::into({level=>1}, ':all');		# `autodie` requires a bit of magic ...
	goto \&Exporter::import;
}


# This is a global, sort of ... it has a global lifetime, certainly, but not global visibility.
# Think of it like a singleton.  Most of our methods can either be called as object methods, in
# which case they operate on the object invocant, or just as straight functions, in which case they
# operate on this guy.  `$CMD` is set by `Pb->go` (which is down at the very bottom of this file).
my $CMD;

# And this is how we implement that optional invocant.
sub _pb_args { $_[0]->$_can('_osprey_config') ? @_ : ($CMD, @_) }


###################
# CONTEXT OBJECTS #
###################

# This will be appended to with command-specific values when the flow executes.
our %FLOW =
(
	DEBUG			=>	0,
	# can't fill in ME here, because we don't know it yet
);

our %OPT;											# key == option name, value == option value


##################
# GLOBAL OPTIONS #
##################

option pretend =>
(
	is => 'ro', doc => "don't run commands; just print them",
);


#####################
# COMMAND STRUCTURE #
#####################

=head1 COMMAND DEFINITION SYNTAX

=head2 command

Declare a Pb command.

=cut

sub _extrapolate_run_mode
{
	return 'NOACTION' if $OPT{pretend};
	return 'ACTION';
}

sub command
{
	state $CONTEXT_VAR_XLATE = { LOGFILE => 'log_to', };
	my ($name, %args) = @_;

	my $context = {};								# need a `my` var for the closure
	foreach ( keys %$CONTEXT_VAR_XLATE )
	{
		my $arg = $CONTEXT_VAR_XLATE->{$_};
		$context->{$_} = $args{$arg} if exists $args{$arg};
	}
	my $subcmd = sub
	{
		my ($osprey) = @_;
		my %opts = $osprey->_osprey_options;
		%OPT = map { $_ => $osprey->$_ } keys %opts;

		# I would `local`ize this, but it doesn't seem to work; not sure if that's because of the
		# closure or because of the export (or some combination thereof).  But it shouldn't matter
		# anyway because, on any given run of the program, exactly one flow gets executed and then
		# the program exits.  So (at least currently) it doesn't matter that we're essentially
		# overwriting the default context container.
		%FLOW = (%FLOW, %$context);
		# clients may use these
		$FLOW{TIME} = localtime($^T)->strftime("%Y%m%d%H%M%S");
		$FLOW{DATE} = localtime($^T)->strftime("%Y%m%d");
		# these are for internal use
		$FLOW{':RUNMODE'} = _extrapolate_run_mode();

		if ( exists $FLOW{LOGFILE} )
		{
			$FLOW{LOGFILE} =~ s/%(\w+)/$FLOW{$1}/g;
			make_path(dirname($FLOW{LOGFILE}));
		}

		$args{flow}->();
	};
	subcommand $name => $subcmd;
}


=head2 log_to

Specify a logfile for the output of a command.

=cut

sub log_to ($) { log_to => shift }


=head2 flow

Specify the code for the actual command.

=cut

sub flow (&) { flow => shift }


##############
# DIRECTIVES #
##############

=head2 verify

Make an assertion (using a code block) which must return a true value before the command will
execute.  Also specify the error message if the assertion fails.

=cut

sub verify (&$)
{
	my ($check, $fail_msg) = @_;
	fatal("pre-flow check failed [$fail_msg]") unless $check->();
}


=head2 SH

Run a command in C<bash>.  If the command does not exit with 0, the entire command will exit.

=cut

sub SH (@)
{
	my @cmd = @_;

	if ( $FLOW{':RUNMODE'} eq 'NOACTION' )
	{
		say "would run: @cmd";
		return;
	}

	push @cmd, ">>$FLOW{LOGFILE}" if exists $FLOW{LOGFILE};

	my $exitval = bash @cmd;
	unless ($exitval == 0)
	{
		fatal("command [@_] exited non-zero [$exitval]");
	}
}


####################
# SUPPORT ROUTINES #
####################

=head2 fatal

Print a fatal error and exit.

=cut

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

=begin Pod::Coverage

	run
	go

=end Pod::Coverage

=cut

# This is only used when there's a base command (but Osprey needs it regardless).
sub run
{
	$BASE_CMD->(@_) if $BASE_CMD;
}

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
