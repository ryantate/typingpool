#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/test'

class TestTpMake < Typingpool::Test::Script                   
  def test_abort_with_no_files
    assert_raise(Typingpool::Error::Shell) do
      call_tp_make('--title', 'Foo', '--chunks', '0:20')
    end
  end

  def test_abort_with_no_title
    assert_raise(Typingpool::Error::Shell) do
      call_tp_make('--file', audio_files[0])
    end
  end

  def tp_make_with(dir, config_path, subdir='mp3')
    skip_if_no_amazon_credentials('tp-make test')
    project = nil
    assert_nothing_raised do
      tp_make(dir, config_path, subdir)
      assert_nothing_raised do
        project = temp_tp_dir_project(dir, Typingpool::Config.file(config_path))
      end
      assert_not_nil(project.local)
      assert_not_nil(project.local.id)
      assert(project.local.audio_chunks.size >= 6)
      assert(project.local.audio_chunks.size <= 7)
      assert_equal(project_default[:subtitle], project.local.subtitle)
      assignments = nil
      assert_nothing_raised do 
        assignments = project.local.read_csv('assignment')
      end
      assert_equal(project.local.audio_chunks.size, assignments.size)
      assignments.each do |assignment|
        assert_not_nil(assignment['url'])
        assert(working_url? assignment['url'])
        assert_equal(assignment['project_id'], project.local.id)
        assert_equal(assignment['unusual'].split(/\s*,\s*/), project_default[:unusual])
        project_default[:voice].each_with_index do |voice, i|
          name, description = voice.split(/\s*,\s*/)
          assert_equal(name, assignment["voice#{i+1}"])
          if not(description.to_s.empty?)
            assert_equal(description, assignment["voice#{i+1}title"])
          end
        end
      end
    end #assert_nothing_raised
  end #test_tp_make

  def test_tp_make
    Dir.entries(audio_dir).select{|entry| File.directory?(File.join(audio_dir, entry))}.reject{|entry| entry.match(/^\./) }.each do |subdir|
      in_temp_tp_dir do |dir|
        config_path = self.config_path(dir)
        tp_make_with(dir, config_path, subdir)
        tp_finish(dir, config_path)
      end #in_temp_tp_dir
    end #Dir.entries
  end

  def test_tp_make_s3
    in_temp_tp_dir do |dir|
      config = config_from_dir(dir)
      config.param.delete('sftp')
      config_path = write_config(config, dir, '.config_s3')
      tp_make_with(dir, config_path)
      tp_finish(dir, config_path)
    end
  end #test_tp_make_s3
end #TestTpMake