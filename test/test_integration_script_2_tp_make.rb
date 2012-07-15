#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/test'
require 'csv'

class TestTpMake < Typingpool::Test::Script                   
  def test_abort_with_no_files
    exception = assert_raise(Typingpool::Error::Shell) do
      call_tp_make('--title', 'Foo', '--chunks', '0:20')
    end
    assert_match(exception.message, /no files/i)
  end

  def test_abort_with_no_title
    exception = assert_raise(Typingpool::Error::Shell) do
      call_tp_make('--file', audio_files[0])
    end
    assert_match(exception.message, /no title/i)
  end

  def test_abort_with_invalid_title
    exception = assert_raise(Typingpool::Error::Shell) do
      call_tp_make('--file', audio_files[0], '--title', 'Foo/Bar')
    end #assert_raise
    assert_match(exception.message, /invalid title/i)
  end

  def test_abort_with_no_args
    exception = assert_raise(Typingpool::Error::Shell) do
      call_tp_make
    end
    assert_match(exception.message, /\bUSAGE:/)
  end

  def tp_make_with(dir, config_path, subdir='mp3')
    project = nil
    assert_nothing_raised do
      tp_make(dir, config_path, subdir)
      assert_nothing_raised do
        project = temp_tp_dir_project(dir, Typingpool::Config.file(config_path))
      end
      assert_not_nil(project.local)
      assert_not_nil(project.local.id)
      assert_equal(7, project.local.subdir('audio','chunks').to_a.size)
      assert_equal(project_default[:subtitle], project.local.subtitle)
      assignments = nil
      assert_nothing_raised do 
        assignments = project.local.csv('data', 'assignment.csv').read
      end
      assert_equal(project.local.subdir('audio','chunks').to_a.size, assignments.size)
      assignments.each do |assignment|
        assert_not_nil(assignment['audio_url'])
        assert(working_url? assignment['audio_url'])
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
        skip_if_no_upload_credentials('tp-make integration test', Typingpool::Config.file(config_path))
        tp_make_with(dir, config_path, subdir)
        tp_finish(dir, config_path)
      end #in_temp_tp_dir
    end #Dir.entries
  end

  def test_tp_make_s3
    in_temp_tp_dir do |dir|
      config = config_from_dir(dir)
      config.to_hash.delete('sftp')
      config_path = write_config(config, dir, '.config_s3')
      skip_if_no_s3_credentials('tp-make S3 integration test', config)
      tp_make_with(dir, config_path)
      tp_finish(dir, config_path)
    end #in_temp_tp_dir do...
  end 

  def test_fixing_failed_tp_make
    in_temp_tp_dir do |dir|
      config = config_from_dir(dir)
      config.to_hash.delete('sftp')
      skip_if_no_s3_credentials('tp-make failed upload integration test', config)
      good_config_path = write_config(config, dir, '.config_s3')
      bad_password = 'f'
      refute_equal(config.to_hash['amazon']['secret'], bad_password)
      config.to_hash['amazon']['secret'] = bad_password
      bad_config_path = write_config(config, dir, '.config_s3_bad')
      assert_raises(Typingpool::Error::Shell) do
        tp_make(dir, bad_config_path, 'mp3')
      end
      project_dir = temp_tp_dir_project_dir(dir)
      assert(File.exists? project_dir)
      assert(File.directory? project_dir)
      assert(File.exists? File.join(project_dir, 'data', 'assignment.csv'))
      originals_dir = File.join(project_dir, 'audio', 'originals')
      refute_empty(Dir.entries(originals_dir).reject{|entry| entry.match(/^\./) }.map{|entry| File.join(originals_dir, entry) }.select{|path| File.file? path })
      refute_empty(assignment_csv = File.read(File.join(project_dir, 'data', 'assignment.csv')))
      refute_empty(assignment_rows = CSV.parse(assignment_csv))
      assignment_headers = assignment_rows.shift
      assert(assignment_confirm_index = assignment_headers.find_index('audio_upload_confirmed'))
      assert_empty(assignment_rows.reject{|row| row[assignment_confirm_index].to_i == 0 })
      assert(assignment_url_index = assignment_headers.find_index('audio_url'))
      refute_empty(assignment_urls = assignment_rows.map{|row| row[assignment_url_index] })
      assert_empty(assignment_urls.select{|url| working_url? url })
      begin
        tp_make(dir, good_config_path, 'mp3')
        refute_empty(assignment_csv = File.read(File.join(project_dir, 'data', 'assignment.csv')))
        refute_empty(assignment_rows = CSV.parse(assignment_csv))
        assignment_rows.shift
        assert_empty(assignment_rows.reject{|row| row[assignment_confirm_index].to_i == 1 })
        refute_empty(assignment_urls2 = assignment_rows.map{|row| row[assignment_url_index] })
        assignment_urls.each_with_index do |original_url, i|
          assert_equal(original_url, assignment_urls2[i])
        end
        assert_empty(assignment_urls2.reject{|url| working_url? url })
      ensure
        tp_finish(dir, good_config_path)
      end #begin
    end #in_temp_tp_dir do...
  end

end #TestTpMake
