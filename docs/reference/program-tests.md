# Program tests

A program test is a plain Ruby program under `test/programs/`, with
files beside it that give what the pinned ruby does with it. The test
builds the program with zr, runs the binary, and compares its stdout,
its stderr and its exit status with ruby's, byte for byte.

`test/programs_test.rb` defines one minitest test for each program.
`test/support/program_case.rb` defines the format,
`test/support/program_run.rb` the run directory,
`test/support/program_build.rb` the build, and
`test/support/programs.rb` the check. For the steps to add a test, see
[How to add a program test](../how-to/add-a-program-test.md).

## The files of a test

A program is a `.rb` file and nothing else: no header and no DSL.
`ruby foo.rb` runs it. Thus the program that you debug is the program
that the test builds.

The names of the files beside it come from
[spinel](https://github.com/matz/spinel), a Ruby compiler, so a spinel
test directory runs as it is:

| File | Contains | When the file is not there |
|---|---|---|
| `foo.rb` | the program | |
| `foo.rb.expected` | its stdout | the program is not a test |
| `foo.rb.err.expected` | its stderr | the stderr is empty |
| `foo.rb.args` | its arguments, separated by white space | no arguments |
| `foo.rb.stdin` | the bytes of its stdin | the stdin is empty |

zr adds these files, in the same style:

| File | Contains | When the file is not there |
|---|---|---|
| `foo.rb.status` | `exit N`, or `signal N` for a program that a signal stopped | `exit 0` |
| `foo.rb.env` | `NAME=value` lines, added to the program's environment | nothing is added |
| `foo.rb.files/` | a tree of files that the run directory holds (the fixtures) | no files |
| `foo.rb.needs` | what the machine must have, one item on each line: `libssl`, `nonroot` (a user that is not root), or a platform (`macos`, `linux`, `wasi`) | the test runs everywhere |
| `foo.rb.ruby` | command-line options for ruby only, such as `-W:no-experimental`; zr ignores them | no options |
| `foo.rb.limits` | `build_mb=N` and `run_mb=N` lines: memory limits above the defaults | the defaults |
| `foo.rb.gems` | `name version` lines: another version of a gem whose C zr ports, which ruby takes on `-I` and the build with `--gem` | the version in `vendor/ruby` |
| `foo.rb.<platform>.expected` | the stdout on that platform (`linux`, `wasi`), when it is different | `foo.rb.expected` |

In `.env`, `.needs`, `.limits` and `.gems`, an empty line and a line
that starts with `#` do not count.

Nothing is escaped and nothing has a marker. Thus a program can write
any bytes (binary output, invalid UTF-8, a last line with no newline),
and a wrong output is a diff of two files.

A `.rb` file below a `foo.rb.files/` directory is a fixture, not a
test.

## Areas

| Directory | Contains | How zr builds it |
|---|---|---|
| `test/programs/lang/` | the language | in the worker process |
| `test/programs/core/` | the core classes | in the worker process |
| `test/programs/stdlib/` | the standard library and the ports | in the worker process |
| `test/programs/compiler/` | what zr does with a program: caches, fusion, guards | in the worker process |
| `test/programs/cli/` | the product: `zr build`, the link, ARGV, signals, sockets, the flush at exit | with `zr build`, in its own process, as a user builds it |
| `test/programs/native/` | programs that only a native target runs (`.needs` gives `macos` and `linux`) | in the worker process |

An area has a directory for each subject, and a directory for each
group of the subject. For example,
`test/programs/core/string/blocks/` holds the programs about String
and blocks, one program for each behavior.

`ProgramBuild.cli?` selects the build: a test below `cli/` runs
`exe/zr build <program> -o <binary> --target <triple>` in the run
directory. Any other test builds in the worker process, because a new
ruby for each test loads the whole compiler each time.

## Expected output

The ruby that `.ruby-version` names is the only source of expected
output. Never write an expected file yourself. `zr-dev expect`
(`tool/expect.rb`) runs each program under that ruby, in a run directory as the test does, and
writes the files:

```console
$ bin/zr-dev expect                              # each test whose program is newer
$ bin/zr-dev expect test/programs/core/string    # an area
$ bin/zr-dev expect --all test/programs/lang     # write again, also when not newer
$ bin/zr-dev expect --check                      # write nothing; list what differs
```

- It always writes `foo.rb.expected`. It writes `foo.rb.err.expected`
  only when the stderr is not empty, and `foo.rb.status` only when the
  status is not `exit 0`. It removes a file that is no longer
  necessary.
- On Linux, it writes `foo.rb.linux.expected` when the stdout is not
  the same as `foo.rb.expected`.
- Without `--all`, it writes only a test that has no `foo.rb.expected`,
  or whose `foo.rb.expected` is older than the program. After a change
  to `.args`, `.env`, `.stdin` or `.files/` alone, give `--all` and the
  path.
- When ruby does not finish, the old files stay.
- It runs ruby with only the reference gems
  (`test/support/harness/reference.rb`, `tool/install_reference_gems.rb`), and the
  options of `foo.rb.ruby`.

`zr-dev expect --check` fails when a file is different from ruby's
output.

## The run directory

Each run of a program, by ruby or by zr, gets a new directory
(`ProgramRun.within`). Thus no run sees what another run wrote.

1. The runner makes a temporary directory, and a `run/` directory in
   it. It uses the real path, because on macOS `/var` is a link to
   `/private/var`.
2. It copies the program to `run/<rel>`, where `<rel>` is the path of
   the program below `test/programs` (for example
   `core/string/blocks/foo.rb`).
3. It copies the tree of `foo.rb.files/` into `run/`. A symbolic link
   stays a link. A file that must be beside the program goes in
   `foo.rb.files/<directory of rel>/`.
4. It starts the program in `run/`, as `ruby <rel> <args>` or as the
   binary with the same arguments. Thus `__FILE__` and a backtrace give
   `<rel>`.

The program gets the environment that `bin/minitest` started with, before
bundler (`Harness::CleanEnv`), with the lines of `foo.rb.env` added.

## Normalization

Before a comparison, the runner changes the parts of an output that
change from run to run (`Harness::Normalize`). It does the same to the
output of ruby and of zr, so `zr-dev expect` writes the normalized
bytes.

- CRLF becomes LF.
- The absolute path of the program becomes its path relative to the run
  directory.
- The run directory and its `/` are removed from each path.
- A hexadecimal number of 8 to 16 digits after `0x` becomes `0xADDR`.
  This removes object addresses, as in `#<Object:0x000000012a0b1c28>`.

## Limits

| Limit | Default | Change it with |
|---|---|---|
| the time of one run | 60 s | `ZR_TEST_SECONDS` |
| the time of a ruby run | two times the run limit | `ZR_TEST_SECONDS` |
| the time of a `zr build` (`cli/` only) | five times the run limit | `ZR_TEST_SECONDS` |
| the memory of a run | 1024 MB | `ZR_TEST_RUN_MB`, or `run_mb=` in `foo.rb.limits` |
| the memory of a `zr build` (`cli/` only) | 2048 MB | `ZR_TEST_BUILD_MB`, or `build_mb=` in `foo.rb.limits` |
| the time of one test in a worker | 180 s | `ZR_TEST_TIMEOUT` |

A value in `foo.rb.limits` applies only when it is higher than the
default. The memory limit is the resident size of the whole process
group.

## Results

minitest prints one character for each test, as it ends:

| Mark | Result | Cause |
|---|---|---|
| `.` | pass | stdout, stderr, the exit status and the signal are all ruby's |
| `F` | fail | the output is different; or a test in the baseline passes |
| `E` | error | zr does not build or run the program: a refusal, a backend error, a trap, a time limit, a memory limit, a failed `zr build`, or a worker that died |
| `S` | skip | this machine cannot run the test (`.needs`, or no wasmtime for a WASI target); or the baseline allows its failure |

A refusal is an error, not a skip. A program that stops at run time
with `... is not implemented yet` is also a refusal. The baseline of
the target lists each refusal that the target may have.

Each program is one minitest test, named
`test_<path below test/programs>`. After the marks, minitest prints
each failure and each error, and then a count:

```
ProgramsTest#test_core/string/blocks/foo.rb
--- expected stdout
+++ actual stdout
 a
-b
+c

12 runs, 12 assertions, 1 failures, 0 errors, 0 skips
```

The detail is a unified diff of each part that is different (stderr,
then stdout), and a `status:` line when the exit status or the signal
is different. For outputs of more than 2,000 lines, the diff shows only
the first difference, with its context. An error gives the reason that
zr did not build or run the program. A skip gives its reason (the
baseline, or a need that this machine does not meet); minitest's `-v`
shows it. The command exits with status 1 when a test failed or had an
error.

To run one failure again, give its path below `test/programs` to
`ZR_PROGRAMS`:

```console
$ ZR_PROGRAMS=core/string/blocks/foo.rb bin/minitest test/programs_test.rb
```

## Baselines

A target can be allowed to fail some tests. Its baseline file is
`test/baselines/<triple>.txt` (`test/support/baseline.rb`). The host,
`aarch64-apple-darwin`, has one too. Each line has a key, a tab, and
the reason. The key is the path of the program below `test/programs`.
A line that starts with `#` is a comment:

```
# wasi has no processes and no signals.
cli/core/process/process_spawn.rb	spawn() is unimplemented on wasi
```

- A test in the baseline that fails or has an error is a skip, with
  the reason.
- A test in the baseline that **passes** fails, with the message
  `this now passes: take it off test/baselines/<triple>.txt`. Thus the
  file cannot become out of date.

See [How to test on another target](../how-to/test-on-another-target.md).

## Workers

The parent process loads zr and the runtime, and then forks workers
(`Zr::Test::ForkPool`). Each worker takes one test at a time, so a
worker builds a test in its process and loads nothing again. `MT_CPU`
sets the number of workers (`test/support/workers.rb`). A worker that
grows more than `ZR_TEST_RECYCLE_MB` stops, and the parent forks a new
one. A worker
that runs one test longer than `ZR_TEST_TIMEOUT` stops, and its test
has an error.

A test that builds in the worker process uses a kept binary when its
inputs did not change (`test/support/binaries.rb`, `ZR_TEST_BINARIES`).
