# Programs ze0 does not get right yet

Each file here is a Ruby program whose answer under `__END__` was recorded
from **ruby**, and which ze0 does not currently match.

To see where one stands, run it both ways:

```console
$ ruby test/gaps/<name>.rb
$ bin/ze0 test test/gaps/<name>.rb --show 40
```

`bin/ze0 test gaps` runs the whole directory. A gap lands in `refused`,
`diverged`, `crashed` or `timeout` — the buckets every other suite counts as
defects. Here they say the gap is still open, and a gap that matches is the
news worth having.

There is no promote command. The day a gap starts matching, move it by hand:
`git mv` the program into the topic directory it belongs in
(`test/core/string/`, `test/lang/blocks/`, and so on), then run it there to
confirm the recording still holds.

A gap that hangs is bounded by the sweep's ordinary limit: not matching is
the answer this directory wants, and a hang gives it as well as a crash does,
while making the whole suite wait for it.
