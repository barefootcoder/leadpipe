# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Pb (Leadpipe)** is a workflow system that combines Perl and bash, allowing developers to write devops/control scripts with the job control power of bash and the programming sophistication of Perl. It's distributed as a CPAN module under the name "Pb".

The project uses a declarative DSL-style syntax (without source filters) to define commands with:
- Subcommands (git-style)
- Validated command-line options and arguments
- Workflows composed of directives (SH, CODE, RUN)
- Pre-command verification
- Automatic logging, pidfiles, and status tracking
- Interactive and pretend modes

## Code Architecture

### Core Components

**lib/Pb.pm** - Main module that provides the DSL syntax
- Exports keywords: `command`, `base_command`, `flow`, `arg`, `opt`, `verify`, `SH`, `CODE`, `RUN`
- Exports global variables: `$FLOW` (context object), `%OPT` (options hash)
- Uses CLI::Osprey for command-line parsing
- Uses Type::Tiny for argument/option validation
- Uses PerlX::bash for shell command execution
- The `command` function builds subcommands dynamically using Moo packages
- Signal handling setup ensures END blocks run even on signal termination

**lib/Pb/Command/Context.pm** - Context object for command execution
- Manages context variables (accessible via `$FLOW->{var}`)
- Handles runmode (ACTION, NOACTION, ASKACTION)
- Manages control structures (pidfiles, statusfiles, clean exit tracking)
- Validates arguments and options against Type::Tiny constraints
- Overloads `%{}` to act like a hash while being an object
- Uses `Clone` to create per-command contexts from the global template

### Key Design Patterns

1. **Context Cloning**: Global `$FLOW` is cloned for each command invocation, adding command-specific vars and options
2. **Deferred Execution**: Flows are stored as closures in `%FLOWS` and executed when the command runs
3. **Runmode Control**: All directives check `_should_doit()` to support pretend/interactive modes
4. **Error Handling**: Uses `autodie` throughout; `bash` calls from PerlX::bash die on non-zero exit by default
5. **Optional Invocant**: Functions use `_pb_args` to work as both object methods and plain functions via global `$CMD`

## Building and Testing

### Development Commands

```bash
# Build the distribution (requires Dist::Zilla with @BAREFOOT bundle)
dzil build

# Run all tests
dzil test

# Run specific test file
prove -lv t/basic.t

# Install locally for testing
dzil install
```

### Test Infrastructure

Tests use **Test::Pb::Bin** (t/Test/Pb/Bin.pm) which provides:
- `pb_basecmd($name, $code)` - Creates executable test command
- `pb_run(@args)` - Runs command and captures output via Test::Trap
- `pb_run_interactive($answers)` - Runs with interactive mode, providing y/n answers
- `check_output($trap, @lines, $testname)` - Validates clean exit with expected output
- `check_error($trap, $exit, @lines, $testname)` - Validates error exit with expected stderr

All tests create temporary commands in `$TMPDIR` that use the development version of Pb.pm.

### Distribution Configuration

**dist.ini** uses Dist::Zilla with the `@BAREFOOT` bundle (author's custom plugin bundle). The module is:
- Named "Pb" on CPAN
- Licensed under Artistic_2_0
- Requires IPC::System::Simple >= 1.23
- Requires Getopt::Long::Descriptive >= 0.100

## Common Workflow Patterns

### Command Definition Structure

```perl
command 'name' =>
    arg argname => must_be Type,
    opt optname => must_be Type,
    log_to '/path/to/log/%DATE-%TIME.log',
    control_via { pidfile => '/var/run/cmd.pid', statusfile => '...' },
flow
{
    verify { condition } 'error message if false';
    SH shell => commands;
    CODE sub { perl code; return 1; };
    RUN 'other-command' => @args;
};
```

### Type Validation

- `must_be Type` - Wraps any Type::Tiny type with custom error messages
- `one_of [values]` - Creates Type::Tiny::Enum for argument/option validation
- `also(properties)` - Adds extra properties to options (e.g., `also(-access_as_var)`)

### Context Variables

Context vars use `%` expansion in strings passed to control structure:
- `%DATE` - Command start date (YYYYMMDD)
- `%TIME` - Command start timestamp (YYYYMMDDHHMMSS)
- `%ME` - Command basename (from `invoked_as`)
- Custom vars set via `$FLOW->set_var($name, $value)`

## Important Notes

### Error Handling Bug

There's a known issue (see TODO.md and recent commits) where Perl scripts called via `SH` that `die()` produce ugly error messages. The recent fix (commit ec52d92) ensures Perl `die` causes a bash failure rather than an exception, but error message formatting could still be improved.

### Testing in Non-English Locales

The test suite uses `%ERRNO` hash (in Test::Pb::Bin) to handle locale-specific error messages, particularly for ENOENT ("No such file or directory"). This ensures tests pass regardless of system locale.

### Global vs Command-Specific Options

- Global options (like `--pretend`, `--interactive`) are defined at package level
- Command options are defined in `command` declarations
- All options are read-only (`is => 'ro'`)
- Options must precede subcommand name on command line (known limitation)

### Signal Handling

Pb sets up comprehensive signal handlers to ensure END blocks run even on termination signals, which is critical for cleaning up pidfiles and writing statusfiles.
