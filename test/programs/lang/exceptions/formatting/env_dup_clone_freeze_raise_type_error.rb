# ENV overrides Kernel#dup/#clone/#freeze to raise (copy it via ENV.to_h).
# These must route through dispatch, not the universal value fast paths,
# which would silently shallow-copy/freeze the singleton instead.

ENV['ZZ_E2E'] = '1'
p (ENV.dup rescue $!.message)
p (ENV.clone rescue $!.message)
p (ENV.freeze rescue $!.message)
p ENV['ZZ_E2E']
p ENV.store('ZZ_E2E2', '3')
p ENV.delete('ZZ_E2E2')
p ENV.to_s
