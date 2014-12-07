use Test::Most;
use Debuggit DEBUG => 1;

use File::Basename;
use lib dirname($0);
use Test::Bin::Pb;


check_output pb_run(qw< info debug:DEBUG >), 0, "DEBUG set properly";
check_output pb_run(qw< DEBUG=1 info debug:DEBUG >), 1, "DEBUG set properly";


done_testing;
