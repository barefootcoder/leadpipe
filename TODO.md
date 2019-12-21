These are things I want to not forget to do.  Also, any people who are
interested in contributing to Leadpipe could take on one of these tasks.  The
list below is not in any particular order.

* If a script does not have a `base_command`, running it without a subcommand
  just returns immediately.  Probably that should give a more user-friendly
  message.

  **_Implementation Note:_** Doing this should be a simple matter of changing
  the `$BASE_CMD->(@_) if $BASE_CMD` in `Pb::run` to something more like:
  ```
  if ($BASE_CMD)
  {
      $BASE_CMD->(@_);
  }
  else
  {
      ...
  }
  ```
* Contrariwise, if a script _does_ have a `base_command`, the current `help`
  message gives no indication of that fact, which it definitely should.
  (Possibly `commands` should as well, though that's less clear.)
* In a perfect world, `%FLOW` would be readonly, and you could only set values
  in it via the `SET` directive.  The obvious way to do that is to change
  `FLOW` from a hash to an object, and then access the context vars via methods
  instead of hash keys.  However, that means you can't directly interpolate
  context vars, and I don't like that.  Probably there's some way to mark a
  hash readonly or somesuch; I need to investigate the possibilities.
* Currently there's no way to have "slurpy" arguments.  For instance, you might
  want one or more (or zero or more) filenames as args.  One possible syntax
  would be: `arg files => list_of '1..'`.  Then you could specify `'0..'` or
  `'1..2'` or whatever.  Then I suppose you have you access it like
  `@{$FLOW{files}}`, which is ... not ideal. :-/  **_Implementation Note:_**
  VCtools currently uses a similar syntax, so there's probably code to be
  stolen from there.
* Maybe the solution to the object/hash dilemma for `FLOW` is ... both.  That
  is, if `$FLOW` were an object, it could be overloaded on hash deferencing
  such that `$FLOW->{foo}` was the same as `$FLOW->foo`.  Which is nifty, since
  you can directly interpolate the latter (even if it is a couple characters
  longer), but you wouldn't be able to assign to it (unless the method were
  defined to return an lvalue, but I can't imagine doing that).  This also
  opens up the possibility of having other methods, which could be nifty,
  although then you could get name clashes with variables.  Probably instead of
  `$FLOW->{foo}` meaning `$FLOW->foo`, it should mean `$FLOW->var('foo')` or
  somesuch.
* I still need to add options for command flows.  I think the syntax should be
  the same as for args in specifying the constraint, and probably only one more
  attribute: `doc`, for documentation.  So something like `opt input => must_be
  Str, doc => "specify a <path> to pull input from",` would just turn into:
  ```
  option input =>
  (
      is => 'ro',
	  isa => Str,		# probably optional
	  format => 's',
	  doc => "specify a <path> to pull input from",
	  format_doc => "<path>",
  )
  ```
  and that's probably all we ever really need to specify.  Default constraint
  is `Bool`.  The `negatable` attribute could either always be supplied, or
  could be supplied for explicit `Bool`s but not default `Bool`s.  `repeatable`
  is probably never necessary (but could be implied if the constraint specifies
  an `ArrayRef` or somesuch); `required` would definitely never be necessary.
  The only other one I can think of wanting is `short`, and we can just cross
  that bridge when we come to it.
