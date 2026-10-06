ENV["ZR_TEST_PROBE_X"] = "1"
p ENV.select { |k, v| k == "ZR_TEST_PROBE_X" }
p ENV.reject { |k, v| k != "ZR_TEST_PROBE_X" }
p ENV.filter { |k, v| k == "ZR_TEST_PROBE_X" }
