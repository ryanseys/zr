# frozen_string_literal: true

module Zr
  module Dev
    module Fuzz
      # What the fuzzer does with each failure. A known difference is only
      # counted. Else the failure has a first bucket from its verdict
      # alone (the kind, and the first line that differs). The first
      # `per_bucket` failures of a first bucket are reduced, and the
      # reduced case gets its own bucket and is written. The ones after
      # are only counted, in the bucket that the reduced case got.
      #
      # `call` answers :known, :new (a bucket that the store did not
      # have), :old or :counted.
      class Triage
        PER_BUCKET = 2

        def initialize(store:, reducer: nil, layer: nil, per_bucket: PER_BUCKET, meta: {})
          @store = store
          @reducer = reducer
          @layer = layer
          @per_bucket = per_bucket
          @meta = meta
          @lock = Mutex.new
          @seen = Hash.new(0)
          @ids = 0
        end

        def call(candidate, result)
          verdict = result.verdict
          return :ignored if candidate.origin == "junk" && !Triage.junk_fault?(result)

          if (why = Known.reason(verdict))
            @store.count(verdict.bucket, verdict, known: why)
            return :known
          end

          first = verdict.bucket
          seen = @lock.synchronize { @seen[first] += 1 }
          known = @store.bucket_of(first)
          if known && (seen > @per_bucket || @store.buckets.dig(known, "cases").to_a.size >= @per_bucket)
            @store.count(known, verdict)
            return :counted
          end

          source, final, shape = reduce(candidate, result)
          bucket = final.verdict.bucket(shape)
          fresh = @store.count(bucket, final.verdict, first: first)
          id = @lock.synchronize { "#{@store.run}-#{@ids += 1}" }
          meta = @meta.merge(origin: candidate.origin, found: candidate.meta, shape: shape)
          meta[:layer] = @layer.call(source, final) if @layer
          @store.add_case(bucket, id, final, source: source, original: candidate.source, meta: meta)
          fresh ? :new : :old
        end

        # A difference in a run of junk counts when the build failed in a way
        # that it must not (Classify::BUILD_FAULTS), or when ruby rejected the
        # junk and zr did not print ruby's report. A refusal, or junk that
        # happens to run, is no fault.
        def self.junk_fault?(result)
          return true if Classify::BUILD_FAULTS.include?(result.verdict.kind)
          return false if result.verdict.kind == "refused"

          Classify.text(result.ruby&.stderr).include?("(SyntaxError)") || Classify.text(result.ruby&.stderr).include?("syntax error")
        end

        private

        # The reduced program, its result and its shape, or the program as
        # it is when there is no reducer. `reducer` makes a new Reducer
        # for each case, as each one keeps the state of its reduction.
        def reduce(candidate, result)
          return [candidate.source, result, nil] unless @reducer

          @reducer.call.reduce(candidate.source, result)
        end
      end
    end
  end
end
