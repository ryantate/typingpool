#!/usr/bin/env ruby

require 'audibleturk/test'
require 'fileutils'

class CollectProjectFixtureGen4 < Audibleturk::Test::Script
  def test_populate_fixture3
    fixture_path = File.join(fixtures_dir, 'vcr', 'tp-collect-3')
    tp_collect(tp_collect_fixture_project_dir, fixture_path)
    assert(File.exists?("#{fixture_path}.yml"))
    remove_tp_collect_fixture_project_dir
    add_goodbye_message("Third and final tp-collect recorded. Fixtures for tp-collect testing successfully generated in #{File.dirname(fixture_path)}!")
  end
end
