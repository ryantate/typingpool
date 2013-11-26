#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'

class TestTpConfig < Typingpool::Test::Script

def test_abort_with_invalid_file
  exception = assert_raises(Typingpool::Error::Shell) do
    tp_config(File.join(fixtures_dir, 'not_yaml.txt'))
  end
  assert_match(/not valid yaml/i, exception.message)
end

def test_abort_with_directory_path
  dir = File.join(fixtures_dir, 'vcr')
  assert(File.exists? dir)
  assert(File.directory? dir)
  exception = assert_raises(Typingpool::Error::Shell) do
    tp_config(dir)
  end
  assert_match(/not a file/i, exception.message)
end

def test_abort_with_invalid_path
  path = '/jksdljs/euwiroeuw'
  refute(File.exists? path)
  exception = assert_raises(Typingpool::Error::Shell) do
    tp_config(path)
  end
  assert_match(/valid path/i, exception.message)
end

def test_usage_message
  out, err = tp_config('--help')
  assert(out)
  assert_match(/\bUSAGE:/, out)
end

def test_new_config_creation
  in_temp_dir do |dir|
    path = {
      :config => File.join(dir, 'config.yml'),
      :transcript_dir => File.join(dir, 'transcriptionz')
    }
    path.values.each{|path| refute(File.exists? path) }
    assert(output = tp_config_with_input([path[:config], '--test'], ['keykey', 'secretsecret', path[:transcript_dir]]))
    assert_match(/wrote config to/i, output[:err])
    path.values.each{|path| assert(File.exists? path) }
    assert(File.file? path[:config] )
    assert(File.directory? path[:transcript_dir] )
    assert(config = Typingpool::Config.file(path[:config]))
    assert_equal(path[:transcript_dir], config.transcripts)
    assert_equal(File.join(path[:transcript_dir], 'templates').downcase, config.templates.downcase)
    assert_equal('keykey', config.amazon.key)
    assert_equal('secretsecret', config.amazon.secret)
    refute_empty(config.amazon.bucket.to_s)
  end #in_temp_dir do |dir|
end

def test_config_editing
  in_temp_dir do |dir|
    path = {
      :config => File.join(dir, 'config.yml'),
      :fixture => File.join(fixtures_dir, 'config-1'),
      :transcript_dir => File.join(dir, 'transcriptionz')
    }
    assert(File.exists? path[:fixture])
    refute(File.exists? path[:config])
    FileUtils.cp(path[:fixture], path[:config])
    assert(File.exists? path[:config])
    assert(original_config = Typingpool::Config.file(path[:config]))
    [:key, :secret, :bucket].each{|param| refute_empty(original_config.amazon.send(param).to_s) }
    [:transcripts, :templates, :cache].each{|param| refute_empty(original_config.send(param).to_s) } 
    assert(output = tp_config_with_input([path[:config], '--test'], ['keykey', 'secretsecret', path[:transcript_dir]]))
    assert(edited_config = Typingpool::Config.file(path[:config]))
    [:key, :secret].each{|param| refute_equal(original_config.amazon.send(param), edited_config.amazon.send(param)) }
    assert_equal(original_config.amazon.bucket, edited_config.amazon.bucket)
    [:templates, :cache].each{|param| assert_equal(original_config.send(param), edited_config.send(param)) }
    refute_equal(original_config.transcripts, edited_config.transcripts)
    assert_equal('keykey', edited_config.amazon.key)
    assert_equal('secretsecret', edited_config.amazon.secret)
    assert_equal(path[:transcript_dir], edited_config.transcripts)
  end #in_temp_dir |dir| do
end

def test_skips_bucket_when_sftp_params_exist
  in_temp_dir do |dir|
    path = {
      :config => File.join(dir, 'config.yml'),
      :fixture => File.join(fixtures_dir, 'config-2'),
      :transcript_dir => File.join(dir, 'transcriptionz')
    }
    assert(File.exists? path[:fixture])
    refute(File.exists? path[:config])
    FileUtils.cp(path[:fixture], path[:config])
    assert(File.exists? path[:config])
    assert(original_config = Typingpool::Config.file(path[:config]))
    assert_empty(original_config.amazon.bucket.to_s)
    assert(output = tp_config_with_input([path[:config], '--test'], ['keykey', 'secretsecret', path[:transcript_dir]]))
    assert_match(/wrote config to/i, output[:err])
    assert(edited_config = Typingpool::Config.file(path[:config]))
    assert_empty(edited_config.amazon.bucket.to_s)
  end #in_temp_dir do |dir|
end

end #class TestTpConfig
