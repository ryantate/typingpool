#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'
require 'set'

class TestTest < Typingpool::Test::Script

  def test_readymade_project
    with_temp_transcripts_dir do |dir|
      tp_make(dir, config_path(dir), 'mp3', true)
      assert_is_proper_tp_dir(dir)
      assert_has_proper_assignment_csv(dir)
    end
    with_temp_readymade_project do |dir|
      assert_is_proper_tp_dir(dir)
      assert_has_proper_assignment_csv(dir)
    end
    with_temp_readymade_project do |dir|
      with_temp_readymade_project do |dir2|
        projects = [transcripts_dir_project(dir), transcripts_dir_project(dir2)]
        refute_equal(projects[0].local.id, projects[1].local.id)
        ['audio_url', 'project_id'].each do |csv_param|
          param_set = projects.map{|project| Set.new project.local.file('data', 'assignment.csv').as(:csv).select{|a| a[csv_param] } }
          assert_empty(param_set[0].intersection(param_set[1]))
        end #['audio_url', 'project_id'].each do...
      end #with_temp_readymade_project do...
    end #with_temp_readymade_project do...
  end

  def assert_is_proper_tp_dir(dir)
    assert(project = transcripts_dir_project(dir))
    assert(project.local)
    assert(File.exists? project.local)
    assert(File.directory? project.local)
    assert_equal(3, project.local.subdir('audio', 'originals').files.count)
    assert_equal(6, project.local.subdir('audio', 'chunks').files.count)
  end

  def assert_has_proper_assignment_csv(dir)
    assert(project = transcripts_dir_project(dir))
    assert(File.exists? project.local.file('data', 'assignment.csv').path)
    assert(assignments = project.local.file('data', 'assignment.csv').as(:csv).read)
    assert_equal(project.local.subdir('audio', 'chunks').files.count, assignments.count)
    assert_equal(assignments.count, assignments.select{|a| a['audio_url']}.count)
    assignments.each{|a| assert_match(/^https?:\/\/\w+/i, a['audio_url']) }
  end

end #class TestTest
