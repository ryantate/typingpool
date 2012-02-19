#!/usr/bin/env ruby

require 'test/unit'

class TestScripts < Test::Unit::TestCase
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

  def audio_files
    Dir.entries(audio_dir).map{|entry| File.join(audio_dir, entry)}.select{|path| File.file?(path) }
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
      assert_nothing_raised do
        in_temp_tp_dir do |dir|
          Audibleturk::Utility.system_quietly(
                                              path_to_tp_make, 
                                              '--config', File.join(dir, project_default[:config_filename]), 
                                              *[:title, :subtitle].map{|param| ["--#{param}", project_default[param]] }.flatten,
                                              *[:voice, :unusual].map{|param| project_default[param].map{|value| ["--#{param}", value] }.flatten }.flatten,
                                              *audio_files.map{|path| ['--file', path]}.flatten
                                              )
        end
      end
    end
  end #TestTpMake
end
