use 5.14.0;
use warnings;
use autodie qw< :all >;

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::Pb::Command extends MooseX::App::Cmd::Command
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use Const::Fast;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	# ATTRIBUTES


	# PRIVATE METHODS


	# PUBLIC METHODS

	method validate_args ($opt, ArrayRef $args)
	{
		inner();
	}

}
