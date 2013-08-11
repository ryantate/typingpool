 #!/usr/bin/env gem build 

$LOAD_PATH.unshift File.expand_path('../lib', __FILE__)
require 'typingpool/version'

Gem::Specification.new do |s|
   s.name = 'typingpool'
   s.version = Typingpool::VERSION
   s.date = Time.now.strftime("%Y-%m-%d")
   s.description = 'An app for transcribing audio using Mechanical Turk'
   s.summary = s.description
   s.authors = ['Ryan Tate']
   s.email = 'ryantate@ryantate.com'
   s.homepage = 'http://github.com/ryantate/typingpool'
   s.required_ruby_version = '>= 1.9.2'
   s.requirements = ['ffmpeg', 'mp3splt', 'mp3wrap']
   s.add_runtime_dependency('rturk', '~> 2.9')
   s.add_runtime_dependency('highline', '>= 1.6')
   s.add_runtime_dependency('nokogiri', '>= 1.5')
   s.add_runtime_dependency('aws-sdk', '~> 1.8.0')
   s.add_runtime_dependency('net-sftp', '>= 2.0.5')
   s.add_development_dependency('minitest', '~> 5.0')
   s.add_development_dependency('vcr')
   s.add_development_dependency('webmock', '>= 1.13.0')
   s.require_path = 'lib'
   s.executables = ['tp-config',
                    'tp-make',
                    'tp-assign',
                    'tp-review',
                    'tp-collect',
                    'tp-finish']
   s.test_files = ['test/test_unit_amazon.rb',
                   'test/test_unit_config.rb',
                   'test/test_unit_filer.rb',
                   'test/test_unit_project.rb',
                   'test/test_unit_project_local.rb',
                   'test/test_unit_project_remote.rb',
                   'test/test_unit_template.rb',
                   'test/test_unit_transcript.rb']
   s.bindir = 'bin'
   s.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
   s.files = `git ls-files`.split("\n")
 end
