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
      unit = Zr::Machine.unit(Zr.kernel_files)
      image = Zr::Native::Build.unit(unit.functions, unit.data, raw: unit.raw, export: true, jobs: jobs, floor: 0)
      Zr::Native::Build.writer(Zr::Target.default).write(image)
    end
    assert_equal one.bytesize, three.bytesize
    assert one == three, "the kernel object differs between one worker and three"
  end

  # A worker uses about as much memory as the parent, because it inherits
  # that heap and grows its own heap too. Six workers of the compiled
  # compiler, ten gigabytes each, pushed a sixteen gigabyte machine into
  # swap. A run that swaps does not fail, but it takes ten times as long.
  def test_worker_count_is_limited_by_machine_memory
    on_a_machine_of(16) do
      assert_equal 6, holding(1) { Parallel.afforded(6) }
      assert_equal 3, holding(4) { Parallel.afforded(6) }
      assert_equal 1, holding(10) { Parallel.afforded(6) }
    end
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
    with_env("ZR_JOBS" => "6") do
      on_a_machine_of(16) { assert_equal 6, holding(10) { Parallel.afforded(6) } }
    end
  end

  private

  Parallel = Zr::Native::Parallel

  def on_a_machine_of(gigabytes, &block) = stub_method(Parallel, :machine_bytes, -> { gigabytes << 30 }, &block)

  def holding(gigabytes, &block) = stub_method(Parallel, :held_bytes, -> { gigabytes << 30 }, &block)
end
