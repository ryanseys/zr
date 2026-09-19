# frozen_string_literal: true

require "etc"
require "test_helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/native/build"

# A unit assembled in workers: the answers in item order whatever the
# bins, the first failure in item order, and the bytes of the kernel's
# object the same for one process and for three.
class ParallelTest < Minitest::Test
  def test_answers_come_back_in_item_order_for_any_jobs
    items = (1..40).to_a
    [1, 2, 3, 7].each do |jobs|
      assert_equal items.map { |x| x * x }, Ze0::Native::Parallel.map(items, jobs: jobs, weight: ->(x) { x % 5 }) { |x| x * x }
    end
  end

  def test_a_failure_raises_the_first_items_error
    error = assert_raises(ArgumentError) do
      Ze0::Native::Parallel.map((1..30).to_a, jobs: 3, weight: ->(x) { x }) do |x|
        raise TypeError, "late #{x}" if x == 25
        raise ArgumentError, "first #{x}" if x == 11

        x
      end
    end
    assert_equal "first 11", error.message
  end

  def test_the_kernel_object_is_the_same_bytes_from_any_number_of_workers
    one, three = [1, 3].map do |jobs|
      unit = Ze0::Machine.unit(Ze0::Zr.kernel_files)
      image = Ze0::Native::Build.unit(unit.functions, unit.data, raw: unit.raw, export: true, jobs: jobs, floor: 0)
      Ze0::Native::Build.writer(Ze0::Target.default).write(image)
    end
    assert_equal one.bytesize, three.bytesize
    assert one == three, "the kernel object differs between one worker and three"
  end

  # A worker costs about what the parent holds, since it inherits that
  # heap and grows one of its own beside it. Six workers of the compiled
  # compiler, ten gigabytes each, drove a sixteen gigabyte machine into
  # swap, and a run that swaps does not fail -- it takes ten times as
  # long.
  def test_the_worker_count_is_bounded_by_what_the_machine_holds
    on_a_machine_of(16) do
      assert_equal 6, holding(1) { Parallel.afforded(6) }
      assert_equal 3, holding(4) { Parallel.afforded(6) }
      assert_equal 1, holding(10) { Parallel.afforded(6) }
    end
  end

  def test_a_machine_that_will_not_say_its_memory_is_treated_as_a_small_one
    standing_in(Etc, :sysconf, -> { raise NotImplementedError }) do
      assert_equal 8 << 30, Parallel.machine_bytes
    end
  end

  # However little the machine has, one worker is what a fork pool is.
  def test_a_machine_smaller_than_the_compiler_still_runs_one_worker
    on_a_machine_of(4) { assert_equal 1, holding(8) { Parallel.afforded(6) } }
  end

  def test_ze0_jobs_overrules_the_memory_bound
    with_env("ZE0_JOBS" => "6") do
      on_a_machine_of(16) { assert_equal 6, holding(10) { Parallel.afforded(6) } }
    end
  end

  private

  Parallel = Ze0::Native::Parallel

  def on_a_machine_of(gigabytes, &block) = standing_in(Parallel, :machine_bytes, -> { gigabytes << 30 }, &block)

  def holding(gigabytes, &block) = standing_in(Parallel, :held_bytes, -> { gigabytes << 30 }, &block)

  # minitest 6 leaves `minitest/mock` out, and standing in for one
  # method is the whole of what it was wanted for.
  def standing_in(owner, name, answer)
    was = owner.method(name)
    owner.define_singleton_method(name) { |*args| answer.call(*args) }
    yield
  ensure
    owner.define_singleton_method(name, was)
  end

  def with_env(pairs)
    was = pairs.transform_values { nil }.merge(ENV.slice(*pairs.keys))
    ENV.update(pairs)
    yield
  ensure
    was.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end
end
