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
  class Coverage < Layout
    attr_accessor :rows #: ptr
    attr_accessor :len #: word
    attr_accessor :capa #: word
    attr_accessor :setup #: word
    attr_accessor :running #: word
    attr_accessor :last #: ptr
    attr_accessor :branches #: ptr
    attr_accessor :branch_size #: word
  end
  # `file` is the FrameMeta's file bytes, one address for each file that a
  # lowering made. `counts` contains `size` words, a count for each line
  # from 1.
  class CovRow < Layout
    attr_accessor :file #: ptr
    attr_accessor :file_len #: word
    attr_accessor :counts #: ptr
    attr_accessor :size #: word
    attr_accessor :measured #: word
  end

  #: () -> ptr
  def zr_coverage
    Machine.static(:coverage, Coverage.size)
  end

  #: () -> bool
  def zr_coverage_setup_p
    Coverage[zr_coverage()].setup != 0
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
    Coverage[c].setup = n == 0 ? 0 : 1
    Coverage[c].running = n == 2 ? 1 : 0
    zr_trace_events_arm()
    Machine.value(QNIL)
  end

  # `eval: true`: the code that eval compiles is measured too.
  #: (value) -> value
  def zr_coverage_evals_set(on)
    Machine.store64(Machine.static(:coverage_evals, 8), 0, on == QTRUE ? 1 : 0)
    on
  end

  #: (ptr) -> void
  def zr_coverage_forget(c)
    i = 0
    while i < Coverage[c].len
      counts = CovRow[Coverage[c].rows + (i * CovRow.size)].counts
      if counts != 0
        zr_xfree(counts)
      end
      i += 1
    end
    Coverage[c].len = 0
    Coverage[c].last = 0
    if Coverage[c].branches != 0
      zr_xfree(Coverage[c].branches)
    end
    Coverage[c].branches = 0
    Coverage[c].branch_size = 0
    rows = zr_global(G_COVERAGE_METHODS)
    if !zr_special_p(rows) && zr_type(rows) == T_ARRAY
      i = 3
      while i < RArray[rows].len
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
    last = Coverage[c].last
    if last != 0 && CovRow[last].file == file
      return last
    end
    i = 0
    while i < Coverage[c].len
      row = Coverage[c].rows + (i * CovRow.size)
      if CovRow[row].file == file
        Coverage[c].last = row
        return row
      end
      i += 1
    end
    if Coverage[c].len == Coverage[c].capa
      capa = Coverage[c].capa == 0 ? 16 : Coverage[c].capa * 2
      rows = zr_xmalloc(capa * CovRow.size)
      if Coverage[c].len > 0
        zr_memcpy(rows, Coverage[c].rows, Coverage[c].len * CovRow.size)
        zr_xfree(Coverage[c].rows)
      end
      Coverage[c].rows = rows
      Coverage[c].capa = capa
    end
    row = Coverage[c].rows + (Coverage[c].len * CovRow.size)
    Coverage[c].len = Coverage[c].len + 1
    CovRow[row].file = file
    CovRow[row].file_len = file_len
    CovRow[row].counts = 0
    CovRow[row].size = 0
    CovRow[row].measured = toplevel ? 1 : 0
    Coverage[c].last = row
    row
  end

  # A :line event in frame `rec`. Adds one run to its line, if coverage
  # measures the file and coverage runs.
  #: (ptr) -> void
  def zr_coverage_line(rec)
    c = zr_coverage()
    if Coverage[c].setup == 0 || rec == 0
      return
    end
    meta = Frame[rec].meta
    if FrameMeta[meta].file_len == 0
      return
    end
    kind = FrameMeta[meta].kind
    toplevel = kind == KIND_TOP || (kind == KIND_EVAL && Machine.load64(Machine.static(:coverage_evals, 8), 0) != 0)
    row = zr_coverage_row(c, FrameMeta[meta].file, FrameMeta[meta].file_len, toplevel)
    line = zr_frame_line(rec)
    if CovRow[row].measured == 0 || Coverage[c].running == 0 || line <= 0
      return
    end
    if line > CovRow[row].size
      size = line * 2
      counts = zr_xmalloc(size * 8)
      Libc.memset(counts, Machine.i32(0), size * 8)
      if CovRow[row].counts != 0
        zr_memcpy(counts, CovRow[row].counts, CovRow[row].size * 8)
        zr_xfree(CovRow[row].counts)
      end
      CovRow[row].counts = counts
      CovRow[row].size = size
    end
    slot = CovRow[row].counts + ((line - 1) * 8)
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
    if Coverage[c].running == 0
      return
    end
    if id >= Coverage[c].branch_size
      size = (id + 1) * 2
      counts = zr_xmalloc(size * 8)
      Libc.memset(counts, Machine.i32(0), size * 8)
      if Coverage[c].branches != 0
        zr_memcpy(counts, Coverage[c].branches, Coverage[c].branch_size * 8)
        zr_xfree(Coverage[c].branches)
      end
      Coverage[c].branches = counts
      Coverage[c].branch_size = size
    end
    slot = Coverage[c].branches + (id * 8)
    Machine.store64(slot, 0, Machine.load64(slot, 0) + 1)
  end

  # All branch counters, by id, up to the last one that ran. If `clear` is
  # set, this sets them to zero after it reads them.
  #: (value) -> value
  def zr_coverage_branch_counts(clear)
    c = zr_coverage()
    out = zr_ary_new(Coverage[c].branch_size)
    i = 0
    while i < Coverage[c].branch_size
      zr_ary_push(out, zr_fix(Machine.load64(Coverage[c].branches + (i * 8), 0)))
      i += 1
    end
    if clear == QTRUE && Coverage[c].branches != 0
      Libc.memset(Coverage[c].branches, Machine.i32(0), Coverage[c].branch_size * 8)
    end
    out
  end

  # A later eval into the file `path` was compiled: each line in `lines`
  # (an Array of Fixnums) starts from zero again, in every record of the
  # file, as CRuby's compiler sets the line's count to 0.
  #: (value, value) -> value
  def zr_coverage_reset(path, lines)
    c = zr_coverage()
    i = 0
    while i < Coverage[c].len
      row = Coverage[c].rows + (i * CovRow.size)
      if zr_bytes_eq(CovRow[row].file, CovRow[row].file_len, RString[path].ptr, RString[path].len)
        j = 0
        while j < RArray[lines].len
          line = zr_fix2long(zr_ary_at(lines, j))
          if line > 0 && line <= CovRow[row].size
            Machine.store64(CovRow[row].counts + ((line - 1) * 8), 0, 0)
          end
          j += 1
        end
      end
      i += 1
    end
    Machine.value(QNIL)
  end

  # Each measured file as `[path, counts]`, with a count for each line from
  # 1 to the last line that ran. If `clear` is set, this sets the counts to
  # zero after it reads them.
  #: (value) -> value
  def zr_coverage_counts(clear)
    c = zr_coverage()
    out = zr_ary_new(Coverage[c].len)
    i = 0
    while i < Coverage[c].len
      row = Coverage[c].rows + (i * CovRow.size)
      if CovRow[row].measured != 0
        counts = zr_ary_new(CovRow[row].size)
        j = 0
        while j < CovRow[row].size
          zr_ary_push(counts, zr_fix(Machine.load64(CovRow[row].counts + (j * 8), 0)))
          j += 1
        end
        if clear == QTRUE && CovRow[row].counts != 0
          Libc.memset(CovRow[row].counts, Machine.i32(0), CovRow[row].size * 8)
        end
        pair = zr_ary_new(2)
        zr_ary_push(pair, zr_str_new(CovRow[row].file, CovRow[row].file_len))
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
  G_COVERAGE_METHODS = 14

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
    if Coverage[c].setup == 0 || meta == 0 || FrameMeta[meta].cover == 0
      return
    end
    e = zr_find_method_at(zr_origin(klass), mid)
    if e == 0
      return
    end
    rows = zr_coverage_method_rows()
    MEntry[e].cover = (RArray[rows].len / 4) + 1
    zr_ary_push(rows, zr_fix(FrameMeta[meta].cover - 1))
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
    if Coverage[c].running == 0 || MEntry[e].cover == 0
      return
    end
    rows = zr_global(G_COVERAGE_METHODS)
    i = ((MEntry[e].cover - 1) * 4) + 3
    zr_ary_store(rows, i, zr_fix(zr_fix2long(zr_ary_at(rows, i)) + 1))
  end

  # All method records, as the Ruby part reads them. If `clear` is set,
  # this sets the counts to zero after it reads them. The records stay at
  # their positions, because the method entries point to them.
  #: (value) -> value
  def zr_coverage_method_counts(clear)
    rows = zr_coverage_method_rows()
    out = zr_ary_new(RArray[rows].len)
    i = 0
    while i < RArray[rows].len
      zr_ary_push(out, zr_ary_at(rows, i))
      i += 1
    end
    if clear == QTRUE
      i = 3
      while i < RArray[rows].len
        zr_ary_store(rows, i, zr_fix(0))
        i += 4
      end
    end
    out
  end
end
