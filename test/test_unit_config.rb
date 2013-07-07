#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'

class TestConfig < Typingpool::Test

  def test_config_regular_file
    assert(config = Typingpool::Config.file(File.join(fixtures_dir, 'config-1')))
    assert_equal('~/Documents/Transcripts/', config['transcripts'])
    assert_match(/Transcripts$/, config.transcripts)
    refute_match(/~/, config.transcripts)
    %w(key secret).each do |param| 
      regex = /test101010/
      assert_match(regex, config.amazon.send(param)) 
      assert_match(regex, config.amazon[param])
      assert_match(regex, config.amazon.to_hash[param])
    end
    assert_equal(0.75, config.assign.reward.to_f)
    assert_equal(3*60*60, config.assign.deadline.to_i)
    assert_equal('3h', config.assign['deadline'])
    assert_equal(60*60*24*2, config.assign.lifetime.to_i)
    assert_equal('2d', config.assign['lifetime'])
    assert_equal(3, config.assign.keywords.count)
    assert_kind_of(Typingpool::Config::Root::Assign::Qualification, config.assign.qualify.first)
    assert_equal(:approval_rate, config.assign.qualify.first.to_arg[0])
    assert_equal(:gte, config.assign.qualify.first.to_arg[1].keys.first)
    assert_equal('95', config.assign.qualify.first.to_arg[1].values.first.to_s)
  end

  def test_config_sftp
    assert(config = Typingpool::Config.file(File.join(fixtures_dir, 'config-2')))
    assert_equal('ryan', config.sftp.user)
    assert_equal('public_html/transfer/', config.sftp['path'])
    assert_equal('public_html/transfer', config.sftp.path)
    assert_equal('http://example.com/mturk/', config.sftp['url'])
    assert_equal('http://example.com/mturk', config.sftp.url)
  end

  def test_config_screwy_file
    assert(config = Typingpool::Config.file(File.join(fixtures_dir, 'config-2')))

    exception = assert_raises(Typingpool::Error::Argument) do 
      config.assign.qualify
    end
    assert_match(/Unknown qualification type/i, exception.message)

    config.assign['qualify'] = [config.assign['qualify'].pop]
    exception = assert_raises(Typingpool::Error::Argument) do 
      config.assign.qualify
    end
    assert_match(/Unknown comparator/i, exception.message)

    assert_equal('3z', config.assign['deadline'])
    exception = assert_raises(Typingpool::Error::Argument::Format) do
      config.assign.deadline
    end
    assert_match(/can't convert/i, exception.message)

    config.assign['reward'] = 'foo'
    exception = assert_raises(Typingpool::Error::Argument::Format) do
      config.assign.reward
    end
    assert_match(/\bformat should\b/i, exception.message)
  end

  def test_config_regular_input
    assert(config = Typingpool::Config.file(File.join(fixtures_dir, 'config-1')))
    new_reward = '0.80'
    refute_equal(config.assign.reward, new_reward)
    assert(config.assign.reward = new_reward)
    assert_equal(new_reward, config.assign.reward)
    
    new_time = '11d'
    refute_equal(new_time, config.assign.approval)
    assert(config.assign.approval = new_time)
    assert_equal(950400, config.assign.approval)
  end

  def test_config_screwy_input
    exception = assert_raises(Typingpool::Error::Argument::Format) do
      config.assign.reward = 'foo'
    end
    assert_match(/\bformat should\b/i, exception.message)

    exception = assert_raises(Typingpool::Error::Argument::Format) do
      config.assign.approval = '11f'
    end
    assert_match(/can't convert/i, exception.message)

  end
end #TestConfig
