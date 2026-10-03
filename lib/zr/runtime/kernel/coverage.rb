# Coverage line counts. The compiler adds :line events to a program that
# refers to Coverage. While coverage is set up, each event comes here. A
# file is measured when its first event comes from its toplevel, which
# runs when the file loads. A file loaded before Coverage.setup has no
# toplevel left to run. Its counts increase as lines run while coverage
# runs.

module Zr::Kern
  # `rows` contains one CovRow record for each file seen. `last` is the
  # record of the last event, which is most probably the record of the
  # next event.
  Coverage = layout rows: Ptr, len: Word, capa: Word, setup: Word, running: Word, last: Ptr, branches: Ptr, branch_size: Word
  # `file` is the FrameMeta's file bytes, one address for each file that a
  # lowering made. `counts` contains `size` words, a count for each line
  # from 1.
  CovRow = layout file: Ptr, file_len: Word, counts: Ptr, size: Word, measured: Word

  #: () -> ptr
  def zr_coverage
    Machine.static(:coverage, Coverage.size)
  end

  #: () -> bool
  def zr_coverage_setup_p
    Coverage.setup(zr_coverage()) != 0
  end

  # Coverage.setup, resume and suspend. `state` is 0 idle, 1 set up and
  # suspended, 2 running. A change to idle discards all files.
  #: (value) -> value
  def zr_coverage_state_set(state)
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

  #: (ptr) -> void
  def zr_coverage_forget(c)
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
    rows = zr_global(G_COVERAGE_METHODS)
    if !zr_special_p(rows) && zr_type(rows) == T_ARRAY
      i = 3
      while i < RArray.len(rows)
        zr_ary_store(rows, i, zr_fix(0))
        i += 4
      end
    end
  end

  # The record of the file whose bytes are at `file`. If the file is new,
  # this makes the record. The file is measured if the event came from its
  # toplevel.
  #: (ptr, ptr, word, bool) -> ptr
  def zr_coverage_row(c, file, file_len, toplevel)
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

  # A :line event in frame `rec`. Adds one run to its line, if coverage
  # measures the file and coverage runs.
  #: (ptr) -> void
  def zr_coverage_line(rec)
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
      Libc.memset(counts, Machine.i32(0), size * 8)
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

  # Adds one run to branch `id` while coverage runs. The branches of all
  # files share one array. The program's branch table gives the file of
  # each branch, so the count is a store with no lookup. This call is on
  # each side of each branch in a measured file.
  #
  # The line count decides one time if a file is measured (`measured`).
  # The Ruby part does not report the branches of a file whose lines it
  # does not report.
  #: (word) -> void
  def zr_coverage_branch(id)
    c = zr_coverage()
    if Coverage.running(c) == 0
      return
    end
    if id >= Coverage.branch_size(c)
      size = (id + 1) * 2
      counts = zr_xmalloc(size * 8)
      Libc.memset(counts, Machine.i32(0), size * 8)
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

  # All branch counters, by id, up to the last one that ran. If `clear` is
  # set, this sets them to zero after it reads them.
  #: (value) -> value
  def zr_coverage_branch_counts(clear)
    c = zr_coverage()
    out = zr_ary_new(Coverage.branch_size(c))
    i = 0
    while i < Coverage.branch_size(c)
      zr_ary_push(out, zr_fix(Machine.load64(Coverage.branches(c) + (i * 8), 0)))
      i += 1
    end
    if clear == QTRUE && Coverage.branches(c) != 0
      Libc.memset(Coverage.branches(c), Machine.i32(0), Coverage.branch_size(c) * 8)
    end
    out
  end

  # Each measured file as `[path, counts]`, with a count for each line from
  # 1 to the last line that ran. If `clear` is set, this sets the counts to
  # zero after it reads them.
  #: (value) -> value
  def zr_coverage_counts(clear)
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
          Libc.memset(CovRow.counts(row), Machine.i32(0), CovRow.size(row) * 8)
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

  # The methods that Coverage reports: the definitions that ran while it
  # was set up. Each one has a record of four words, `[def-site id, owner,
  # name, count]`, in one flat global Array, so the collector keeps the
  # owners. The records stay after a `forget`, because a method entry
  # refers to its record by position, and zr never measures a file two
  # times. A `forget` and a `clear` discard only the counts.
  G_COVERAGE_METHODS = 53

  #: () -> value
  def zr_coverage_method_rows
    rows = zr_global(G_COVERAGE_METHODS)
    if zr_special_p(rows) || zr_type(rows) != T_ARRAY
      rows = zr_ary_new(64)
      zr_set_global(G_COVERAGE_METHODS, rows)
    end
    rows
  end

  # Records a definition of `mid` on `klass` from the scope `meta`. The
  # method entry keeps the position of the record. A scope that is not
  # from a measured file has no def-site id and gets no record.
  #: (value, word, ptr) -> void
  def zr_coverage_method_claim(klass, mid, meta)
    c = zr_coverage()
    if Coverage.setup(c) == 0 || meta == 0 || FrameMeta.cover(meta) == 0
      return
    end
    e = zr_find_method_at(zr_origin(klass), mid)
    if e == 0
      return
    end
    rows = zr_coverage_method_rows()
    MEntry.set_cover(e, (RArray.len(rows) / 4) + 1)
    zr_ary_push(rows, zr_fix(FrameMeta.cover(meta) - 1))
    zr_ary_push(rows, zr_origin(klass))
    zr_ary_push(rows, zr_sym(mid))
    zr_ary_push(rows, zr_fix(0))
  end

  # Adds one run to the method of entry `e` while coverage runs. CRuby
  # counts the same on the :call event, for a def and for a
  # `define_method` block. An alias keeps the record of its original, as
  # CRuby resolves an alias to the entry it was made from.
  #: (ptr) -> void
  def zr_coverage_method(e)
    c = zr_coverage()
    if Coverage.running(c) == 0 || MEntry.cover(e) == 0
      return
    end
    rows = zr_global(G_COVERAGE_METHODS)
    i = ((MEntry.cover(e) - 1) * 4) + 3
    zr_ary_store(rows, i, zr_fix(zr_fix2long(zr_ary_at(rows, i)) + 1))
  end

  # All method records, as the Ruby part reads them. If `clear` is set,
  # this sets the counts to zero after it reads them. The records stay at
  # their positions, because the method entries point to them.
  #: (value) -> value
  def zr_coverage_method_counts(clear)
    rows = zr_coverage_method_rows()
    out = zr_ary_new(RArray.len(rows))
    i = 0
    while i < RArray.len(rows)
      zr_ary_push(out, zr_ary_at(rows, i))
      i += 1
    end
    if clear == QTRUE
      i = 3
      while i < RArray.len(rows)
        zr_ary_store(rows, i, zr_fix(0))
        i += 4
      end
    end
    out
  end
end
