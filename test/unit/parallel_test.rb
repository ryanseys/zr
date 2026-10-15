# frozen_string_literal: true

require "etc"
require "test_helper"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/native/build"

# A unit assembled in workers. Results come back in item order for any
# split, the first failure in item order is raised, and the kernel
# object has the same bytes from one process and from three.
class ParallelTest < Minitest::Test
  def test_map_returns_results_in_item_order_for_any_job_count
    items = (1..40).to_a
    [1, 2, 3, 7].each do |jobs|
      assert_equal items.map { |x| x * x }, Zr::Native::Parallel.map(items, jobs: jobs, weight: ->(x) { x % 5 }) { |x| x * x }
    end
  end

  def test_a_failure_raises_the_first_items_error
    error = assert_raises(ArgumentError) do
      Zr::Native::Parallel.map((1..30).to_a, jobs: 3, weight: ->(x) { x }) do |x|
        raise TypeError, "late #{x}" if x == 25
        raise ArgumentError, "first #{x}" if x == 11

        x
      end
    end
    assert_equal "first 11", error.message
  end

  def test_kernel_object_bytes_are_the_same_for_any_worker_count
    one, three = [1, 3].map do |jobs|
      unit = Zr::Machine.unit(Zr::RuntimeSources.for.kernel_files)
      image = Zr::Native::Build.unit(unit.functions, unit.data, raw: unit.raw, export: true, jobs: jobs, floor: 0)
      Zr::Native::Build.writer(Zr::Target.default).write(image)
    end
    assert_equal one.bytesize, three.bytesize
    assert_equal one, three, "the kernel object differs between one worker and three"
  end

  # A worker copies only the pages it writes: about a third of the parent
  # under ruby. The count is three quarters of the available memory over
  # that cost.
  def test_worker_count_is_limited_by_available_memory
    on_a_machine_of(16, available: 12) do
      assert_equal 6, holding(3) { Parallel.afforded(6) }
      assert_equal 4, holding(6) { Parallel.afforded(6) }
    end
    on_a_machine_of(16, available: 4) { assert_equal 3, holding(3) { Parallel.afforded(6) } }
  end

  # A worker of the compiled compiler copies about all of the parent. Six
  # such workers, ten gigabytes each, pushed a sixteen gigabyte machine
  # into swap. A run that swaps does not fail, but it takes ten times as
  # long.
  def test_a_worker_of_the_compiled_compiler_costs_the_whole_parent
    stub_method(Zr::Binary, :running?, -> { true }) do
      on_a_machine_of(16, available: 12) { assert_equal 2, holding(4) { Parallel.afforded(6) } }
    end
  end

  # Without the system's available memory, the machine less the parent.
  def test_worker_count_without_available_memory_uses_the_machine
    on_a_machine_of(16) do
      assert_equal 6, holding(3) { Parallel.afforded(6) }
      assert_equal 5, holding(6) { Parallel.afforded(6) }
    end
  end

  def test_available_bytes_is_below_the_machine
    available = Parallel.available_bytes
    skip "this system gives no available memory" unless available
    assert_operator available, :<=, Parallel.machine_bytes
  end

  def test_machine_bytes_is_8gb_when_sysconf_fails
    stub_method(Etc, :sysconf, -> { raise NotImplementedError }) do
      assert_equal 8 << 30, Parallel.machine_bytes
    end
  end

  # A fork pool needs one worker, however little memory the machine has.
  def test_worker_count_is_one_when_machine_memory_is_small
    on_a_machine_of(4) { assert_equal 1, holding(8) { Parallel.afforded(6) } }
  end

  def test_zr_jobs_overrules_the_memory_bound
    on_a_machine_of(16) do
      Zr::Config.with(ZR_JOBS: "6") { |_| assert_equal 6, holding(10) { Parallel.afforded(6) } }
    end
  end

  def test_with_timing_a_map_shows_each_tenth_of_its_weight_and_its_slowest_items
    items = (1..40).to_a
    squares = nil
    _, err = capture_io do
      Zr::Config.with(ZR_TIMING: "1") do |_|
        squares = Parallel.map(items, jobs: 3, weight: ->(x) { x }, label: ->(x) { "item #{x}" }) { |x| x * x }
      end
    end

    assert_equal items.map { |x| x * x }, squares
    # No item weighs a tenth of the total (40 of 820), so each tenth has its line.
    assert_equal 10, err.scan(/^zr: +\d+% of the weight/).size
    assert_match(/^zr: 100% of the weight \(40 of 40 items\) in \d+:\d\d, about 0:00 left$/, err)
    slowest = err.lines.grep(/^zr: +[\d.]+s  weight +\d+  item \d+$/)
    assert_equal Parallel::Progress::SLOWEST, slowest.size
  end

  def test_with_timing_a_map_adds_the_tallies_of_its_workers
    _, err = capture_io do
      Zr::Config.with(ZR_TIMING: "1") do |_|
        Parallel.map((1..6).to_a, jobs: 2, weight: ->(x) { x }) { |x| Zr::Timing.tally("nap") { sleep 0.01 } && x }
      end
    end

    napped = err[/^zr: +nap +([\d.]+)s/, 1]
    refute_nil napped, err
    assert_operator napped.to_f, :>=, 0.06
    assert_empty Zr::Timing.tallies, "the report clears the tallies"
  end

  def test_a_worker_that_ends_with_no_answer_raises
    error = assert_raises(RuntimeError) do
      Parallel.map((1..4).to_a, jobs: 2, weight: ->(x) { x }) { |x| x == 4 ? exit!(3) : x }
    end
    assert_match(/a worker stopped without an answer/, error.message)
  end

  private

  Parallel = Zr::Native::Parallel

  # With no `ZR_JOBS`, which overrides the memory bound. `available` is
  # the memory the system can give now, nil when it does not say.
  def on_a_machine_of(gigabytes, available: nil, &)
    Zr::Config.with(ZR_JOBS: nil) do |_|
      stub_method(Parallel, :available_bytes, -> { available && available << 30 }) do
        stub_method(Parallel, :machine_bytes, -> { gigabytes << 30 }, &)
      end
    end
  end

  def holding(gigabytes, &) = stub_method(Parallel, :held_bytes, -> { gigabytes << 30 }, &)
end
