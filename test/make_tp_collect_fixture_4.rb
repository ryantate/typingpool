#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool/test'
require 'fileutils'

class CollectProjectFixtureGen4 < Typingpool::Test::Script
  def test_populate_fixture3
    fixture_path = File.join(fixtures_dir, 'vcr', 'tp-collect-3')
    tp_collect_with_fixture(tp_collect_fixture_project_dir, fixture_path)
    assert(File.exists?("#{fixture_path}.yml"))
    tp_finish(tp_collect_fixture_project_dir)
    remove_tp_collect_fixture_project_dir
    add_goodbye_message("Third and final tp-collect recorded. Fixtures for tp-collect testing successfully generated in #{File.dirname(fixture_path)}!")
  end
end
