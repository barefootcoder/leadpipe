use 5.14.0;
use warnings;
use autodie qw< :all >;

use MooseX::Declare;
use Method::Signatures::Modifiers;


class App::Pb::Command::info extends App::Pb::Command
{
	use Debuggit;
	use autodie qw< :all >;
	use experimental 'smartmatch';

	use Path::Class;
	use Const::Fast;
	use MooseX::Has::Sugar;
	use MooseX::Types::Moose qw< :all >;


	# ATTRIBUTES

	has key         =>  (
							traits => [qw< NoGetopt >],
							rw, isa => Str,
						);


	# PRIVATE METHODS


	# PUBLIC METHODS

	augment validate_args ($opt, ArrayRef $args)
	{
		$self->key($args->[0]);
	}

	method execute (...)
	{
		given ($self->key)
		{
			when ( 'debug:DEBUG' )
			{
				say DEBUG;
			}
		}
	}

}
