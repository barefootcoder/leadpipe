use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::Pb::Bin;

use File::Temp;


pb_basecmd(sh_test => <<'END');
	use Pb;

	command explode => flow
	{
		SH exit => 33;
		SH echo => "should never get here";
	};

	command perl_explode => flow
	{
		SH $^X => -e => 'die "explode\n"';
		SH echo => "should never get here";
	};

	command catch_exit => flow
	{
		my $status = SH exit => 33;
		say "exited with $status";
	};

	command verify => flow
	{
		verify { SH exit => 33 } "can't continue!";
		SH echo => "should never get here";
	};

	Pb->go;
END

# double check that SH as a directive blows up
# (this is also checked in t/errors.t)
check_error pb_run('explode'), 1, "sh_test: command [exit 33] exited non-zero [33]",
		"`SH` calls `fatal` on dirty exit";

# how about a `die` from Perl?
# NB: This error message needs to be radically cleaned up.  See more extensive notes in TODO.md.
my $die_msg = '"bash" unexpectedly returned exit value 255 at .*';
check_error pb_run('perl_explode'), 1,
		qr/explode\nsh_test: command \[$^X -e die \"explode\\n\"\] had fatal error \[$die_msg\]/,
		"`SH` calls `fatal` on perl die";

# OTOH, if you catch the return value, it should *not* blow up
check_output pb_run('catch_exit'), "exited with 33", "can catch an SH exit value w/o blowing up";

# running `SH` inside `verify` should explode, but for a different reason
check_error pb_run('verify'), 1, "sh_test: pre-flow check failed [can't continue!]",
		"`SH` inside `verify` functions as expected";


done_testing;
