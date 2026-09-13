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

Every other suite holds only programs ze0 matches, so a sweep of them reads
as a pass and a new failure there is news. A program that stops matching
comes here, with `tools/gap.rb`:

```console
$ ruby tools/gap.rb core/string/a_case.rb   # these programs
$ ruby tools/gap.rb --sweep tmp/sweep.txt   # every row a sweep did not match
```

The tool rewrites the recording's own path and every relative path the
program names, carries a helper directory named after the program along
with it, and asks ruby for the answer in both places. A move stands only
when ruby's answer is the same once the path is. `ORIGINS.tsv` records the
topic each gap came from.

There is no promote command. The day a gap starts matching, move it back by
hand: `git mv` the program into the topic `ORIGINS.tsv` names (and its
helper directory, if it has one), undo any relative path the move rewrote,
drop its `ORIGINS.tsv` row, then run it there to confirm the recording still
holds.

A gap that hangs is bounded by the sweep's ordinary limit: not matching is
the answer this directory wants, and a hang gives it as well as a crash does,
while making the whole suite wait for it.
