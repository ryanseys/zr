# ENV["X"] gives a String, or nil when the variable is not set.
# `==` against a String works in both orders, also for nil.

# Use a variable that's vanishingly unlikely to be set in any environment.
UNSET = "SPINEL_TEST_VAR_THAT_DOES_NOT_EXIST_129"

# 1. nil? on unset → true.
puts ENV[UNSET].nil?                      # true

# 2. local capture + nil? roundtrip on unset → true.
s = ENV[UNSET]
puts s.nil?                                # true

# 3. inline puts on unset → blank line.
puts ENV[UNSET]                            # (blank)

# 4. equality on unset → false.
puts ENV[UNSET] == "1"                     # false

# 5. Reverse-order equality on unset → false.
puts "1" == ENV[UNSET]                     # false

# 6. nil? on a likely-set var (PATH is universal on POSIX). The test
#    harness needs PATH, so PATH is set when this test runs.
puts ENV["PATH"].nil?                      # false
