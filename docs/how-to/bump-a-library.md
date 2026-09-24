# How to change the version of a library ze0 carries

This guide shows you how to move one of ruby's pure-Ruby libraries,
such as `csv` or `uri`, to another version. ze0 reads these libraries
from installed gems and compiles them into programs. `ze0.gemspec`
pins each one to one version, and `lib/ze0/library_digests.rb` records
the files of that version.

A gem with a C extension is different: see
[How to port a C extension](port-a-c-extension.md).

## 1. Change the pin

Change the version in `PINS` in `lib/ze0/libraries.rb`. The gemspec
reads its dependencies from there.

To carry a new library, add its gem to `PINS`. If the gem does not
keep its files in its `require_paths`, name its directories in
`DIRS`.

## 2. Lock and install

```
bundle lock
bundle install
```

Commit `Gemfile.lock` with the change.

## 3. Write the digests again

```
bundle exec rake gen:libraries
```

The task finds each pinned gem as a build does, and writes the SHA-256
of its files. A build refuses a gem whose files do not have this
digest, so a build that runs before this step stops by name.

## 4. Run the checks the change reaches

```
bundle exec rake affected
```

A change to the pins reaches every spec. When ruby answers a program
another way with the new version, record that program again, as
[How to add a spec](add-a-spec.md) shows.

## A new ruby

A new ruby moves every pin at once. Pin each default and bundled gem
to the version the new ruby ships (`gem list` names them), and copy
the files named in `vendor/lib/VERSIONS` from the new ruby, unedited.
