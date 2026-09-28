# frozen_string_literal: true

# Deliberately small adapter for the RawSource proof of concept. Unsupported
# assertions must fail visibly; this is not a replacement for Minitest.
module Minitest
  class Assertion < StandardError; end

  class Test
    def setup; end
    def teardown; end

    def assert(value, message = "Expected a truthy value")
      raise Assertion, message unless value
      true
    end

    def assert_equal(expected, actual)
      raise Assertion, "Expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
      true
    end

    def assert_respond_to(object, method_name)
      raise Assertion, "Expected response to #{method_name}" unless object.respond_to?(method_name)
      true
    end
  end
end
