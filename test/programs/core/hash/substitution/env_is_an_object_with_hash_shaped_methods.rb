# `ENV` is an Object with Hash-shaped methods, NOT a Hash (`ENV.class` is
# `Object` -- oracle-verified), and it reads the LIVE environment.

p ENV.class
ENV["ZR_TEST_E2E"] = "set"
p ENV["ZR_TEST_E2E"]
p ENV.key?("ZR_TEST_E2E")
p ENV.fetch("ZR_TEST_E2E")
p ENV.fetch("ZR_TEST_E2E_ABSENT", "default")
p ENV.fetch("ZR_TEST_E2E_ABSENT") { |k| "computed:#{k}" }
p ENV["ZR_TEST_E2E_ABSENT"]
p ENV.delete("ZR_TEST_E2E")
p ENV.key?("ZR_TEST_E2E")
p ENV.delete("ZR_TEST_E2E")
p ENV.to_h.class
p ENV.keys.class
ENV["ZR_TEST_E2E2"] = "x"
ENV["ZR_TEST_E2E2"] = nil
p ENV["ZR_TEST_E2E2"]
