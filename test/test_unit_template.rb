#!/usr/bin/env ruby

$LOAD_PATH.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'minitest/autorun'
require 'typingpool'
require 'typingpool/test'
require 'fileutils'

class TestTemplate < Typingpool::Test
  def test_template_base
    assert(template1 = Typingpool::Template.new('template', [fixtures_dir]))
    has_template_in_fixtures_dir_test(template1)
    assert(template2 = Typingpool::Template.new('template.html.erb', [fixtures_dir]))
    has_template_in_fixtures_dir_test(template2)
    signature = 'ffffffffff'
    assert_match(/#{signature}/, template1.render({:title => signature}))
    refute_match(/#{signature}/, template1.read)
    assert_match(/<h1><%= title/i, template1.read)
    in_temp_dir do |dir1|
      assert(template = Typingpool::Template.new('template', [dir1, fixtures_dir]))
      assert(template.look_in.detect{|path| path == dir1})
      has_template_in_fixtures_dir_test(template)
      in_temp_dir do |dir2|
        copy_template_fixture_into(dir2, '-2') do |path|
          assert(template = Typingpool::Template.new('template', [dir1, dir2, fixtures_dir]))
          assert_equal(path, template.full_path)
          assert_match(/#{signature}/, template.render({:title => signature}))
          refute_match(/#{signature}/, template.read)
          assert_match(/<h2><%= title/i, template.read)
        end #copy_template_fixture_into do...
      end #in_temp_dir do |dir2|
    end #in_temp_dir do |dir1|
  end

  def test_template_from_config
    in_temp_dir do |dir1|
      in_temp_dir do |dir2|
        copy_template_fixture_into(dir2, '-2') do |path|
          config = dummy_config
          config.templates = dir2
          assert(template = Typingpool::Template.from_config('template', config))
          assert_equal(path, template.full_path)
          assert_match(/<h2><%= title/i, template.read)
          config.templates = dir1
          exception = assert_raises(Typingpool::Error) do 
            template = Typingpool::Template.from_config('template', config)
          end #assert_raises() do...
          assert_match(/could not find/i, exception.message)
        end #copy_template_into do...
      end #in_temp_dir do |dir2|
    end #in_temp_dir do |dir1|
  end

  def test_template_assignment
    in_temp_dir do |dir|
      copy_template_fixture_into(dir) do |path|
        assignment_subdir = File.join(dir, 'assignment')
        FileUtils.mkdir(assignment_subdir)
        copy_template_fixture_into(assignment_subdir, '-2') do |assignment_path|
          config = dummy_config
          config.templates = dir
          assert(template = Typingpool::Template::Assignment.from_config('template', config))
          assert_equal(assignment_path, template.full_path)
          assert_match(/<h2><%= title/i, template.read)
        end #copy_template_fixture_into(assignment_subdir) do...
      end #copy_template_fixture_into(dir, '') do...
    end #in_temp_dir do...
  end

  def test_template_env
    assert(template = Typingpool::Template.new('template-3', [fixtures_dir]))
    signatures = [('g' * 9), ('h' * 11)]
    assert(rendered = template.render(:title => signatures[0], :new_title => signatures[1]))
    assert_match(/<h1><%= title/i, rendered)
    assert_match(/<h1>#{signatures[0]}/i, rendered)
    assert_match(/<h1>#{signatures[1]}/i, rendered)
    in_temp_dir do |dir|
      copy_template_fixture_into(dir) do |template_path|
        subdir = File.join(dir, 'closer')
        FileUtils.mkdir(subdir)
        copy_template_fixture_into(subdir, '-2') do |closer_template_oath|
          FileUtils.cp(File.join(fixtures_dir, 'template-3.html.erb'), subdir)
          FileUtils.cp(File.join(fixtures_dir, 'template-2.html.erb'), subdir)
          look_in = [dir, subdir]
          assert(template = Typingpool::Template.new('template', look_in))
          assert_match(/<h1><%= title/i, template.read)
          refute_match(/<h2><%= title/i, template.read)
          assert(calling_template = Typingpool::Template.new('template-3', look_in))
          assert(rendered = calling_template.render(:title => signatures[0], :new_title => signatures[1]))
          assert_match(/<h2>/, rendered)
          refute_match(/<h1>/, rendered)
        end #copy_template_fixture_into do...
      end #copy_template_fixture_into do...
    end #in_temp_dir do...
  end

  def copy_template_fixture_into(dir, which_fixture='')
    dest = File.join(dir, 'template.html.erb')
    FileUtils.cp(File.join(fixtures_dir, "template#{which_fixture}.html.erb"), dest)
    begin
      yield(dest)
    ensure
      File.delete(dest)
    end #begin
  end

  def has_template_in_fixtures_dir_test(template)
    assert_equal(File.join(fixtures_dir, 'template.html.erb'), template.full_path)
  end

end #TestTemplate
