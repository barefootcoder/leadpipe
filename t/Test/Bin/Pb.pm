package Test::Bin::Pb;

use parent 'Exporter';

our @EXPORT = qw< pb_run check_output >;


use Test::Most;
use autodie ':all';

use Const::Fast;
use Path::Class;


const our $PB => file($0)->parent->file( '..', 'bin', 'pb' )->resolve;

ok -e $PB, "pb binary exists";
ok -x $PB, "pb binary is executable";


sub pb_run
{
	use Test::Trap qw< :output(systemsafe) :on_fail(diag_all_once) >;
	my @args = @_;

	trap { system($PB, @args) };
	return $trap;
}

sub check_output
{
	my $testname = pop;
	my ($trap, @lines) = @_;

	subtest $testname => sub
	{
		$trap->did_return("clean exit");
		$trap->stderr_is( '', "no errors" );
		$trap->stdout_is( join('', map { "$_\n" } @lines), "good output" );
	};
}
