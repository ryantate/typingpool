#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'
require 'stringio'
require 'aws-sdk'

class TestProjectRemote < Typingpool::Test
  def test_project_remote_from_config
    assert(remote = Typingpool::Project::Remote.from_config(dummy_config(1)))
    assert_instance_of(Typingpool::Project::Remote::S3, remote)
    assert(remote = Typingpool::Project::Remote.from_config(dummy_config(2)))
    assert_instance_of(Typingpool::Project::Remote::SFTP, remote)
    config = dummy_config(2)
    config.to_hash.delete('sftp')
    assert_raises(Typingpool::Error) do
      Typingpool::Project::Remote.from_config(config)
    end #assert_raises
  end

  def test_project_remote_s3_base
    config = dummy_config(1)
    assert(remote = Typingpool::Project::Remote::S3.from_config(config.amazon))
    assert_nil(config.amazon.url)
    assert_includes(remote.url, config.amazon.bucket)
    custom_url = 'http://tp.example.com/tp-test/1/2/3'
    config.amazon.url = custom_url
    assert(remote = Typingpool::Project::Remote::S3.from_config(config.amazon))
    refute_nil(remote.url)
    refute_includes(remote.url, config.amazon.bucket)
    assert_includes(remote.url, custom_url)
    assert_equal('tp.example.com', remote.host)
    assert_equal('/tp-test/1/2/3', remote.path)
    assert_includes(Typingpool::Project::Remote::S3.random_bucket_name, 'typingpool-')
    assert_equal(27, Typingpool::Project::Remote::S3.random_bucket_name.size)
    assert_equal(21,Typingpool::Project::Remote::S3.random_bucket_name(10).size)
    assert_equal(28,Typingpool::Project::Remote::S3.random_bucket_name(10, 'testing-typingpool').size)
    assert_equal(34,Typingpool::Project::Remote::S3.random_bucket_name(16, 'testing-typingpool').size)
    assert_match(/^[a-z]/, Typingpool::Project::Remote::S3.random_bucket_name(16, ''))
  end

  def vcr_opts
    {
      :preserve_exact_body_bytes => true,
      :match_requests_on => [:method, Typingpool::App.vcr_core_host_matcher]
    }
  end

  def test_project_remote_s3_networked
    assert(config = self.config)
    skip_if_no_s3_credentials('Project::Remote::S3 upload and delete tests', config)
    config.to_hash.delete('sftp')
    assert(project = Typingpool::Project.new(project_default[:title], config))
    assert_instance_of(Typingpool::Project::Remote::S3, remote = project.remote)
    with_vcr('test_unit_project_remote_s3_1', config, vcr_opts) do
      standard_put_remove_tests(remote)
    end
  end

  def test_project_remote_s3_networked_make_new_bucket_when_needed
    assert(config = self.config)
    skip_if_no_s3_credentials('Project::Remote::S3 upload and delete tests', config)
    config.to_hash.delete('sftp')
    config.amazon.bucket = Typingpool::Project::Remote::S3.random_bucket_name(16, 'typingpool-test-')
    with_vcr('test_unit_project_remote_s3_2', config, vcr_opts) do
      assert(s3 = AWS::S3.new(:access_key_id => config.amazon.key, :secret_access_key => config.amazon.secret))
      assert(works_eventually?{ not(s3.buckets[config.amazon.bucket].exists?) })
      assert(project = Typingpool::Project.new(project_default[:title], config))
      assert_instance_of(Typingpool::Project::Remote::S3, remote = project.remote)
      begin
        standard_put_remove_tests(remote)
        assert(works_eventually?{s3.buckets[config.amazon.bucket].exists?})
      ensure
        s3.buckets[config.amazon.bucket].delete rescue AWS::S3::Errors::NoSuchBucket
      end #begin
    end #with_vcr...
  end

  def test_project_remote_sftp_base
    config = dummy_config(2)
    assert(remote = Typingpool::Project::Remote::SFTP.from_config(config.sftp))
    %w(host path user url).each do |param|
      refute_nil(remote.send(param.to_sym))
      assert_equal(config.sftp.send(param.to_sym), remote.send(param.to_sym))
    end #%w().each do...
    assert_equal('example.com', remote.host)
    assert_equal('public_html/transfer', remote.path)
  end

  def test_project_remote_sftp_networked
    assert(config = self.config)
    test_name = 'Project::Remote::SFTP upload and delete tests'
    skip_if_no_sftp_credentials(test_name, config)
    skip_during_vcr_playback(test_name)
    assert(project = Typingpool::Project.new(project_default[:title], config))
    assert_instance_of(Typingpool::Project::Remote::SFTP, remote = project.remote)
    standard_put_remove_tests(remote)
  end

  def standard_put_remove_tests(remote)
    basenames = ['amazon-question-html.html', 'amazon-question-url.txt']
    local_files = basenames.map{|basename| File.join(fixtures_dir, basename) }
    local_files.each{|path| assert(File.exists? path) }
    strings = local_files.map{|path| File.read(path) }
    strings.each{|string| refute_empty(string) }


    #with default basenames
    put_remove_test(
                    :remote => remote, 
                    :streams => local_files.map{|path| File.new(path) },
                    :test_with => lambda{|urls| urls.each_with_index{|url, i| assert_includes(url, basenames[i]) } }
                    )

    #now with different basenames
    remote_basenames = basenames.map{|name| [File.basename(name, '.*'), pseudo_random_chars, File.extname(name)].join }
    base_args = {
      :remote => remote,
      :as => remote_basenames,
      :test_with => lambda{|urls| urls.each_with_index{|url, i| assert_includes(url, remote_basenames[i]) }}
    }

    put_remove_test(
                    base_args.merge(
                                    :streams => local_files.map{|path| File.new(path) },
                                    )
                    )

    #now using remove_urls for removal
    put_remove_test(
                    base_args.merge(
                                    :streams => local_files.map{|path| File.new(path) },
                                    :remove_with => lambda{|urls|  base_args[:remote].remove_urls(urls) }
                                    )
                    )

    #now with stringio streams
    put_remove_test(
                    base_args.merge( 
                                    :streams => strings.map{|string| StringIO.new(string) },
                                    )
                    )

  end

  #Uploads and then deletes streams to a remote server, running some
  #basic tests along the way, along with some optional lambdas.
  # ==== Params
  # args[:remote]      Required. A Project::Remote instance to use for
  #                    putting and removing.  
  # args[:streams]     Required. An enumerable collection of IO streams to
  #                    put and remove.
  # args[:as]          Optional. An array of basenames to use to name the
  #                    streams remotely. Default is to call
  #                    Project::Remote#put with no 'as' param.
  # args[:test_with]   Optional. Lambda to call after putting the
  #                    streams and after running the standard tests.
  # args[:remove_with] Optional. Lambda to call to remove the remote
  #                    files. Default lambda calls
  #                    args[:remote].remove(args[:as])
  # ==== Returns
  #URLs of the former remote files (non functioning/404)
  def put_remove_test(args)
    args[:remote] or raise Error::Argument, "Must supply a Project::Remote instance as :remote"
    args[:streams] or raise Error::Argument, "Must supply an array of IO streams as :streams"
    args[:remove_with] ||= lambda do |urls| 
      args[:remote].remove(urls.map{|url| Typingpool::Utility.url_basename(url) })
    end #lambda do...
    put_args = [args[:streams]]
    put_args.push(args[:as]) if args[:as]
    assert(urls = args[:remote].put(*put_args))
    begin
      assert_equal(args[:streams].count, urls.count)
      urls.each{|url| assert(working_url_eventually?(url)) }
      args[:test_with].call(urls) if args[:test_with]
    ensure
      args[:remove_with].call(urls)
    end #begin
    urls.each{|url| assert(broken_url_eventually?(url)) }
    urls
  end

  #Copy-pasted from Project::Remote so we don't have to make that a public method
  def pseudo_random_chars(length=6)
    (0...length).map{(65 + rand(25)).chr}.join
  end

end #TestProjectRemote
