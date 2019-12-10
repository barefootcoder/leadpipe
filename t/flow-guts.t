use Test::Most;

use File::Basename;
use lib dirname($0);
use Test::Pb::Bin;


my $test_cmd = <<'END';
	use Pb;

	command dumb => flow
	{
		SH echo => 'hello';
	};

	Pb->go;
END
my @commands = sort (qw< commands help info >, $test_cmd =~ /\bcommand\s+(\w+)\b/g);
pb_basecmd(test_pb => $test_cmd);
check_output pb_run('commands'), @commands, "command keyword generates an Osprey subcommand";

check_output pb_run('dumb'), "hello", "can execute stupid-simple single-SH-directive flow";


done_testing;
