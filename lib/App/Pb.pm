use 5.14.0;
use warnings;
use autodie qw< :all >;

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::Pb extends MooseX::App::Cmd
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use Const::Fast;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	const our $VERSION => 'v0.01';


	# ATTRIBUTES


	# PRIVATE METHODS


	# PUBLIC METHODS

}
