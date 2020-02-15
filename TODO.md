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
* In a perfect world, `%$FLOW` would be readonly, and you could only set values
  in it via the `SET` directive.  Probably the easiest way to do that is to
  have the `FLOW` object's overloaded hash dereference operator return a
  constant _copy_ of the `_vars` attribute.
* Currently there's no way to have "slurpy" arguments.  For instance, you might
  want one or more (or zero or more) filenames as args.  One possible syntax
  would be: `arg files => list_of '1..'`.  Then you could specify `'0..'` or
  `'1..2'` or whatever.  Then I suppose you have to access it like
  `@{$FLOW->{files}}`, which is ... not ideal. :-/  **_Implementation Note:_**
  VCtools currently uses a similar syntax, so there's probably code to be
  stolen from there.
* I need to flesh out properties for command flow options.  I think the syntax
  just needs one more property: `doc`, for documentation.  So something like
  `opt input => must_be Str, doc => "specify a <path> to pull input from",`
  would turn into:
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
  could be `Bool`, or perhaps you always have to specify a constraint (which is
  the current situation).  The `negatable` attribute could either always be
  supplied (for `Bool`), or could be supplied for explicit `Bool`s but not
  default `Bool`s.  `repeatable` is probably never necessary (but could be
  implied if the constraint specifies an `ArrayRef` or somesuch); `required`
  would definitely never be necessary.  The only other one I can think of
  wanting is `short`, and we can just cross that bridge when we come to it.
  **_NOTE:_** Now that we have `also`, any of these could done using that
  syntax.
* There are currently no syntax checks for the `also` keyword.  Syntax errors
  would include but not be limited to: using `also` where it doesn't make sense
  (e.g. in an `arg` or a `control`), giving `also` arguments that can't
  possibly work out to a set of key/value pairs (e.g. `also(1)`), or using the
  "longcut" version of `also` without a hashref (e.g. `properties => 1`).
  However, an empty `also` (e.g. `also()`) should _not_ be considered an error.
  (I mean, it's stupid, but it's not an error.)
* Also consider rejecting unknown properties, because it's easy to typo a long
  property name like "access_as_var" (speaking from experience here).
* When using `also(-access_as_var)`, it doesn't currently check for collisions
  (i.e. there's already a variable with the same name as the option).  This
  should definitely be an error or else really hard-to-debug errors will likely
  result.
* There seems to be some sort of problem with Osprey's handling of unknown
  options.  I keep seeing this error message: `Can't locate object method
  \"die\" via package \"CLI::Osprey::Descriptive::Usage\"`
* Failure to supply a required argument gives you an error, because `undef`
  fails the validation check.  But the error should say that you failed to
  supply a required argument (duh).
* Right now, global options *must* precede a subcommand, and
  subcommand-specific options *must* follow it.  I'm okay with the latter
  (putting a subcommand option before the name of the subcommand would feel
  weird), but the former just messed with my head for like half an hour before
  I realized I was just putting the `--pretend` in the wrong place.  That's
  bound to bite other users as well, so consider doing _something_ to alleviate
  that.  I think the only solution might be to add all the global options to
  each subcommand (which is doable; cf the "global opts hash" stash), but then
  you have to deal with the weirdness of people providing an option in both
  places and then what if they have different values?  Needs further
  consideration.
* If you `SH` something, and the something is a Perl script, and the Perl
  script `die`s, you get a radically different (and much uglier) error message.
  That sux.  I'm still not entirely sure why a `die` from Perl is treated
  differently than any other error exit, and I'm not sure if that's
  PerlX::bash's fault, or autodie's fault, or IPC::System::Simple's fault ...
  Either way, it needs to be fixed, or at least the turd needs to be polished
  before passing it on to the user.
