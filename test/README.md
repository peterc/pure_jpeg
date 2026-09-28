# Adding and running tests

**Add normal Ruby tests to `minitest/test_*.rb`.** This is the full Minitest
suite, run by `rake` and `rake test`. Follow the existing files: require
`test_helper`, subclass `Minitest::Test`, and include `TestHelper` if you need
the fixture or pixel helpers.

Run commands from the repository root:

```sh
bundle exec rake test
bundle exec rake test TEST=test/minitest/test_raw_source.rb
```

The layout is unusual because this library is both a Ruby gem and a Spin
package. Spin treats **every top-level `test/*.rb` file** as a standalone
program to compile and run, regardless of its filename. Keeping Minitest
tests and helpers in subdirectories prevents Spin from compiling Minitest
and its test discovery machinery.

| Location | Purpose |
| --- | --- |
| `minitest/test_*.rb` | Normal unit and integration tests; add most tests here. |
| `minitest/test_helper.rb` | Loads Minitest, optional SimpleCov coverage, and shared helpers. |
| `support/` | Shared helpers and the small assertion adapter for the experimental Spinel runner. |
| `fixtures/` | Test images shared by the suites. |
| Top-level `*.rb` | Standalone Spin package checks, run with `spin test`. |

The top-level checks supplement the full Minitest suite. They load
`require "pure_jpeg"`, raise on failed assertions, and print deterministic
output that Spin compares with CRuby. They currently cover round trips,
metadata, and invalid input. Add a top-level Ruby file only when intentionally
adding a standalone Spin check; put reusable helpers in `support/`.

```sh
spin test
spin test round_trip.rb
```

`rake test:spinel` is a separate, experimental runner that compiles selected
existing Minitest cases using a small assertion adapter. It does not run the
top-level package checks or the full Minitest suite. See [SPINEL.md](SPINEL.md)
for its usage, limitations, and details of the Spin checks.
