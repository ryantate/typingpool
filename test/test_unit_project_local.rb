#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'

class TestProjectLocal < Typingpool::Test
  def test_project_local_ours
    assert(File.exists?(non_project_dir))
    assert(File.directory?(non_project_dir))
    refute(Typingpool::Project::Local.ours?(Typingpool::Filer::Dir.new(non_project_dir)))
    assert(File.exists?(project_template_dir))
    assert(Typingpool::Project::Local.ours?(Typingpool::Filer::Dir.new(project_template_dir)))
  end

  def test_project_local_named
    assert_nil(Typingpool::Project::Local.named(project_default[:title], fixtures_dir))
    assert_kind_of(Typingpool::Project::Local, local = Typingpool::Project::Local.named('project', project_template_dir_parent))
  end

  def test_project_local_valid_name
    assert(Typingpool::Project::Local.valid_name?('hello, world'))
    refute(Typingpool::Project::Local.valid_name?('hello / world'))
  end

  def test_project_local_create
    in_temp_dir do |dir|
      assert(local = create_project_local(dir))
      assert(File.exists?(local.path))
      assert(File.directory?(local.path))
      assert_kind_of(Typingpool::Project::Local, local)
      refute_nil(local.id)
    end
  end

  def test_project_instance
    in_temp_dir do |dir|
      assert(local = create_project_local(dir))
      refute_nil(local.id)
      assert_raises(Typingpool::Error) do
        local.create_id
      end
      assert_nil(local.subtitle)
      [:subtitle].each do |accessor|
        text = 'hello, world'
        assert(local.send("#{accessor.to_s}=".to_sym, text))
        assert_equal(text, local.send(accessor))
      end #[].each do...
    end #in_temp_dir do..
  end

  def create_project_local(dir)
    Typingpool::Project::Local.create(project_default[:title], dir, project_template_dir)
  end

  def project_template_dir
    File.join(project_template_dir_parent, 'project')
  end

  def project_template_dir_parent
    File.join(Typingpool::Utility.lib_dir, 'templates')
  end

  def non_project_dir
    File.join(fixtures_dir, 'vcr')
  end
end #TestProjectLocal
