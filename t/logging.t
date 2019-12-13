use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::Pb::Bin;

use File::Temp			qw< tempdir >;


my $logdir = tempdir( TMPDIR => 1, CLEANUP => 1 );

my $test_cmd = <<'END';
	use Pb;

	command get_logfile2 =>
		log_to '%%/some/other/file',
	flow
	{
		say $FLOW{LOGFILE};
	};

	command get_logfile1 =>
		log_to '%%/some/file',
	flow
	{
		say $FLOW{LOGFILE};

		# verify that our logfile's dir gets created
		-d '%%/some' or die("failed to create parent dir for our logfile");
		# and that the logfile dir of other commands _don't_
		not -d '%%/some/other' or die("created parent log dir for the wrong command");

		# now do something that will actually create a logfile
		SH echo => "this is a test";
		SH echo => "a second line";
	};

	Pb->go;
END
$test_cmd =~ s/%%/$logdir/g;
pb_basecmd(test_pb => $test_cmd);

check_output pb_run('get_logfile1'), "$logdir/some/file", "logfile name saved in context container";
check_output pb_run('get_logfile2'), "$logdir/some/other/file", "logfile name individuates by command";

# verify that we got our logfile output
my $log = _slurp("$logdir/some/file");
my @lines = ( "this is a test", "a second line", );
is $log, join('', map { "$_\n" } @lines), "base logging works (SH directive)";


done_testing;
