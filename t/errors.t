use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::Pb::Bin;


# SYNTACTICAL FAILURES

# `command` declaration syntax with random garbage
pb_basecmd(bad_command => <<'END');
	use Pb;
	command explode =>
		random => 'crap',
	flow
	{
		say "should have died already";
	};
	Pb->go;
END
check_error pb_run('explode'), 1, "bad_command: unknown command attribute [random]",
		"`command` syntax rejects unknown elements";

# unknown `arg` type
pb_basecmd(bad_type => <<'END');
	use Pb;
	command explode =>
		arg foo => must_be 'bogus-type',
	flow
	{
	};
	Pb->go;
END
check_error pb_run('explode'), 1, "bad_type: not a valid type [bogus-type]", "detects illegal type";

# no real proper constraint
pb_basecmd(bad_type => <<'END');
	use Pb;
	command explode =>
		arg foo => 'bogus-type',
	flow
	{
	};
	Pb->go;
END
check_error pb_run('explode'), 1, "bad_type: not a constraint [bogus-type]", "detects lack of constraint keyword";


# OPERATIONAL FAILURES (arguments)

# `arg` failure to validate type
pb_basecmd(argfail => <<'END');
	use Pb;
	use Types::Standard -types;
	command explode =>
		arg foo => must_be Int,
	flow
	{
	};
	Pb->go;
END
check_error pb_run('explode', "x"), 1, "argfail: arg foo fails validation [x is not a Int]",
		"can validate arg type";

# `arg` failure to validate type as string
pb_basecmd(argfail => <<'END');
	use Pb;
	command explode =>
		arg foo => must_be 'Int',
	flow
	{
	};
	Pb->go;
END
check_error pb_run('explode', "x"), 1, "argfail: arg foo fails validation [x is not a Int]",
		"can validate arg typestring";

# `arg` failure to validate one of a given list
pb_basecmd(argfail => <<'END');
	use Pb;
	command explode =>
		arg foo => one_of [qw< a b c >],
	flow
	{
	};
	Pb->go;
END
check_error pb_run('explode', "x"), 1, "argfail: arg foo fails validation [x must be one of: a, b, c]",
		"can validate arg list";


# OPERATIONAL FAILURES (other)

# `verify` failure
pb_basecmd(verify => <<'END');
	use Pb;
	command explode => flow
	{
		verify { 0 } "AAAH! We're all gonna die!";
	};
	Pb->go;
END
check_error pb_run('explode'), 1, "verify: pre-flow check failed [AAAH! We're all gonna die!]",
		"`verify` calls `fatal` when condition fails";

# failure of an `SH` directive
pb_basecmd(sh_dirty_exit => <<'END');
	use Pb;
	command explode => flow
	{
		SH exit => 33;
		SH echo => "should never get here";
	};
	Pb->go;
END
check_error pb_run('explode'), 1, "sh_dirty_exit: command [exit 33] exited non-zero [33]",
		"`SH` calls `fatal` on dirty exit";


done_testing;
