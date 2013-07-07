#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'
require 'uri'

class TestProject < Typingpool::Test
  def test_project_base_new
    assert(project = Typingpool::Project.new(project_default[:title], dummy_config))
    assert_instance_of(Typingpool::Project, project)
    assert_equal(project_default[:title], project.name)
    assert_equal(dummy_config.to_hash.to_s, project.config.to_hash.to_s)
    assert_raises(Typingpool::Error::Argument::Format) do 
      Typingpool::Project.new('one/two', dummy_config)
    end #assert_raise...
  end

  def test_project_base_bitrate
    assert(project = Typingpool::Project.new(project_default[:title], dummy_config))
    bitrate = rand(999) + 1
    assert(project.bitrate = bitrate)
    assert_equal(bitrate, project.bitrate)
    bitrate = rand 
    assert_raises(Typingpool::Error::Argument::Format) do
      project.bitrate = bitrate
    end
  end

  def test_project_base_interval
    assert(project = Typingpool::Project.new(project_default[:title], dummy_config))
    assert(project.interval = 120)
    assert_equal(120, project.interval)
    assert_equal(1, set_and_return_interval(project, '01'))
    assert_equal(1, set_and_return_interval(project, 1))
    assert_equal("0:01", project.send(:interval_as_time_string))
    assert_equal(2, set_and_return_interval(project, 2))
    assert_equal("0:02", project.send(:interval_as_time_string))
    assert_raises(Typingpool::Error::Argument::Format) do 
      set_and_return_interval(project, 2.1)
    end
    assert_equal(11, set_and_return_interval(project,11))
    assert_equal("0:11", project.send(:interval_as_time_string))
    assert_equal(1, set_and_return_interval(project, '00:01'))
    assert_equal(60, set_and_return_interval(project, '01:00'))
    assert_equal("1:00", project.send(:interval_as_time_string))
    assert_equal(60, set_and_return_interval(project, '1:00'))
    assert_equal(3552, set_and_return_interval(project, '59:12'))
    assert_equal("59:12", project.send(:interval_as_time_string))
    assert_equal(3680, set_and_return_interval(project, '61:20'))
    assert_equal("1:01:20", project.send(:interval_as_time_string))
    assert_raises(Typingpool::Error::Argument::Format) do 
      set_and_return_interval(project, '61:20.1')
    end
    assert_equal(7152, set_and_return_interval(project, '01:59:12'))
    assert_equal("1:59:12", project.send(:interval_as_time_string))
    assert_equal(7152, set_and_return_interval(project, '1:59:12'))
    assert_raises(Typingpool::Error::Argument::Format) do 
      set_and_return_interval(project, '01:59:12.01')
    end
    assert_equal(43152, set_and_return_interval(project, '11:59:12'))
    assert_equal("11:59:12", project.send(:interval_as_time_string))
  end

  def test_project_base_interval_as_mds
    assert(project = Typingpool::Project.new(project_default[:title], dummy_config))
    assert_equal('0.1', set_and_return_interval_as_mds(project, 1))
    assert_equal('0.2', set_and_return_interval_as_mds(project, 2))
    assert_equal('0.11', set_and_return_interval_as_mds(project,11))
    assert_equal('1.0', set_and_return_interval_as_mds(project, '01:00'))
    assert_equal('59.12', set_and_return_interval_as_mds(project, '59:12'))
    assert_equal('61.20', set_and_return_interval_as_mds(project, '61:20'))
    assert_equal('119.12', set_and_return_interval_as_mds(project, '1:59:12'))
    assert_equal('719.12', set_and_return_interval_as_mds(project, '11:59:12'))
  end

  def test_project_base_local
    config = dummy_config
    config.transcripts = fixtures_dir
    assert(project = Typingpool::Project.new('project', config))
    assert_nil(project.local)
    valid_transcript_dir = File.join(Typingpool::Utility.lib_dir, 'templates')
    assert_kind_of(Typingpool::Project::Local, project.local(valid_transcript_dir))
    config.transcripts = valid_transcript_dir
    assert(project = Typingpool::Project.new('project', config))
    assert_kind_of(Typingpool::Project::Local, project.local)
  end

  def test_project_base_remote
    assert(project = Typingpool::Project.new(project_default[:title], dummy_config(1)))
    assert_instance_of(Typingpool::Project::Remote::S3, project.remote)
    assert(project = Typingpool::Project.new(project_default[:title], dummy_config(2)))
    assert_instance_of(Typingpool::Project::Remote::SFTP, project.remote)
    config = dummy_config(2)
    config.to_hash.delete('sftp')
    assert(project = Typingpool::Project.new(project_default[:title], config))
    assert_raises(Typingpool::Error) do
      project.remote
    end
  end

  def test_project_base_create_local
    config = dummy_config
    in_temp_dir do |dir|
      config.transcripts = dir
      assert(project = Typingpool::Project.new(project_default[:title], config))
      assert_nil(project.local)
      assert_kind_of(Typingpool::Project::Local, project.create_local)
      assert_kind_of(Typingpool::Project::Local, project.local)      
    end #in_temp_dir do
  end

  def test_project_base_create_assignment_csv
    config = dummy_config
    in_temp_dir do |dir|
      config.transcripts = dir
      assert(project = Typingpool::Project.new(project_default[:title], config))
      project.create_local
      assert(project.interval = '1:00')
      assert_kind_of(Typingpool::Project::Local, project.local)
      dummy_remote_files = (1..5).map{|n| "#{project_default[:title]}.#{n}" }
      relative_path = ['data', 'assignment.csv']
      voices = project_default[:voice].map do |voice|
        spec = voice.split(/,\s*/)
        hash = {:name => spec[0]}
        hash[:description] = spec[1] if spec[1]
        hash
      end
      assert(result = project.create_assignment_csv(:path => relative_path, :urls => dummy_remote_files, :unusual => project_default[:unusual], :voices => voices, ))
      assert_includes(result, dir)
      csv_file = File.join(dir, project_default[:title], *relative_path)
      assert(File.exists? csv_file)
      assert(File.file? csv_file)
      assert(parsed = CSV.read(csv_file))
      assignment_headers = parsed.shift
      assert_equal(dummy_remote_files.count, parsed.count)
      assert(chunk_index = assignment_headers.find_index('chunk'))
      assert_equal('1:00', parsed.first[chunk_index].to_s)
      assert(chunk_minutes_index = assignment_headers.find_index('chunk_minutes'))
      assert_equal(1, parsed.first[chunk_minutes_index].to_i)
      assert(chunk_seconds_index = assignment_headers.find_index('chunk_seconds'))
      assert_empty(parsed.first[chunk_seconds_index].to_s)
      assert(voices_count_index = assignment_headers.find_index('voices_count'))
      assert_equal(voices.count, parsed.first[voices_count_index].to_i)
      assert(voice_2_title_index = assignment_headers.find_index('voice2title'))
      refute_empty(parsed.first[voice_2_title_index].to_s)
    end #in_temp_dir do
  end

  def test_local_basename_from_url
    url = ['http://example.com/dir/', URI.escape('Example Title With Spaces & Ampersand.html')].join
    assert_match(/%20/, url)
#assert(basename = Typingpool::Project.local_basename_from_url.u)
  end

  def set_and_return_interval(project, interval)
    project.interval = interval
    project.interval
  end

  def set_and_return_interval_as_mds(project, interval)
    project.interval = interval
    project.interval_as_min_dot_sec
  end
end #TestProject
