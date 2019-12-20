package Pb;

use 5.14.0;
use warnings;
use autodie ':all';

# VERSION

use Exporter;
our @EXPORT =
(
	qw< command log_to control_via flow >,			# structure of the command itself
	qw< arg must_be one_of >,						# for declaring command arguments
	qw< verify SH RUN >,							# keywords inside a flow
	qw< %FLOW >,									# variable containers that flows need access to
);

use Moo;
use CLI::Osprey;

use Fcntl				qw< :flock >;
use Safe::Isa;
use File::Path			qw< make_path >;
use Type::Tiny;
use PerlX::bash;
use Time::Piece;
use Import::Into;
use File::Basename;


sub import
{
	my $caller = caller;
	_setup_signal_handlers();
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
our %CONTROL;										# key == command name, value == control structure
my  $DEFAULT_EXIT_STATUS = 'exited cleanly';		# default; update this when you hit an error
our $EXIT_STATUS = $DEFAULT_EXIT_STATUS;


##################
# GLOBAL OPTIONS #
##################

option pretend =>
(
	is => 'ro', doc => "don't run commands; just print them",
);


###############
# SCAFFOLDING #
###############

# this will hold all the different flows
my %FLOWS;

sub _expand_vars
{
	shift =~ s/%(\w+)/$FLOW{$1}/gr;
}

sub _prep_filename
{
	my ($file) = @_;
	$file = _expand_vars($file);
	make_path(dirname($file));
	return $file;
}

=head1 COMMAND DEFINITION SYNTAX

=head2 command

Declare a Pb command.

=cut

sub _extrapolate_run_mode
{
	return 'NOACTION' if $OPT{pretend};
	return 'ACTION';
}

sub _safe_file_rw
{
	my ($file, $line) = @_;
	my ($open_mode, $lock_mode) = defined $line ? ('>', LOCK_EX) : ('<', LOCK_SH);

	# This is essentially the same amount of paranoia that Proc::Pidfile undergoes.  I just don't
	# have to catch all the errors because I have `autodie` turned on.
	eval
	{
		local *FILE;
		open FILE, $open_mode, $file;
		flock FILE, $lock_mode;
		if ($open_mode eq '<')
		{
			$line = <FILE>;
			chomp $line;
		}
		else
		{
			say FILE $line;
		}
		flock FILE, LOCK_UN;
		close(FILE);
	};
	if ($@)
	{
		fatal("file read/write failure [" . $@ =~ s/ at .*? line \d+.*\n//sr . "]")
				unless $@ =~ /^Can't open '$file' for reading:/;
	}
	return $line;
}


# This deals with all the stuff you can put in the "control structure (i.e. the hashref that follows
# the `control_via` keyword).
sub _process_control_structure
{
	my ($cmd) = @_;

	if (my $control = $CONTROL{$cmd})
	{
		foreach (grep { exists $control->{$_} } qw< pidfile statusfile unless_clean_exit >)
		{
			my $value = delete $control->{$_};
			if ($_ eq 'pidfile')
			{
				require Proc::Pidfile;
				my $pidfile = eval { Proc::Pidfile->new( pidfile => _prep_filename($value) ) };
				if ($pidfile)
				{
					$FLOW{':PIDFILE'} = $pidfile;
				}
				else
				{
					if ( $@ =~ /already running: (\d+)/ )
					{
						$EXIT_STATUS = 'NOSAVE';
						fatal("previous instance already running [$1]");
					}
					else
					{
						die;						# rethrow
					}
				}
			}
			elsif ($_ eq 'statusfile')
			{
				$FLOW{':STATFILE'} = _prep_filename($value);
				my $statfile = sub
				{
					unless ($EXIT_STATUS eq 'NOSAVE')
					{
						_safe_file_rw($FLOW{':STATFILE'}, "last run: $EXIT_STATUS at " . scalar localtime);
					}
				};
				# have to use string `eval` here, otherwise the `END` will always fire
				eval 'END { $statfile->() }';
			}
			elsif ($_ eq 'unless_clean_exit')
			{
				fatal("cannot specify `unless_clean_exit' without `statusfile'") unless defined $FLOW{':STATFILE'};
				my $lastrun = _safe_file_rw($FLOW{':STATFILE'});
				if ($lastrun)											# probably means this is the first run
				{
					my ($last_exit) = $lastrun =~ /: (.*?) at /;
					unless ($last_exit eq $DEFAULT_EXIT_STATUS)
					{
						$EXIT_STATUS = 'NOSAVE';
						$FLOW{ERR} = $last_exit;
						my $msg = _expand_vars($value);
						fatal($msg);
					}
				}
			}
		}
		fatal("unknown parameter(s) in control structure [" . join(',', sort keys %$control) . "]") if %$control;
	}
}


# This guarantees that `END` blocks are not only called when your program `exit`s or `die`s, but
# also when it's terminated due to a signal (where possible to catch).  This is super-important for
# things like making sure pidfiles get cleaned up.  I'm pretty sure that the only times your `END`
# blocks won't get called if your program exits after this runs is for uncatchable signals (i.e.
# `KILL`) and if you call `exec`.  I'd worry more about that latter one, but it seems pretty
# unlikely in a Leadpipe context.
sub _setup_signal_handlers
{
	# This list compiled via the following methodology:
	#	*	Examine the signal(7) man page on a current (at the time) Linux version (this one just
	#		so happened to be Linux Mint 18.2, kernel 4.10.0-38-generic).
	#	*	Find all signals which are labeled either "Term" or "Core" (i.e. all signals which will
	#		actually cause your process to exit).
	#	*	Eliminate everything already in sigtrap.pm's "normal-signals" list.
	#	*	Eliminate everything already in sigtrap.pm's "error-signals" list.
	#	*	Eliminate "KILL," because you can't catch it anyway.
	#	*	Eliminate "USR1" and "USR2" on the grounds that we shouldn't assume anything about
	#		"user-defined signals."
	#	*	Whatever was leftover is the list below.
	my @EXTRA_SIGNALS = qw< ALRM POLL PROF VTALRM XCPU XFSZ IOT STKFLT IO PWR LOST UNUSED >;
	require sigtrap;
	# Because of the `untrapped`, this won't bork any signals you've previously set yourself.
	# Signals you _subsequently_ set yourself will of course override these.
	sigtrap->import( handler => sub
		{
			my $signal = shift;
			# Weirdly (or maybe not so much; I dunno), while `END` blocks don't get called if a
			# `'DEFAULT'` signal handler leads to an exit, they _do_ for custom handlers.  So this
			# `sub` literally doesn't need to do _anything_.  But, hey: while we're here, may as
			# well alert the user as to what's going down.
			$EXIT_STATUS = "terminated due to signal $signal";
			say STDERR "received signal: $signal";
		},
		untrapped => 'normal-signals', 'error-signals',
		grep { exists $SIG{$_} } @EXTRA_SIGNALS
	);
}


#####################
# COMMAND STRUCTURE #
#####################

sub command
{
	state $PASSTHRU_ARGS = { map { $_ => 1 } qw< log_to flow > };
	state $CONTEXT_VAR_XLATE = { LOGFILE => 'log_to', };
	my $name = shift;

	# these are all used in the closure below
	my %args;										# arguments to this command definition
	my $argdefs = [];								# definition of args to the command invocation
	# process args: most are simple, some are trickier
	while (@_)
	{
		if ($PASSTHRU_ARGS->{$_[0]})
		{
			my $arg = shift;
			$args{$arg} = shift;
		}
		elsif ($_[0] eq 'arg')
		{
			shift;									# just the 'arg' marker
			my $arg = {};
			$arg->{name} = shift;
			$arg->{type} = shift;
			fatal("not a constraint [" . (ref $arg->{type} || $arg->{type}) . "]")
					unless $arg->{type}->$_isa('Type::Tiny');
			push @$argdefs, $arg;
		}
		elsif ($_[0] eq 'control')
		{
			shift;									# just the 'control' marker
			my $control = shift;
			fatal("`control_via' requires hashref") unless ref $control eq 'HASH';
			$CONTROL{$name} = $control;
		}
		else
		{
			fatal("unknown command attribute [$_[0]]");
		}
	}

	# Save the flow (including processing any args) under our name.  Doing args here rather than in
	# the `$subcmd` below enables the `RUN` directive to pass args as well.
	$FLOWS{$name} = sub
	{
		foreach (@_)
		{
			my $argdef = shift @$argdefs;
			unless ($argdef->{type}->check($_))
			{
				fatal("arg $argdef->{name} fails validation [" . $argdef->{type}->validate($_) . "]");
			}
			$FLOW{$argdef->{name}} = $_;
		}

		$args{flow}->();
	};

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
		# anyway because, on any given run of the program, exactly one (master) flow gets executed
		# and then the program exits.  (Subflows can be executed by the master, but they always use
		# the same context.)  So (at least currently) it doesn't matter that we're essentially
		# overwriting the default context container.
		%FLOW = (%FLOW, %$context);
		# clients may use these
		$FLOW{TIME} = localtime($^T)->strftime("%Y%m%d%H%M%S");
		$FLOW{DATE} = localtime($^T)->strftime("%Y%m%d");
		# these are for internal use
		$FLOW{':RUNMODE'} = _extrapolate_run_mode();					# more like this set by `_process_control_structure`

		_process_control_structure($name);
		$FLOW{LOGFILE} = _prep_filename($FLOW{LOGFILE}) if exists $FLOW{LOGFILE};

		# Script args are flow args (switches were already processed by Osprey).
		$FLOWS{$name}->(@ARGV);
	};
	subcommand $name => $subcmd;
}


=head2 arg

Declare an argument to a command.

=head2 must_be

Specify the type (of either an argument or option).

=head2 one_of

Specify the valid values for an enum type (for either an argument or option).  Use I<instead of>
C<must_be>, not in addition to.

=cut

sub arg ($) { arg => shift }

sub must_be ($)
{
	my $type = shift;
	# slightly cheating, but this private method handles the widest range of things that might be a
	# type (including if it's already a Type::Tiny to start with)
	my ($t) = eval { Type::Tiny::_loose_to_TypeTiny($type) };
	fatal("not a valid type [$type]") unless defined $t;
	$t->create_child_type(message => sub { ($_ // '<<undef>>') . " is not a " . $t->name });
}

sub one_of ($)
{
	require Type::Tiny::Enum;
	my $v = shift;
	Type::Tiny::Enum->new( values => $v, message => sub { ($_ // '<<undef>>') . " must be one of: " . join(', ', @$v) });
}


=head2 log_to

Specify a logfile for the output of a command.

=head2 control_via

Specify a control structure.  This is where you put pidfile, statusfile, etc.

=cut

sub log_to ($) { log_to => shift }

sub control_via ($) { control => shift }


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

=head2 RUN

Run one command inside another.  Although you pass the nested command its own arguments, all other
parts of the context (including options) are retained.

=cut

sub RUN (@)
{
	my ($flow, @args) = @_;
	$FLOWS{$flow}->(@args);
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
	my $me = $FLOW{ME} // basename($0);
	say STDERR "$me: $msg";
	$EXIT_STATUS = $msg unless $EXIT_STATUS eq 'NOSAVE';
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
