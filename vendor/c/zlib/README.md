# zlib 1.3.1, the deflate and inflate sources

The compression library, from https://zlib.net (the zlib license, see
LICENSE). This is the version ruby 4.0.6 links into its `zlib`
extension, so a deflate here writes the bytes ruby's writes. Only the
sources the runtime needs are here: deflate, inflate, the checksums and
their headers; the gzip file functions (`gz*.c`) are not, since the
extension writes the gzip container itself. `gzguts.h` stays because
`zutil.c` reads it. `ze0 deps build` compiles them into
vendor/build/libz.a, and `rt/kernel/zlib.rb` calls them.

Nothing here is changed.
