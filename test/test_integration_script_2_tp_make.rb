#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(File.dirname($0)), 'lib')

require 'typingpool'
require 'typingpool/test'
require 'csv'

class TestTpMake < Typingpool::Test::Script                   
  def test_abort_with_no_files
    assert_tp_make_abort_match(['--title', 'Foo', '--chunks', '0:20'], /no files/i)
  end

  def test_abort_with_no_title
    assert_tp_make_abort_match(['--file', audio_files[0]], /no title/i)
  end

  def test_abort_with_invalid_title
    assert_tp_make_abort_match(['--file', audio_files[0], '--title', 'Foo/Bar'], /illegal character/i)
  end

  def test_abort_with_no_args
    assert_tp_make_abort_match([], /\bUSAGE:/)
  end

  def assert_tp_make_abort_match(args, regex)
    assert_script_abort_match(args, regex) do |args|
      call_tp_make(*args)
    end
  end

  def tp_make_with(dir, config_path, subdir='mp3')
    begin
      tp_make(dir, config_path, subdir)
      assert(project = temp_tp_dir_project(dir, Typingpool::Config.file(config_path)))
      assert_not_nil(project.local)
      assert_not_nil(project.local.id)
      assert(project.local.subdir('audio','chunks').to_a.size <= 7)
      assert(project.local.subdir('audio','chunks').to_a.size >= 6)
      assert_equal(project_default[:subtitle], project.local.subtitle)
      assignments = project.local.file('data', 'assignment.csv').as(:csv)
      assert_equal(project.local.subdir('audio','chunks').to_a.size, assignments.count)
      assert_all_assets_have_upload_status(assignments, ['audio'], 'yes')
      sleep 4 #pause before checking URLs so remote server has time to fully upload
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
        end #project_default[:voice].each_with_index...
      end #assignments.each d0....
    ensure
      tp_finish_outside_sandbox(dir, config_path)
    end #begin
    assert_all_assets_have_upload_status(assignments, ['audio'], 'no')
  end

  def test_tp_make
    Dir.entries(audio_dir).select{|entry| File.directory?(File.join(audio_dir, entry))}.reject{|entry| entry.match(/^\./) }.each do |subdir|
      in_temp_tp_dir do |dir|
        config_path = self.config_path(dir)
        skip_if_no_upload_credentials('tp-make integration test', Typingpool::Config.file(config_path))
        tp_make_with(dir, config_path, subdir)
      end #in_temp_tp_dir
    end #Dir.entries
  end

  def test_tp_make_s3
    in_temp_tp_dir do |dir|
      skip_if_no_s3_credentials('tp-make S3 integration test', config)
      config_path = setup_s3_config(dir)
      tp_make_with(dir, config_path)
    end #in_temp_tp_dir do...
  end 

  def test_fixing_failed_tp_make
    in_temp_tp_dir do |dir|
      config = config_from_dir(dir)
      skip_if_no_s3_credentials('tp-make failed upload integration test', config)
      good_config_path = setup_s3_config(dir)
      bad_config_path = setup_s3_config_with_bad_password(dir)
      assert_raises(Typingpool::Error::Shell) do
        tp_make(dir, bad_config_path, 'mp3')
      end
      project_dir = temp_tp_dir_project_dir(dir)
      assert(File.exists? project_dir)
      assert(File.directory? project_dir)
      assert(File.exists? File.join(project_dir, 'data', 'assignment.csv'))
      originals_dir = File.join(project_dir, 'audio', 'originals')
      refute_empty(Dir.entries(originals_dir).reject{|entry| entry.match(/^\./) }.map{|entry| File.join(originals_dir, entry) }.select{|path| File.file? path })
      assert(project = temp_tp_dir_project(dir))
      assert(assignment_csv = project.local.file('data', 'assignment.csv').as(:csv))
      refute_empty(assignment_csv.to_a)
      assert_all_assets_have_upload_status(assignment_csv, ['audio'], 'maybe')
      assert(audio_urls = assignment_csv.map{|assignment| assignment['audio_url'] })
      refute_empty(audio_urls)
      assert_empty(audio_urls.select{|url| working_url? url })
      begin
        tp_make(dir, good_config_path, 'mp3')
        refute_empty(assignment_csv.read)
        assert_all_assets_have_upload_status(assignment_csv, ['audio'], 'yes')
        refute_empty(audio_urls2 = assignment_csv.map{|assignment| assignment['audio_url'] })
        audio_urls.each_with_index do |original_url, i|
          assert_equal(original_url, audio_urls2[i])
        end
        sleep 4 #pause before checking URLs so remote server has time to fully upload
        assert_equal(audio_urls.count, audio_urls2.select{|url| working_url? url }.count)
      ensure
        tp_finish_outside_sandbox(dir, good_config_path)
      end #begin
      assert_all_assets_have_upload_status(assignment_csv, ['audio'], 'no')
    end #in_temp_tp_dir do...
  end

end #TestTpMake
