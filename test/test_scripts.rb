#!/usr/bin/env ruby

require 'test/unit'


def MiniTest.filter_backtrace(bt)
  bt
end

class TestScripts < Test::Unit::TestCase
  require 'set'
  require 'net/http'

  def self.app_dir
    File.join(File.dirname(__FILE__), '..')
  end

  $:.unshift File.join(self.app_dir, 'lib')

  require 'audibleturk'
  require 'tmpdir'
  require 'yaml'

  def template_dir
    File.join(self.class.app_dir, 'templates', 'test')
  end

  def audio_dir
    File.join(template_dir, 'audio')
  end

  def audio_files(subdir='mp3')
    dir = File.join(audio_dir, subdir)
    Dir.entries(dir).reject{|entry| entry.match(/^\./) }.map{|entry| File.join(dir, entry)}.select{|path| File.file?(path) }
  end

  def in_temp_tp_dir
    Dir.mktmpdir('typingpool_') do |dir|
      make_temp_tp_dir_config(dir)
      FileUtils.cp_r(File.join(template_dir, 'projects'), dir)
      yield(dir)
    end
  end

  def project_default
    Hash[
             :config_filename => '.config',
             :subtitle => 'Typingpool test interview transcription',
             :title => 'TestTpInterview',
             :chunks => '0:20',
             :unusual => ['Hack Day', 'Sunnyvale', 'Chad D'],
             :voice => ['Ryan', 'Havi, hacker']
            ]
  end

  def make_temp_tp_dir_config(dir, config=Audibleturk::Config.file)
    config.param['local'] = File.join(dir, 'projects')
    config.param['cache'] = File.join(dir, '.cache')
    config.param['app'] = self.class.app_dir
    File.open(File.join(dir, project_default[:config_filename]), 'w') do |out|
      out << YAML.dump(config.param)
    end
  end

  def working_url?(url, max_redirects=6)
    response = nil
    seen = Set.new
    loop do
      url = URI.parse(url)
      break if seen.include? url.to_s
      break if seen.size > max_redirects
      seen.add(url.to_s)
      response = Net::HTTP.new(url.host, url.port).request_head(url.path)
      if response.kind_of?(Net::HTTPRedirection)
        url = response['location']
      else
        break
      end
    end
    response.kind_of?(Net::HTTPSuccess) && url.to_s
  end

  class TestTpMake < TestScripts

    def path_to_tp_make
      File.join(self.class.app_dir, 'bin', 'make.rb')
    end
 
    def test_abort_with_no_files
      assert_raise(Audibleturk::Error::Shell) do
        Audibleturk::Utility.system_quietly(path_to_tp_make, '--title', 'Foo', '--chunks', '0:20')
      end
    end

    def test_abort_with_no_title
      assert_raise(Audibleturk::Error::Shell) do
        Audibleturk::Utility.system_quietly(path_to_tp_make, '--file', audio_files[0])
      end
    end

    def test_tp_make
      Dir.entries(audio_dir).select{|entry| File.directory?(File.join(audio_dir, entry))}.reject{|entry| entry.match(/^\./) }.each do |subdir|
        assert_nothing_raised do
          in_temp_tp_dir do |dir|
            config_path = File.join(dir, project_default[:config_filename])
            Audibleturk::Utility.system_quietly(
                                                path_to_tp_make, 
                                                '--config', config_path, 
                                                '--chunks', project_default[:chunks],
                                                *[:title, :subtitle].map{|param| ["--#{param}", project_default[param]] }.flatten,
                                                *[:voice, :unusual].map{|param| project_default[param].map{|value| ["--#{param}", value] }.flatten }.flatten,
                                                *audio_files(subdir).map{|path| ['--file', path]}.flatten
                                                )
            project = nil
            assert_nothing_raised do
              project = Audibleturk::Project.new(project_default[:title], Audibleturk::Config.file(config_path))
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
              assert(working_url?(assignment['url']))
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
          end
        end
      end
    end

  end #TestTpMake
end
