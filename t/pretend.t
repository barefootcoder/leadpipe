use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::Pb::Bin;

use File::Temp;


# This is pretty much how Path::Tiny::tempfile does it.
my $logfile = File::Temp->new( TMPDIR => 1 ); close $logfile;

my $test_cmd = <<'END';
	use Pb;

	command ptest =>
		log_to '%%',
	flow
	{
		SH echo => "first line";
		SH echo => "second line";
	};

	Pb->go;
END
$test_cmd =~ s/%%/$logfile/g;
pb_basecmd(test_pb => $test_cmd);

# first, run in standard mode
check_output pb_run('ptest'), "sanity check: output not going to term";
my $log = _slurp($logfile);
my @lines = ( "first line", "second line", );
is $log, join('', map { "$_\n" } @lines), "sanity check: output going to log";

# have to remove the logfile or else output will just keep getting tacked on
unlink $logfile;

# now run in pretend mode
check_output pb_run('--pretend', 'ptest'), (map { "would run: echo $_" } @lines), "basic pretend mode: good output";
$log = _slurp($logfile);
is $log, undef, "basic pretend mode: no execution";


done_testing;
