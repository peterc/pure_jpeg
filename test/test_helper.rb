# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.start
rescue LoadError
  # simplecov not available
end

require "minitest/autorun"
require_relative "shared_helper"
