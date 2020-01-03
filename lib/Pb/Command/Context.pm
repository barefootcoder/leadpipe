package Pb::Command::Context;

# VERSION

use Moo;
use 5.14.0;
use autodie ':all';
use MooX::HandlesVia;
use namespace::autoclean;

extends 'Clone';									# so we have our own `clone` method

use Fcntl				qw< :flock >;
use File::Path			qw< make_path >;
use Const::Fast;
use Time::Piece;
use File::Basename;


# Default values for vars here; most values are set as we go along.
my %DEFAULT_CONTEXT =
(
	DEBUG		=>	0,
	TIME		=>	localtime($^T)->strftime("%Y%m%d%H%M%S"),
	DATE		=>	localtime($^T)->strftime("%Y%m%d"),
);

# This is how we tell if we didn't have an error on the last run.
my  $CLEAN_EXIT = 'exited cleanly';


##############
# ATTRIBUTES #
##############

=head1 ATTRIBUTES

=cut


# These are the actual context vars that flows can access via hash deferencing.
has _vars 	=> (	is => 'ro', default => sub { +{%DEFAULT_CONTEXT} }, handles_via => 'Hash',
					handles => { var => 'get', has_var => 'exists', }, );

# The `@RAW_ACCESS` lists packages that are allowed to access our internals directly.  Everyone else
# who treats us like a hash reference gets the hash of context vars instead.  This is how we get
# around the infinite dereferencing loop we would otherwise engender for being a blessed hash that
# defines an overloaded hash dereference operator.  See `perldoc overload` for more details.
# (This method is a bit hacky, but effective, and fairly quick.)
my @RAW_ACCESS = qw< Method::Generate::Accessor Pb::Command::Context >;
use overload '%{}' => sub { (grep { caller =~ /^$_\b/ } @RAW_ACCESS) ? $_[0] : $_[0]->_vars }, fallback => 1;

# Simple attributes; free to read, but only certain people can write to them.
has runmode           => ( is => 'rwp', );
has statfile	      => ( is => 'rwp', );
has proc_pidfile      => ( is => 'rwp', );
has toplevel_command  => ( is => 'rwp', );

# Do we, or do we not, update the statfile (if any) when we exit?
has update_statfile   => ( is => 'rwp', default => 1, );
sub dont_update_statfile { my $self = shift; $self->_set_update_statfile(0); }

# pseudo-attributes
# (Mostly context vars posing as attributes, but also some attributes' attributes.)

=head2 error

Last recorded error.

=head2 logfile

Logfile for the command (if any).

=head2 pidfile

File containing the PID (if any).

=cut

sub error			{ my $self = shift; $self->_vars->{ERR}                                         }
sub logfile			{ my $self = shift; $self->_vars->{LOGFILE}                                     }
sub pidfile			{ my $self = shift; my $ppf = $self->proc_pidfile; $ppf ? $ppf->pidfile : undef }

sub _set_logfile	{ my ($self, $file) = @_; $self->_vars->{LOGFILE} = $file;                      }


##################
# HELPER METHODS #
##################

sub _expand_vars
{
	my ($self, $string) = @_;
	$string =~ s/%(\w+)/$self->_vars->{$1}/ge;
	return $string;
}

sub _prep_filename
{
	my ($self, $file) = @_;
	$file = $self->_expand_vars($file);
	make_path(dirname($file));
	return $file;
}

sub _extrapolate_run_mode
{
	my ($self, %opts) = @_;
	return 'NOACTION' if $opts{pretend};
	return 'ACTION';
}

sub _safe_file_rw
{
	my ($self, $file, $line) = @_;
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
		$self->raise_error("file read/write failure [" . $@ =~ s/ at .*? line \d+.*\n//sr . "]")
				unless $@ =~ /^Can't open '$file' for reading:/;
	}
	return $line;
}



##################
# PUBLIC METHODS #
##################

=head1 METHODS

=head2 set_debug

Set debugging to a certain level.

=head2 set_var

Set a context variable to a certain value.

=cut

sub set_debug { my ($self, $level)     = @_; $self->_vars->{DEBUG} = $level }

sub set_var   { my ($self, $var, $val) = @_; $self->_vars->{$var}  = $val   }


=head2 raise_error

Register a generic error.

=cut

# Currently, this just sets the `ERR` context var, but in the future it may do more.
sub raise_error
{
	my ($self, $err) = @_;
	$self->_vars->{ERR} = $err;
}


######################
# STRUCTURE BUILDERS #
######################

=head2 setup_context

Establish the context.  If called as a class method, this is a constructor; if called as an object
method, it creates a copy of the given context and then builds up from there.  You pass in initial
context variables, option definitions, and a control structure.

=cut

sub setup_context
{
	my ($inv, $vars, $opts, $control) = @_;
	my $self = ref $inv ? $inv->clone : $inv->new;

	# set whatever vars weren't already set
	$self->set_var($_ => $vars->{$_}) foreach keys %$vars;

	# have to do this at runtime so that we only create a logfile for the running command
	$self->prep_logfile;
	# have to this at run time so we have parsed options to work with
	$self->_set_runmode( $self->_extrapolate_run_mode(%$opts) );

	# process control stuff; some of this might mean we have to bail out
	unless ( $self->_process_control_structure($control) )
	{
		# this should never be necessary; `error` should always be set by `_process_control_structure`
		$self->raise_error('Unknown error processing control structure') unless $self->error;
	}

	return $self;
}

# This deals with all the stuff you can put in the "control structure (i.e. the hashref that follows
# the `control_via` keyword).
sub _process_control_structure
{
	my ($self, $control) = @_;

	foreach (grep { exists $control->{$_} } qw< pidfile statusfile unless_clean_exit >)
	{
		my $value = delete $control->{$_};
		if ($_ eq 'pidfile')
		{
			return undef unless $self->prep_pidfile($value);
		}
		elsif ($_ eq 'statusfile')
		{
			$self->_set_statfile($self->_prep_filename($value));
			my $statfile = sub
			{
				if ($self->update_statfile)
				{
					my $exit_status = $self->error // $CLEAN_EXIT;
					$self->_safe_file_rw($self->statfile, "last run: $exit_status at " . scalar localtime);
				}
			};
			# have to use string `eval` here, otherwise the `END` will always fire
			eval 'END { $statfile->() }';
		}
		elsif ($_ eq 'unless_clean_exit')
		{
			unless (defined $self->statfile)
			{
				$self->raise_error("cannot specify `unless_clean_exit' without `statusfile'");
				return undef;
			}
			my $lastrun = $self->_safe_file_rw($self->statfile);
			return undef if $self->error;
			if ($lastrun)												# if not, probably means this is the first run
			{
				my ($last_exit) = $lastrun =~ /: (.*?) at /;
				unless ($last_exit eq $CLEAN_EXIT)
				{
					$self->raise_error($last_exit);						# in case our message wants to access %ERR
					my $msg = $self->_expand_vars($value);
					$self->raise_error($msg);							# this is the real (user-supplied) error message
					$self->dont_update_statfile;						# don't wipe out the previous exit status; ...
					return undef;										# ... we're just going to die here anyway
				}
			}
		}
	}
	if ( %$control )
	{
		$self->raise_error("unknown parameter(s) in control structure [" . join(',', sort keys %$control) . "]");
		return undef;
	}
	else
	{
		return 1;
	}
}


=head2 connect_to

Connect a context to an Osprey command.  This always has to be done eventually, but generally you
have to wail until runtime, when we know which command the user chose.

=cut

sub connect_to
{
	my ($self, $command) = @_;

	# This little dance is to find the ultimate parent command in case we end up with an inline
	# subcommand or somesuch (viz. CLI::Osprey::InlineSubcommand).
	my $top_level = $command;
	$top_level = $top_level->parent_command while $top_level->can('parent_command') and $top_level->parent_command;

	$self->_set_toplevel_command($top_level);
	$self->_vars->{ME} = $top_level->invoked_as;
}


=head2 prep_logfile

Get a logfile ready for outputting to.

=cut

sub prep_logfile
{
	my $self = shift;
	return unless $self->has_var('LOGFILE');
	$self->_set_logfile( $self->_prep_filename($self->_vars->{LOGFILE}) );
	return 1;
}


=head2 prep_pidfile

Build a Proc::Pidfile object and handle any "already running" issues.

=cut

sub prep_pidfile
{
	my ($self, $filename) = @_;
	require Proc::Pidfile;
	my $pidfile = eval { Proc::Pidfile->new( pidfile => $self->_prep_filename($filename) ) };
	if ($pidfile)
	{
		$self->_set_proc_pidfile($pidfile);
	}
	else
	{
		if ( $@ =~ /already running: (\d+)/ )
		{
			$self->raise_error("previous instance already running [$1]");
			$self->dont_update_statfile;			# don't wipe out the previous exit status; ...
			return undef;							# ... we're just going to die here anyway
		}
		else
		{
			die;									# rethrow
		}
	}
	return 1;
}


# Get the command options, as a hash.  Merges both local and global opts.
sub parse_opts
{
	my ($self, $command) = @_;
	my %opt_objects = $command->_osprey_options;
	my %opts = map { $_ => $command->$_ } keys %opt_objects;
	# get options from top-level command as well (these are the global opts)
	{
		my %opt_objects = $self->toplevel_command->_osprey_options;
		$opts{$_} //= $self->toplevel_command->$_ foreach keys %opt_objects;
	}
	return %opts;
}


1;



# ABSTRACT: context object for a Pb command
# COPYRIGHT


=head1 DESCRIPTION

This is the command context class used by L<Pb>.  A lot of it is for internal use, but some methods
may be useful for calling on the C<$FLOW> object.

=cut