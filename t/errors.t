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


done_testing;
