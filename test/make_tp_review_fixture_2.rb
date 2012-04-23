#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool/test'
require 'fileutils'

class ReviewProjectFixtureGen2 < Typingpool::Test::Script
  def test_populate_fixture
    fixture_path = File.join(fixtures_dir, 'vcr', 'tp-review-1')
    dir = fixture_project_dir('tp_review_project_temp')
    output = nil
    assert_nothing_raised do
      output = tp_review_with_fixture(dir, fixture_path, %w(a r a r s q ))
    end
    assert_equal(0, output[:status].to_i, "Bad exit code: #{output[:status]} err: #{output[:err]}")
    assert(File.exists?("#{fixture_path}.yml"))

    fixture_path = File.join(fixtures_dir, 'vcr', 'tp-review-2')
    assert_nothing_raised do
      output = tp_review_with_fixture(dir, fixture_path, %w(a r))
    end
    assert_equal(0, output[:status].to_i, "Bad exit code: #{output[:status]} err: #{output[:err]}")
    assert(File.exists?("#{fixture_path}.yml"))

    tp_finish(dir)
    remove_fixture_project_dir('tp_review_project_temp')
    add_goodbye_message("All done!")
  end
end
