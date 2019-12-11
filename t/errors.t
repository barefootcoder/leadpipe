use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::Pb::Bin;


# OPERATIONAL FAILURES

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
