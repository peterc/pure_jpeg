# Spinel tests

## Package checks

From the repository root, with Spinel and Spin installed:

```sh
spin test
spin test round_trip.rb
```

Spin compiles each top-level `test/*.rb` as a standalone program. These tests
load the package through `require "pure_jpeg"` and use explicit assertions
that raise on failure. No snapshots are committed: Spin compares each
program's output with a fresh CRuby run.

- `round_trip.rb`: color and grayscale encoding/decoding with odd dimensions,
  marker/dimension/pixel checks, and full encoded-byte and decoded-pixel parity.
- `metadata.rb`: baseline/grayscale metadata, header-only input, and metadata
  from the progressive JPEG fixture.
- `invalid_input.rb`: invalid JPEG data, a missing frame, and invalid quality.

The full Minitest suite lives in `test/minitest/` so Spin does not try to
compile Minitest or its helper files. `rake` and `rake test` still run that
suite with SimpleCov. Individual files can be selected with, for example,
`bundle exec rake test TEST=test/minitest/test_raw_source.rb`.
Shared fixtures remain in `test/fixtures/`.

Validated on macOS ARM64 with Spinel `b3cf642`: all three package checks
pass. The relocated Minitest suite passes all 103 tests and 6,302,248
assertions with Ruby 4.0.2, retaining 98.1% line coverage.

## Existing test runner proof of concept

Run the existing RawSource tests under both Ruby and Spinel:

```sh
SPINEL=/path/to/spinel ruby script/test_spinel.rb
# or
SPINEL=/path/to/spinel rake test:spinel
```

Use Ruby 3.0 or newer for the host runner (on a Mise-managed machine,
`mise exec ruby -- ruby script/test_spinel.rb`). `SPINEL` defaults to `spinel`
on PATH. It is an executable path, not a shell command with flags.

Normal `rake test` still uses Minitest and SimpleCov. No library code or test
methods are changed. `support/shared_helper.rb` holds helpers used by both runners.

The host Ruby process discovers test methods. For each method it writes a
copy of its test file under the ignored `tmp/spinel-tests/` directory,
replacing only the `test_helper` require with the assertion adapter and shared
helpers, then appends explicit construction/setup/test/teardown calls.
Each case gets a fresh instance and executable. The generated program runs
under Ruby and Spinel; both must exit successfully and their captured output must match.
Compile errors, assertion failures, missing tools and timeouts fail the run.
Generated Ruby, executables and per-case logs are retained for debugging.

Default coverage is the eight tests in `test/minitest/test_raw_source.rb`. You can
supply other files, but this is intentionally a first proof of concept:

```sh
SPINEL=/path/to/spinel ruby script/test_spinel.rb test/minitest/test_raw_source.rb
```

The runner also accepts the original `test/test_raw_source.rb` argument for
compatibility, resolving it to the relocated file.

The adapter currently implements only `assert`, `assert_equal`, and
`assert_respond_to`, plus setup/teardown hooks. It does not implement the full
Minitest lifecycle, assertion counts, plugins, or skips. Unsupported assertions
must fail rather than silently pass. Tests relying on their own `__dir__` or
additional relative requires need adaptation before copying them this way;
the shared fixture helper resolves fixtures from `test/fixtures/`.

Validated with Spinel `2026.09.12+1839` (`7f08abd9`) on macOS ARM64. This runner
checks existing assertions; it does not by itself prove byte-for-byte parity
for values that a test never prints or compares.

## First run

On the compiler revision above: 7 pass, 1 fails. The failure is
`TestRawSource#test_pixel_responds_to_rgb`: Spinel raises
`undefined method 'respond_to?' for an instance of PureJPEG::Source::Pixel`
inside the assertion adapter. It remains a failure (exit status 1), not a skip
or weakened assertion. The encode/decode test passes. The normal Ruby suite
passes all 103 tests and 6,302,250 assertions.

The adapter's false/unequal assertion paths were also checked with
`spinel diff`; both raise the expected assertion exception, matching Ruby.

After the test layout change, Spinel `b3cf642` still reports the same
7 passes and 1 `respond_to?` failure through `rake test:spinel`.
Locally, running this runner through Bundler 2.6.9 on Ruby 4.0.2 also adds
duplicate-constant warnings to the Ruby subprocess output, causing parity
failures; the plain `rake test:spinel` command avoids those Bundler warnings.
