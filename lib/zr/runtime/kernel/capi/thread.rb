module Zr::Kern
  # C that runs without the GVL: rb_thread_call_without_gvl and its kin.
  # zr's threads are green, so such C runs on a worker OS thread of the
  # offload pool, and the green thread that called it waits for the job's
  # pipe as for any descriptor (`Thread#offload_wait`): the other threads
  # run meanwhile. A thread that is alone calls the C itself.
  #
  # A worker touches only the pool and its jobs, which are malloc'd and
  # which the pool's mutex guards: never the heap, the task or a static.
  # It reaches the pool through its thread argument, and keeps the job
  # that it runs in a thread-local key. When the C calls
  # rb_thread_call_with_gvl, the worker posts the call to the job, and the
  # waiting green thread runs it and lets the worker go on.
  class OffloadPool < Layout
    attr_accessor :mutex #: ptr
    attr_accessor :cond #: ptr
    attr_accessor :head #: ptr
    attr_accessor :tail #: ptr
    attr_accessor :workers #: word
    attr_accessor :idle #: word
    # The thread-local key of a worker's job (pthread_key_t).
    attr_accessor :key #: word
    # The process that made the pool: a fork's child has no workers, and
    # makes a pool of its own.
    attr_accessor :pid #: word
  end

  class OffloadJob < Layout
    attr_accessor :next #: ptr
    attr_accessor :fn #: ptr
    attr_accessor :data #: ptr
    attr_accessor :result #: ptr
    attr_accessor :state #: word
    attr_accessor :read_fd #: word
    attr_accessor :write_fd #: word
    attr_accessor :ubf #: ptr
    attr_accessor :ubf_data #: ptr
    # A call that the C asks for with rb_thread_call_with_gvl.
    attr_accessor :call_fn #: ptr
    attr_accessor :call_data #: ptr
    attr_accessor :call_result #: ptr
  end

  JOB_QUEUED = 0
  JOB_RUNNING = 1
  JOB_DONE = 2
  JOB_CALLING = 3
  # The most workers; more jobs wait in the queue.
  OFFLOAD_WORKERS = 16
  # pthread_mutex_t and pthread_cond_t fit in this many bytes on each OS.
  PTHREAD_OBJECT_BYTES = 128
  # RUBY_UBF_IO and RUBY_UBF_PROCESS: no function that unblocks the C.
  UBF_NONE = 0 - 1

  # rb_thread_call_without_gvl: `fn(data)` on a worker, while the other
  # threads run. An interrupt (Thread#raise, #kill, a signal) calls
  # `ubf(ubf_data)` to stop the C, waits for it to return, then goes on.
  #: (ptr, ptr, ptr, ptr) -> ptr
  def rb_thread_call_without_gvl(fn, data, ubf, ubf_data)
    Machine.gates_enter
    zr_c_entered()
    zr_offload_call(fn, data, ubf, ubf_data)
  end

  #: (ptr, ptr, ptr, ptr) -> ptr
  def rb_thread_call_without_gvl2(fn, data, ubf, ubf_data)
    Machine.gates_enter
    zr_c_entered()
    zr_offload_call(fn, data, ubf, ubf_data)
  end

  # rb_nogvl: the same; zr takes no flag into account.
  #: (ptr, ptr, ptr, ptr, i32) -> ptr
  def rb_nogvl(fn, data, ubf, ubf_data, flags)
    Machine.gates_enter
    zr_c_entered()
    zr_offload_call(fn, data, ubf, ubf_data)
  end

  # rb_thread_call_with_gvl: `fn(data)` with the GVL, from C that runs
  # without it. On a worker, the waiting green thread runs it; on a Ruby
  # thread, the call is direct.
  #: (ptr, ptr) -> ptr
  def rb_thread_call_with_gvl(fn, data)
    Machine.gates_enter
    pool = Machine.ptr(Machine.load64(Machine.static(:offload_pool, 8), 0))
    job = pool == 0 ? Machine.ptr(0) : Libc.pthread_getspecific(OffloadPool[pool].key)
    if job == 0
      zr_c_entered()
      argv = Machine.slot(64)
      Machine.store64(argv, 0, Machine.word(data))
      return Machine.ptr(zr_c_result(Machine.value(zr_call_c(fn, argv, 1))))
    end
    Libc.pthread_mutex_lock(OffloadPool[pool].mutex)
    OffloadJob[job].call_fn = fn
    OffloadJob[job].call_data = data
    OffloadJob[job].state = JOB_CALLING
    Libc.pthread_mutex_unlock(OffloadPool[pool].mutex)
    zr_offload_signal(job)
    Libc.pthread_mutex_lock(OffloadPool[pool].mutex)
    while OffloadJob[job].state == JOB_CALLING
      Libc.pthread_cond_wait(OffloadPool[pool].cond, OffloadPool[pool].mutex)
    end
    Libc.pthread_mutex_unlock(OffloadPool[pool].mutex)
    OffloadJob[job].call_result
  end

  # ruby_native_thread_p: 1. In ruby, C without the GVL runs on its Ruby
  # thread; here it runs on a worker, which can reach Ruby too, through
  # rb_thread_call_with_gvl.
  #: () -> i32
  def ruby_native_thread_p
    Machine.gates_enter
    Machine.i32(1)
  end

  # ruby_thread_has_gvl_p: 0 on a worker of the pool, which runs C
  # without the GVL, else 1.
  #: () -> i32
  def ruby_thread_has_gvl_p
    Machine.gates_enter
    pool = Machine.ptr(Machine.load64(Machine.static(:offload_pool, 8), 0))
    pool != 0 && Libc.pthread_getspecific(OffloadPool[pool].key) != 0 ? Machine.i32(0) : Machine.i32(1)
  end

  # rb_thread_check_ints: a safe point, which runs what interrupts wait.
  #: () -> void
  def rb_thread_check_ints
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_preempt())
  end

  # rb_thread_current: Thread.current.
  #: () -> value
  def rb_thread_current
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_core_class(Machine.id(:Thread)), Machine.id(:current), 0, Machine.ptr(0)))
  end

  # rb_thread_schedule: Thread.pass.
  #: () -> void
  def rb_thread_schedule
    Machine.gates_enter
    zr_c_entered()
    zr_c_result(zr_send(zr_core_class(Machine.id(:Thread)), Machine.id(:pass), 0, Machine.ptr(0)))
  end

  # `fn(data)` without the GVL, as rb_thread_call_without_gvl runs it.
  #: (ptr, ptr, ptr, ptr) -> ptr
  def zr_offload_call(fn, data, ubf, ubf_data)
    if zr_threaded() == QFALSE
      argv = Machine.slot(64)
      Machine.store64(argv, 0, Machine.word(data))
      return Machine.ptr(zr_c_result(Machine.value(zr_call_c(fn, argv, 1))))
    end
    pool = zr_offload_pool()
    job = zr_offload_submit(pool, fn, data, ubf, ubf_data)
    args = Machine.slot(8)
    Machine.store64(args, 0, Machine.word(zr_fix(OffloadJob[job].read_fd)))
    thread = zr_send(zr_core_class(Machine.id(:Thread)), Machine.id(:current), 0, Machine.ptr(0))
    # What the C's calls into Ruby return lives on the worker's stack,
    # which the collector does not read: it stays here until the job ends.
    kept = zr_ary_new(0)
    while true
      if zr_send(thread, Machine.id(:offload_wait), 1, args) == QUNDEF
        # An interrupt: the C stops and returns first, then the interrupt
        # goes on.
        zr_capi_park()
        zr_offload_unblock(pool, job, kept)
        zr_capi_unpark()
        zr_offload_free(job)
        zr_c_unwind()
      end
      zr_offload_drain(job)
      if zr_offload_serve(pool, job, kept)
        result = OffloadJob[job].result
        zr_offload_free(job)
        return result
      end
    end
    Machine.ptr(0)
  end

  # After a wake: runs the call that the C asked for, if it did, keeps
  # its result in `kept`, and lets the worker go on. Whether the job is
  # done.
  #: (ptr, ptr, value) -> bool
  def zr_offload_serve(pool, job, kept)
    Libc.pthread_mutex_lock(OffloadPool[pool].mutex)
    state = OffloadJob[job].state
    Libc.pthread_mutex_unlock(OffloadPool[pool].mutex)
    if state == JOB_DONE
      return true
    end
    if state == JOB_CALLING
      argv = Machine.slot(64)
      Machine.store64(argv, 0, Machine.word(OffloadJob[job].call_data))
      # The call's error cannot go through the worker's C; it is dropped.
      r = zr_call_c(OffloadJob[job].call_fn, argv, 1)
      if r == QUNDEF
        Task[zr_task()].pending = Machine.value(QNIL)
        r = QNIL
      end
      zr_ary_push(kept, Machine.value(r))
      Libc.pthread_mutex_lock(OffloadPool[pool].mutex)
      OffloadJob[job].call_result = Machine.ptr(r)
      OffloadJob[job].state = JOB_RUNNING
      Libc.pthread_cond_broadcast(OffloadPool[pool].cond)
      Libc.pthread_mutex_unlock(OffloadPool[pool].mutex)
    end
    false
  end

  # An interrupt of the wait: calls the job's unblocking function, then
  # waits in the system call for the C to return, serving the calls that
  # it asks for on the way.
  #: (ptr, ptr, value) -> void
  def zr_offload_unblock(pool, job, kept)
    if OffloadJob[job].ubf != Machine.ptr(UBF_NONE) && OffloadJob[job].ubf != 0
      argv = Machine.slot(64)
      Machine.store64(argv, 0, Machine.word(OffloadJob[job].ubf_data))
      if zr_call_c(OffloadJob[job].ubf, argv, 1) == QUNDEF
        Task[zr_task()].pending = Machine.value(QNIL)
      end
    end
    while true
      zr_offload_drain(job)
      if zr_offload_serve(pool, job, kept)
        return
      end
    end
  end

  # The pool of this process, made the first time.
  #: () -> ptr
  def zr_offload_pool
    at = Machine.static(:offload_pool, 8)
    pool = Machine.ptr(Machine.load64(at, 0))
    pid = Machine.sword(Libc.getpid())
    if pool != 0 && OffloadPool[pool].pid == pid
      return pool
    end
    pool = zr_xmalloc(OffloadPool.size)
    Libc.memset(pool, Machine.i32(0), OffloadPool.size)
    OffloadPool[pool].mutex = zr_xmalloc(PTHREAD_OBJECT_BYTES)
    OffloadPool[pool].cond = zr_xmalloc(PTHREAD_OBJECT_BYTES)
    Libc.pthread_mutex_init(OffloadPool[pool].mutex, Machine.ptr(0))
    Libc.pthread_cond_init(OffloadPool[pool].cond, Machine.ptr(0))
    key = Machine.slot(8)
    Machine.store64(key, 0, 0)
    Libc.pthread_key_create(key, Machine.ptr(0))
    OffloadPool[pool].key = Machine.load64(key, 0)
    OffloadPool[pool].pid = pid
    Machine.store64(at, 0, Machine.word(pool))
    pool
  end

  # Queues a job for `fn(data)`, with its pipe, and starts a worker when
  # none is idle.
  #: (ptr, ptr, ptr, ptr, ptr) -> ptr
  def zr_offload_submit(pool, fn, data, ubf, ubf_data)
    fds = Machine.slot(8)
    if Libc.pipe(fds) != Machine.i32(0)
      args = Machine.slot(16)
      Machine.store64(args, 0, Machine.word(zr_str_new(Machine.bytes("pipe"), 4)))
      Machine.store64(args, 8, Machine.word(zr_fix(zr_errno())))
      zr_c_result(zr_raise(zr_c_result(zr_send(zr_core_class(Machine.id(:SystemCallError)), Machine.id(:new), 2, args))))
    end
    job = zr_xmalloc(OffloadJob.size)
    Libc.memset(job, Machine.i32(0), OffloadJob.size)
    OffloadJob[job].fn = fn
    OffloadJob[job].data = data
    OffloadJob[job].ubf = ubf
    OffloadJob[job].ubf_data = ubf_data
    OffloadJob[job].read_fd = Machine.sword(Machine.load32(fds, 0))
    OffloadJob[job].write_fd = Machine.sword(Machine.load32(fds, 4))
    Libc.pthread_mutex_lock(OffloadPool[pool].mutex)
    if OffloadPool[pool].tail == 0
      OffloadPool[pool].head = job
    else
      OffloadJob[OffloadPool[pool].tail].next = job
    end
    OffloadPool[pool].tail = job
    spawn = OffloadPool[pool].idle == 0 && OffloadPool[pool].workers < OFFLOAD_WORKERS
    if spawn
      OffloadPool[pool].workers = OffloadPool[pool].workers + 1
    end
    Libc.pthread_cond_broadcast(OffloadPool[pool].cond)
    Libc.pthread_mutex_unlock(OffloadPool[pool].mutex)
    if spawn
      tid = Machine.slot(8)
      if Libc.pthread_create(tid, Machine.ptr(0), Machine.addr(:zr_offload_worker), pool) == Machine.i32(0)
        Libc.pthread_detach(Machine.ptr(Machine.load64(tid, 0)))
      end
    end
    job
  end

  # A worker's loop: takes each job, runs its C, marks it done, and wakes
  # its waiter. It never returns.
  #: (ptr) -> ptr
  def zr_offload_worker(pool)
    while true
      Libc.pthread_mutex_lock(OffloadPool[pool].mutex)
      OffloadPool[pool].idle = OffloadPool[pool].idle + 1
      while OffloadPool[pool].head == 0
        Libc.pthread_cond_wait(OffloadPool[pool].cond, OffloadPool[pool].mutex)
      end
      OffloadPool[pool].idle = OffloadPool[pool].idle - 1
      job = OffloadPool[pool].head
      OffloadPool[pool].head = OffloadJob[job].next
      if OffloadPool[pool].head == 0
        OffloadPool[pool].tail = Machine.ptr(0)
      end
      OffloadJob[job].state = JOB_RUNNING
      Libc.pthread_mutex_unlock(OffloadPool[pool].mutex)
      Libc.pthread_setspecific(OffloadPool[pool].key, job)
      result = Machine.ptr(zr_gc_call(OffloadJob[job].fn, OffloadJob[job].data, Machine.ptr(0)))
      Libc.pthread_setspecific(OffloadPool[pool].key, Machine.ptr(0))
      Libc.pthread_mutex_lock(OffloadPool[pool].mutex)
      OffloadJob[job].result = result
      OffloadJob[job].state = JOB_DONE
      Libc.pthread_mutex_unlock(OffloadPool[pool].mutex)
      zr_offload_signal(job)
    end
    Machine.ptr(0)
  end

  # A job's waiter wakes when its pipe has a byte: one for each change
  # that it must look at.
  #: (ptr) -> void
  def zr_offload_signal(job)
    byte = Machine.slot(8)
    Machine.store8(byte, 0, Machine.i8(1))
    Libc.write(Machine.i32(OffloadJob[job].write_fd), byte, 1)
  end

  # Reads one wake byte; the read waits until there is one.
  #: (ptr) -> void
  def zr_offload_drain(job)
    byte = Machine.slot(8)
    Libc.read(Machine.i32(OffloadJob[job].read_fd), byte, 1)
  end

  #: (ptr) -> void
  def zr_offload_free(job)
    Libc.close(Machine.i32(OffloadJob[job].read_fd))
    Libc.close(Machine.i32(OffloadJob[job].write_fd))
    zr_xfree(job)
  end

  # rb_ext_ractor_safe: the extension says that its functions may run in
  # any Ractor. zr runs C in the main Ractor only, so this changes nothing.
  #: (i32) -> void
  def rb_ext_ractor_safe(flag)
    Machine.gates_enter
    zr_c_entered()
  end

  # rb_ractor_local_storage_value_newkey: a key of Ractor-local storage.
  # It is a word that holds a Symbol only C knows (`__c_key_<n>`), under
  # which each Ractor keeps its value, as `Ractor[key]` does.
  #: () -> ptr
  def rb_ractor_local_storage_value_newkey
    Machine.gates_enter
    zr_c_entered()
    count = Machine.static(:ractor_c_keys, 8)
    n = Machine.load64(count, 0) + 1
    Machine.store64(count, 0, n)
    b = Machine.slot(Buf.size)
    zr_buf_init(b)
    zr_buf_push(b, Machine.bytes("__c_key_"), 8)
    zr_buf_long(b, n)
    id = zr_intern(Buf[b].ptr, Buf[b].len)
    zr_buf_free(b)
    key = zr_xmalloc(8)
    Machine.store64(key, 0, Machine.word(zr_sym(id)))
    key
  end

  # rb_ractor_local_storage_value_lookup: whether the current Ractor
  # holds a value for `key`; if so, it goes to `*val`.
  #: (ptr, ptr) -> i32
  def rb_ractor_local_storage_value_lookup(key, val)
    Machine.gates_enter
    zr_c_entered()
    found = zr_capi_ractor_local(key)
    if zr_ary_at(found, 0) != QTRUE
      return Machine.i32(0)
    end
    Machine.store64(val, 0, Machine.word(zr_ary_at(found, 1)))
    Machine.i32(1)
  end

  # rb_ractor_local_storage_value: the current Ractor's value for `key`,
  # or nil.
  #: (ptr) -> value
  def rb_ractor_local_storage_value(key)
    Machine.gates_enter
    zr_c_entered()
    zr_ary_at(zr_capi_ractor_local(key), 1)
  end

  #: (ptr) -> value
  def zr_capi_ractor_local(key)
    zr_capi_call1(zr_core_class(Machine.id(:Ractor)), Machine.id(:c_local), Machine.value(Machine.load64(key, 0)))
  end

  # rb_ractor_local_storage_value_set: the current Ractor's value for
  # `key` is `v`.
  #: (ptr, value) -> void
  def rb_ractor_local_storage_value_set(key, v)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.load64(key, 0))
    Machine.store64(args, 8, Machine.word(v))
    zr_c_result(zr_send(zr_core_class(Machine.id(:Ractor)), Machine.id(:[]=), 2, args))
  end

  # rb_nativethread_lock_*: rb_nativethread_lock_t is a pthread mutex.
  #: (ptr) -> void
  def rb_nativethread_lock_initialize(lock)
    Machine.gates_enter
    zr_c_entered()
    Libc.pthread_mutex_init(lock, Machine.ptr(0))
  end

  #: (ptr) -> void
  def rb_nativethread_lock_destroy(lock)
    Machine.gates_enter
    zr_c_entered()
    Libc.pthread_mutex_destroy(lock)
  end

  #: (ptr) -> void
  def rb_nativethread_lock_lock(lock)
    Machine.gates_enter
    zr_c_entered()
    Libc.pthread_mutex_lock(lock)
  end

  #: (ptr) -> void
  def rb_nativethread_lock_unlock(lock)
    Machine.gates_enter
    zr_c_entered()
    Libc.pthread_mutex_unlock(lock)
  end

  # rb_thread_io_blocking_region: `fn(data)` without the GVL, as a read or
  # a write of the stream `fptr` that blocks; an interrupt waits for it to
  # return. (Before 4.0 it took the descriptor last, as kgio declares it.)
  #: (ptr, ptr, ptr) -> value
  def rb_thread_io_blocking_region(fptr, fn, data)
    Machine.gates_enter
    zr_c_entered()
    Machine.value(zr_offload_call(fn, data, Machine.ptr(UBF_NONE), Machine.ptr(0)))
  end

  # --- Thread objects ------------------------------------------------------

  # rb_thread_create: a Thread that runs `fn(arg)` and ends with its
  # result.
  #: (ptr, word) -> value
  def rb_thread_create(fn, arg)
    Machine.gates_enter
    zr_c_entered()
    body = zr_capi_native_proc(Machine.addr(:zr_capi_thread_body), fn, arg)
    zr_c_result(zr_send_blk(zr_capi_thread_class(), Machine.id(:new), 0, Machine.ptr(0), body))
  end

  # The block of a Thread that C made: `fn(arg)`.
  #: (value, word, ptr, value) -> value
  def zr_capi_thread_body(p, argc, argv, blk)
    args = Machine.slot(64)
    Machine.store64(args, 0, zr_capi_proc_data(p))
    Machine.value(zr_call_c(zr_capi_proc_fn(p), args, 1))
  end

  # rb_thread_alone: whether no other thread runs, as 1 or 0.
  #: () -> i32
  def rb_thread_alone
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(zr_capi_thread_class(), Machine.id(:alone?)) == QTRUE ? Machine.i32(1) : Machine.i32(0)
  end

  # rb_thread_main: Thread.main.
  #: () -> value
  def rb_thread_main
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(zr_capi_thread_class(), Machine.id(:main))
  end

  # rb_thread_stop: Thread.stop, which sleeps until another thread runs
  # this one.
  #: () -> value
  def rb_thread_stop
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(zr_capi_thread_class(), Machine.id(:stop))
  end

  # rb_thread_run, rb_thread_wakeup, rb_thread_wakeup_alive and
  # rb_thread_kill: Thread#run, #wakeup, #wakeup (which raises for a
  # dead thread, as both do) and #kill.
  #: (value) -> value
  def rb_thread_run(thread)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(thread, Machine.id(:run))
  end

  #: (value) -> value
  def rb_thread_wakeup(thread)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(thread, Machine.id(:wakeup))
  end

  #: (value) -> value
  def rb_thread_wakeup_alive(thread)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(thread, Machine.id(:wakeup))
  end

  #: (value) -> value
  def rb_thread_kill(thread)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(thread, Machine.id(:kill))
  end

  # rb_thread_local_aref and rb_thread_local_aset: the thread's fiber-local
  # `thread[id]`.
  #: (value, word) -> value
  def rb_thread_local_aref(thread, id)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(thread, Machine.id(:[]), zr_sym(zr_capi_mid(id)))
  end

  #: (value, word, value) -> value
  def rb_thread_local_aset(thread, id, v)
    Machine.gates_enter
    zr_c_entered()
    args = Machine.slot(16)
    Machine.store64(args, 0, Machine.word(zr_sym(zr_capi_mid(id))))
    Machine.store64(args, 8, Machine.word(v))
    zr_c_result(zr_send(thread, Machine.id(:[]=), 2, args))
  end

  # rb_thread_sleep_forever, rb_thread_sleep and rb_thread_wait_for: sleep
  # until woken, for `sec` seconds, or for the timeval that C passes by
  # value (its two words).
  #: () -> void
  def rb_thread_sleep_forever
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(zr_global(G_KERNEL), Machine.id(:sleep))
  end

  #: (i32) -> void
  def rb_thread_sleep(sec)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(zr_global(G_KERNEL), Machine.id(:sleep), zr_fix(Machine.sword(sec)))
  end

  #: (word, word) -> void
  def rb_thread_wait_for(sec, usec)
    Machine.gates_enter
    zr_c_entered()
    total = zr_int_from_word((sec * 1000000) + Machine.sword(Machine.i32(usec)))
    seconds = zr_capi_call1(total, Machine.id(:quo), zr_fix(1000000))
    zr_capi_call1(zr_global(G_KERNEL), Machine.id(:sleep), seconds)
  end

  #: () -> value
  def zr_capi_thread_class
    zr_core_class(Machine.id(:Thread))
  end

  #: (value, word) -> value
  def zr_capi_thread_send(recv, mid)
    zr_c_result(zr_send(recv, mid, 0, Machine.ptr(0)))
  end

  # --- Mutexes -------------------------------------------------------------

  # rb_mutex_new: Mutex.new.
  #: () -> value
  def rb_mutex_new
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(zr_core_class(Machine.id(:Mutex)), Machine.id(:new))
  end

  # rb_mutex_lock, rb_mutex_unlock, rb_mutex_trylock and
  # rb_mutex_locked_p: Mutex#lock, #unlock, #try_lock and #locked?.
  #: (value) -> value
  def rb_mutex_lock(mutex)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(mutex, Machine.id(:lock))
  end

  #: (value) -> value
  def rb_mutex_unlock(mutex)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(mutex, Machine.id(:unlock))
  end

  #: (value) -> value
  def rb_mutex_trylock(mutex)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(mutex, Machine.id(:try_lock))
  end

  #: (value) -> value
  def rb_mutex_locked_p(mutex)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(mutex, Machine.id(:locked?))
  end

  # rb_mutex_sleep: Mutex#sleep for `timeout` seconds (nil: until woken).
  #: (value, value) -> value
  def rb_mutex_sleep(mutex, timeout)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_call1(mutex, Machine.id(:sleep), timeout)
  end

  # rb_mutex_synchronize: `fn(arg)` with the mutex locked, which it
  # unlocks however the call ends.
  #: (value, ptr, word) -> value
  def rb_mutex_synchronize(mutex, fn, arg)
    Machine.gates_enter
    zr_c_entered()
    zr_capi_thread_send(mutex, Machine.id(:lock))
    args = Machine.slot(64)
    Machine.store64(args, 0, arg)
    r = Machine.value(zr_call_c(fn, args, 1))
    if r == QUNDEF
      zr_capi_park()
      left = Task[zr_task()].parked
      Task[zr_task()].parked = Machine.value(QNIL)
      zr_capi_thread_send(mutex, Machine.id(:unlock))
      Task[zr_task()].parked = left
      zr_capi_unpark()
      zr_c_unwind()
    end
    zr_capi_thread_send(mutex, Machine.id(:unlock))
    r
  end

  # rb_internal_thread_add_event_hook: `callback` gets each of `events`
  # that a thread has (kernel/thread_hooks.rb). Returns the hook, which
  # rb_internal_thread_remove_event_hook takes.
  #: (ptr, word, word) -> ptr
  def rb_internal_thread_add_event_hook(callback, events, data)
    Machine.gates_enter
    zr_c_entered()
    hook = zr_xmalloc(ThreadHook.size)
    ThreadHook[hook].callback = callback
    ThreadHook[hook].events = events & 0xffffffff
    ThreadHook[hook].data = data
    ThreadHook[hook].next = Machine.ptr(Machine.load64(zr_thread_hooks(), 0))
    Machine.store64(zr_thread_hooks(), 0, Machine.word(hook))
    hook
  end

  # rb_internal_thread_remove_event_hook: unlinks and frees `hook`;
  # whether it was there.
  #: (ptr) -> i32
  def rb_internal_thread_remove_event_hook(hook)
    Machine.gates_enter
    zr_c_entered()
    link = zr_thread_hooks()
    while Machine.load64(link, 0) != 0
      at = Machine.ptr(Machine.load64(link, 0))
      if at == hook
        Machine.store64(link, 0, Machine.word(ThreadHook[hook].next))
        zr_xfree(hook)
        return Machine.i32(1)
      end
      link = at
    end
    Machine.i32(0)
  end

  # The keys that rb_internal_thread_specific_key_create can give.
  THREAD_SPECIFIC_KEYS = 8

  # rb_internal_thread_specific_key_create: a key for a word of C's in
  # each thread; at most eight, as in ruby.
  #: () -> i32
  def rb_internal_thread_specific_key_create
    Machine.gates_enter
    zr_c_entered()
    count = Machine.static(:thread_specific_keys, 8)
    key = Machine.load64(count, 0)
    if key >= THREAD_SPECIFIC_KEYS
      zr_c_result(zr_raise_msg(zr_core_class(Machine.id(:ThreadError)), Machine.bytes("rb_internal_thread_specific_key_create() is called more than 8 times"), 68))
    end
    Machine.store64(count, 0, key + 1)
    Machine.i32(key)
  end

  # rb_internal_thread_specific_get and _set: the thread's word for
  # `key`, NULL until set. The words are in a hidden binary String of the
  # thread's; a get makes no object, as a hook that may not allocate
  # reads it.
  #: (value, i32) -> word
  def rb_internal_thread_specific_get(thread, key)
    Machine.gates_enter
    zr_c_entered()
    words = zr_hidden_get(thread, zr_sym(Machine.id(:specific)))
    words == QNIL ? 0 : Machine.load64(RString[words].ptr + (Machine.sword(key) * 8), 0)
  end

  #: (value, i32, word) -> void
  def rb_internal_thread_specific_set(thread, key, data)
    Machine.gates_enter
    zr_c_entered()
    words = zr_hidden_get(thread, zr_sym(Machine.id(:specific)))
    if words == QNIL
      words = zr_capi_str(Machine.ptr(0), THREAD_SPECIFIC_KEYS * 8, ENC_BINARY)
      Libc.memset(RString[words].ptr, Machine.i32(0), THREAD_SPECIFIC_KEYS * 8)
      zr_hidden_set(thread, zr_sym(Machine.id(:specific)), words)
    end
    Machine.store64(RString[words].ptr + (Machine.sword(key) * 8), 0, data)
  end
end
