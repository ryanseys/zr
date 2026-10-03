# A precise mark-sweep collector over a shadow stack of frame records, in
# the kernel subset: the shape every runtime frame will take.
#
# A cell is 32 bytes: a header (bit 0 allocated, bit 1 marked, bits 8 up
# the kind: 1 a pair of cells, 2 a leaf) and three words. Cells come from a
# static arena through a free list. A frame record is `prev, count,
# values...`, chained from a static top; the collector marks from every
# record and sweeps the arena. A freed cell is poisoned, and marking
# aborts on a reference to one: a live object pointing at a freed cell is
# a root the discipline missed. Run with any argument, it collects at
# every allocation, so a missed root cannot hide behind a lucky heap; and
# the free list starts just past the last cell handed out, so a freed
# cell is not reused until the arena has cycled and a stale pointer meets
# the poison, not a new object.
module Zr::Kern
  module Libc
    #: (i32, ptr, word) -> word
    def self.write(i, p, n) = Machine.import
    #: () -> void
    def self.abort = Machine.import
    #: (i32) -> void
    def self.exit(i) = Machine.import
  end

  #: () -> ptr
  def arena
    Machine.static(:arena, 131072)
  end

  # heap: 0 free head, 8 allocations, 16 collections, 24 stress flag,
  # 40 record top, 48 the index of the last cell handed out
  #: () -> ptr
  def heap
    Machine.static(:heap, 64)
  end

  #: (word) -> void
  def put_word(n)
    buf = Machine.slot(24)
    at = 23
    Machine.store8(buf + at, 0, Machine.i8(10))
    if n == 0
      at = at - 1
      Machine.store8(buf + at, 0, Machine.i8(48))
    end
    while n > 0
      at = at - 1
      Machine.store8(buf + at, 0, Machine.i8(48 + (n % 10)))
      n = n / 10
    end
    Libc.write(1, buf + at, 24 - at)
  end

  #: (ptr, word) -> void
  def put(bytes, n)
    Libc.write(1, bytes, n)
  end

  # Thread every cell onto the free list.
  #: () -> void
  def heap_init
    h = heap()
    a = arena()
    i = 0
    head = 0
    while i < 4096
      cell = a + (i * 32)
      Machine.store64(cell, 0, 0)
      Machine.store64(cell, 8, head)
      head = cell
      i = i + 1
    end
    Machine.store64(h, 0, head)
  end

  #: (ptr) -> void
  def mark(cell)
    if cell != 0
      header = Machine.load64(cell, 0)
      if (header & 1) == 0
        put(Machine.bytes("a live object points at a freed cell\n"), 37)
        Libc.abort()
      end
      if (header & 2) == 0
        Machine.store64(cell, 0, header | 2)
        if (header >> 8) == 1
          mark(Machine.load64(cell, 8))
          mark(Machine.load64(cell, 16))
        end
      end
    end
  end

  #: () -> void
  def mark_records
    rec = Machine.load64(heap(), 40)
    while rec != 0
      n = Machine.load64(rec, 8)
      i = 0
      while i < n
        mark(Machine.load64(rec + 16 + (i * 8), 0))
        i = i + 1
      end
      rec = Machine.load64(rec, 0)
    end
  end

  #: (word) -> void
  def free_cell(i)
    h = heap()
    cell = arena() + (i * 32)
    header = Machine.load64(cell, 0)
    if (header & 2) == 2
      Machine.store64(cell, 0, header & (0 - 3))
    else
      Machine.store64(cell, 0, 57005 << 8)
      Machine.store64(cell, 8, Machine.load64(h, 0))
      Machine.store64(cell, 16, 57005)
      Machine.store64(cell, 24, 57005)
      Machine.store64(h, 0, cell)
    end
  end

  # Push the cells in reverse, so the list pops in address order from the
  # cell after the last one handed out.
  #: () -> void
  def sweep
    h = heap()
    last = Machine.load64(h, 48)
    Machine.store64(h, 0, 0)
    i = last
    while i >= 0
      free_cell(i)
      i = i - 1
    end
    i = 4095
    while i > last
      free_cell(i)
      i = i - 1
    end
  end

  #: () -> void
  def collect
    h = heap()
    Machine.store64(h, 16, Machine.load64(h, 16) + 1)
    mark_records()
    sweep()
  end

  #: (word) -> ptr
  def alloc(kind)
    h = heap()
    if Machine.load64(h, 24) != 0
      collect()
    end
    if Machine.load64(h, 0) == 0
      collect()
    end
    cell = Machine.load64(h, 0)
    if cell == 0
      put(Machine.bytes("out of cells\n"), 13)
      Libc.abort()
    end
    Machine.store64(h, 0, Machine.load64(cell, 8))
    Machine.store64(h, 48, (cell - arena()) / 32)
    Machine.store64(cell, 0, (kind << 8) | 1)
    Machine.store64(cell, 8, 0)
    Machine.store64(cell, 16, 0)
    Machine.store64(cell, 24, 0)
    Machine.store64(h, 8, Machine.load64(h, 8) + 1)
    cell
  end

  #: () -> word
  def live
    a = arena()
    n = 0
    i = 0
    while i < 4096
      if (Machine.load64(a + (i * 32), 0) & 1) == 1
        n = n + 1
      end
      i = i + 1
    end
    n
  end

  # A list of `len` pairs whose heads are leaves, its spine kept in the
  # record while it grows. Every pair after the first hangs off the record's
  # slot 0; the leaf under construction sits in slot 1 until its pair holds it.
  #: (word) -> ptr
  def build(len)
    h = heap()
    rec = Machine.slot(32)
    Machine.store64(rec, 0, Machine.load64(h, 40))
    Machine.store64(rec, 8, 2)
    Machine.store64(rec, 16, 0)
    Machine.store64(rec, 24, 0)
    Machine.store64(h, 40, rec)
    i = 0
    while i < len
      leaf = alloc(2)
      Machine.store64(rec, 24, leaf)
      leaf = 0
      pair = alloc(1)
      Machine.store64(pair, 8, Machine.load64(rec, 24))
      Machine.store64(pair, 16, Machine.load64(rec, 16))
      Machine.store64(rec, 16, pair)
      Machine.store64(rec, 24, 0)
      pair = 0
      i = i + 1
    end
    result = Machine.load64(rec, 16)
    Machine.store64(h, 40, Machine.load64(rec, 0))
    result
  end

  #: (i32, ptr) -> i32
  def main(argc, argv)
    h = heap()
    if argc > 1
      Machine.store64(h, 24, 1)
    end
    heap_init()
    rec = Machine.slot(24)
    Machine.store64(rec, 0, 0)
    Machine.store64(rec, 8, 1)
    Machine.store64(rec, 16, 0)
    Machine.store64(h, 40, rec)
    round = 0
    while round < 50
      Machine.store64(rec, 16, build(37 + (round % 5)))
      round = round + 1
    end
    # only the last list is reachable now
    collect()
    put(Machine.bytes("allocs "), 7)
    put_word(Machine.load64(h, 8))
    put(Machine.bytes("live "), 5)
    put_word(live())
    Machine.store64(rec, 16, 0)
    collect()
    put(Machine.bytes("after "), 6)
    put_word(live())
    Libc.exit(0)
    0
  end
end
