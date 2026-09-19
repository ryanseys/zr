# Coverage's line counts. A program that names Coverage is compiled with
# its :line events, and while coverage is set up every one comes here.
# A file takes part when its first event comes from its toplevel, which
# runs as the file loads: a file loaded before Coverage.setup has no
# toplevel left to run. Its counts grow as lines run while coverage runs.

# `rows` holds one CovRow per file seen; `last` is the row the last
# event counted in, which the next event is most likely to share.
Machine.struct :Coverage, rows: Ptr, len: Word, capa: Word, setup: Word, running: Word, last: Ptr, branches: Ptr, branch_size: Word
# `file` is the FrameMeta's file bytes, one address per file a lowering
# made. `counts` holds `size` words, a count for each line from 1.
Machine.struct :CovRow, file: Ptr, file_len: Word, counts: Ptr, size: Word, measured: Word

sig [] => Ptr
machine def zr_coverage
  Machine.static(:coverage, Coverage.size)
end

sig [] => Bool
machine def zr_coverage_setup_p
  Coverage.setup(zr_coverage()) != 0
end

# Coverage.setup, resume and suspend: `state` is 0 idle, 1 set up and
# suspended, 2 running. Going idle forgets every file.
sig [Value] => Value
machine def zr_coverage_state_set(state)
  c = zr_coverage()
  n = zr_fix2long(state)
  if n == 0
    zr_coverage_forget(c)
  end
  Coverage.set_setup(c, n == 0 ? 0 : 1)
  Coverage.set_running(c, n == 2 ? 1 : 0)
  zr_trace_events_arm()
  Machine.value(QNIL)
end

sig [Ptr] => Void
machine def zr_coverage_forget(c)
  i = 0
  while i < Coverage.len(c)
    counts = CovRow.counts(Coverage.rows(c) + (i * CovRow.size))
    if counts != 0
      zr_xfree(counts)
    end
    i += 1
  end
  Coverage.set_len(c, 0)
  Coverage.set_last(c, 0)
  if Coverage.branches(c) != 0
    zr_xfree(Coverage.branches(c))
  end
  Coverage.set_branches(c, 0)
  Coverage.set_branch_size(c, 0)
end

# The row of the file whose bytes are at `file`, made now when the file
# is new: measured when the event came from its toplevel.
sig [Ptr, Ptr, Word, Bool] => Ptr
machine def zr_coverage_row(c, file, file_len, toplevel)
  last = Coverage.last(c)
  if last != 0 && CovRow.file(last) == file
    return last
  end
  i = 0
  while i < Coverage.len(c)
    row = Coverage.rows(c) + (i * CovRow.size)
    if CovRow.file(row) == file
      Coverage.set_last(c, row)
      return row
    end
    i += 1
  end
  if Coverage.len(c) == Coverage.capa(c)
    capa = Coverage.capa(c) == 0 ? 16 : Coverage.capa(c) * 2
    rows = zr_xmalloc(capa * CovRow.size)
    if Coverage.len(c) > 0
      zr_memcpy(rows, Coverage.rows(c), Coverage.len(c) * CovRow.size)
      zr_xfree(Coverage.rows(c))
    end
    Coverage.set_rows(c, rows)
    Coverage.set_capa(c, capa)
  end
  row = Coverage.rows(c) + (Coverage.len(c) * CovRow.size)
  Coverage.set_len(c, Coverage.len(c) + 1)
  CovRow.set_file(row, file)
  CovRow.set_file_len(row, file_len)
  CovRow.set_counts(row, 0)
  CovRow.set_size(row, 0)
  CovRow.set_measured(row, toplevel ? 1 : 0)
  Coverage.set_last(c, row)
  row
end

# A :line event in frame `rec`: one more run of its line, in a file
# coverage measures, while coverage runs.
sig [Ptr] => Void
machine def zr_coverage_line(rec)
  c = zr_coverage()
  if Coverage.setup(c) == 0 || rec == 0
    return
  end
  meta = Frame.meta(rec)
  if FrameMeta.file_len(meta) == 0
    return
  end
  row = zr_coverage_row(c, FrameMeta.file(meta), FrameMeta.file_len(meta), FrameMeta.kind(meta) == KIND_TOP)
  line = zr_frame_line(rec)
  if CovRow.measured(row) == 0 || Coverage.running(c) == 0 || line <= 0
    return
  end
  if line > CovRow.size(row)
    size = line * 2
    counts = zr_xmalloc(size * 8)
    memset(counts, Machine.i32(0), size * 8)
    if CovRow.counts(row) != 0
      zr_memcpy(counts, CovRow.counts(row), CovRow.size(row) * 8)
      zr_xfree(CovRow.counts(row))
    end
    CovRow.set_counts(row, counts)
    CovRow.set_size(row, size)
  end
  slot = CovRow.counts(row) + ((line - 1) * 8)
  Machine.store64(slot, 0, Machine.load64(slot, 0) + 1)
end

# One run of branch `id`, while coverage runs. The branches of every
# file share one array, and the branch table a program carries says
# which of them are whose, so the count is a store and no lookup: this
# stands on every side of every branch a measured file holds.
#
# Whether the file took part is decided once, where its lines are
# counted (`measured`), and the Ruby half leaves out the branches of a
# file whose lines it left out.
sig [Word] => Void
machine def zr_coverage_branch(id)
  c = zr_coverage()
  if Coverage.running(c) == 0
    return
  end
  if id >= Coverage.branch_size(c)
    size = (id + 1) * 2
    counts = zr_xmalloc(size * 8)
    memset(counts, Machine.i32(0), size * 8)
    if Coverage.branches(c) != 0
      zr_memcpy(counts, Coverage.branches(c), Coverage.branch_size(c) * 8)
      zr_xfree(Coverage.branches(c))
    end
    Coverage.set_branches(c, counts)
    Coverage.set_branch_size(c, size)
  end
  slot = Coverage.branches(c) + (id * 8)
  Machine.store64(slot, 0, Machine.load64(slot, 0) + 1)
end

# Every branch counter, by id, up to the last one that ran; `clear`
# zeroes them after.
sig [Value] => Value
machine def zr_coverage_branch_counts(clear)
  c = zr_coverage()
  out = zr_ary_new(Coverage.branch_size(c))
  i = 0
  while i < Coverage.branch_size(c)
    zr_ary_push(out, zr_fix(Machine.load64(Coverage.branches(c) + (i * 8), 0)))
    i += 1
  end
  if clear == QTRUE && Coverage.branches(c) != 0
    memset(Coverage.branches(c), Machine.i32(0), Coverage.branch_size(c) * 8)
  end
  out
end

# Every measured file as `[path, counts]`, a count for each line from 1
# up to the last line that ran; `clear` zeroes the counts after.
sig [Value] => Value
machine def zr_coverage_counts(clear)
  c = zr_coverage()
  out = zr_ary_new(Coverage.len(c))
  i = 0
  while i < Coverage.len(c)
    row = Coverage.rows(c) + (i * CovRow.size)
    if CovRow.measured(row) != 0
      counts = zr_ary_new(CovRow.size(row))
      j = 0
      while j < CovRow.size(row)
        zr_ary_push(counts, zr_fix(Machine.load64(CovRow.counts(row) + (j * 8), 0)))
        j += 1
      end
      if clear == QTRUE && CovRow.counts(row) != 0
        memset(CovRow.counts(row), Machine.i32(0), CovRow.size(row) * 8)
      end
      pair = zr_ary_new(2)
      zr_ary_push(pair, zr_str_new(CovRow.file(row), CovRow.file_len(row)))
      zr_ary_push(pair, counts)
      zr_ary_push(out, pair)
    end
    i += 1
  end
  out
end
