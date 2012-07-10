#!/usr/bin/env ruby

require 'rubygems'
require 'active_support'
require 'active_support/inflector'

require 'fileutils'

path_to_project = ARGV.first
if File.exists?(path_to_project)
  PROJECT_ROOT = File.expand_path(path_to_project)
  if File.exists?(File.join(PROJECT_ROOT, 'config'))
    puts "Rails project exists #{PROJECT_ROOT}"
  else
    raise "Is this Rails project? (config dir wasn't found.)"
  end
else
  raise "Please specify the path to project like $ #{$0} ../myproject/"
end

def target_dirname(item)
  dirname = File.basename(item)
  return 'models' if dirname == 'unit'
  return 'controllers' if dirname == 'functional'
  return dirname
end

def prepair_specdir(item)
  target_path = File.join(PROJECT_ROOT, 'spec', target_dirname(item))
  FileUtils.mkdir_p target_path
  target_path
end

def print_message(action, source_name, out_filepath)
  puts "#{action} #{source_name}\n#{' '*(action.length-2)}to #{out_filepath.sub(PROJECT_ROOT.chomp('/')+'/', '')}"
end

def test2rspec(src, options)
  result = []
  Array(src).each do |data|
    ### Skip blank lines
    result.push("\n") && next if data =~ /^\s*$/

    ### require statement
    data.gsub! /require(.*)test_helper'/, 'require \'spec_helper\'' # can be 'require\1spec_helper\''

    ### class definition
    data.gsub!(/class (.*)Test < ActiveSupport::TestCase/) { "describe #{$1} do\n  fixtures :all" }
    # data.gsub!(/class (.*)Test < ActiveSupport::TestCase/) { "describe #{$1} do" + (options[:fixtures] ? "\n  fixtures :#{$1.underscore.pluralize}" : '') } # For fixture for each model
    data.gsub!(/class (.*)HelperTest < ActionView::TestCase/) { "describe #{$1}Helper do" }
    data.gsub!(/class (.*)ControllerTest < ActionController::TestCase/) { "describe #{$1}Controller do\n  fixtures :all\n  render_views" }
    data.gsub!(/class (.*)Test < ActionController::IntegrationTest/) { "describe \"#{$1}\" do" + (options[:fixtures] ? "\n  fixtures :all" : '') }

    ### shoulda matchers
    while(m = data.match /(^\s+)should(_not)?[ _](belong_to|have_one|have_many|allow_mass_assignment_of|validate_presence_of|validate_uniqueness_of|respond_with|render_template) (:.+)/)
      replace = []
      m[4].split(/,\s+/).each do |key|
        replace.push "#{m[1]}it { should#{m[2]} #{m[3]} #{key} }"
      end
      data.gsub! m[0], replace.join("\n")
    end
    data.gsub! /(^\s+)should(_not)?[ _](allow_value|set_the_flash|assign_to|redirect_to)(.+)/, '\1it { should\2 \3\4 }'

    ### setup and teardown
    data.gsub! /setup do/, 'before :each do'
    data.gsub! /def setup/, 'before :each do'
    data.gsub! /setup \{(.*)\}/, 'before(:each) {\1}'
    data.gsub! /def teardown/, 'after :each do'
    data.gsub! /teardown do/, 'after :each do'
    data.gsub! /teardown \{(.*)\}/, 'after(:each) {\1}'

    ### 'test' and 'def test'
    data.gsub! /(^\s+)test /, '\1it '
    data.gsub!(/(^\s+)def test_(.*)/) { "#{$1}it \"#{$2.gsub(/_/,' ')}\" do" }

    ### assertions
    ## condition if/unless
    m = data.match(/assert.*( (?:if|unless) .*)$/)
    if m
      condition = m[1]
      data.gsub! condition, ''
    end

    # Controllers
    data.gsub! /assert_response :(\w+)/, 'response.should be_\1'
    data.gsub! /assert_redirected_to (.+)/, 'response.should redirect_to(\1)'
    data.gsub! /assert_template (.+)/, 'response.should render_template(\1)'
    data.gsub! /assert_routing (.+),\s*\{(.+)\}/, '{ :get => \1 }.should route_to(\2)'

    data.gsub!(/assert_select (.+),\s*(\/[^\/]+\/)/) { text = $2 ; "page.should have_xpath(\"//#{$1.gsub(/^['"]/,'').gsub(/['"]$/,'').gsub('[','[@').gsub('=','=\'').gsub(']','\']')}\", :text => #{text})" }
    data.gsub!(/assert_select (.+),\s*(\d+)/) { count = $2 ; "page.should have_xpath(\"//#{$1.gsub(/^['"]/,'').gsub(/['"]$/,'').gsub('[','[@').gsub('=','=\'').gsub(']','\']')}\", :count => #{count})" }
    data.gsub!(/assert_select (.+)/) { "page.should have_xpath(\"//#{$1.gsub(/^['"]/,'').gsub(/['"]$/,'').gsub('[','[@').gsub('=','=\'').gsub(']','\']')}\")" }

    # Others
    data.gsub! /assert_confirmation\((.+)\)/, 'page.should have_confirmation(\1).and_click_ok'

    # Capybara
    data.gsub! /assert page\.has_(\w+)\?/, 'page.should have_\1'
    #TODO automatically convert assert @xxx.verb? to @xxx.should be_verb
    data.gsub! /assert !([^\s\.]+)\.(\w+)\?/, '\1.should_not be_\2'
    data.gsub! /assert ([^\s\.]+)\.(\w+)\?/, '\1.should be_\2'
    data.gsub! /assert_false ([^\s\.]+)\.(\w+)\?/, '\1.should_not be_\2'
    data.gsub! /assert_equal false, ([^\s\.]+)\.(\w+)\?/, '\1.should_not be_\2'
    #TODO automatically convert assert !@xxx.verb? to @xxx.should_not be_verb

    data.gsub! /assert_equal ((?:\[.*?\]|\(.*?\)|[^,\(\[])+), (\S+)( (?:if|unless) .*)?/, '\2.should == \1\3'
    data.gsub! /assert_not_equal ((?:\[.*?\]|\(.*?\)|[^,\(\[])+), (\S+)( (?:if|unless) .*)?/, '\2.should_not == \1\3'
    data.gsub! /assert_match ((?:\[.*?\]|\(.*?\)|[^,\(\[])+), (\S+)( (?:if|unless) .*)?/, '\2.should match \1\3'

    data.gsub! /assert(_not)?_nil (.*)/, '\2.should\1 be_nil'

    data.gsub! /assert !(.*)/, '\1.should be_false'
    data.gsub! /assert (.*)/, '\1.should be_true'
    # Restore condition
    data.chomp!.concat(condition+"\n") if condition

    data.gsub! /(\s+)should "/, '\1it "should '
    data.gsub! /(\s+)should '/, '\1it \'should '

    # Deal with Mocha -> Rspec Mocks
    # data.gsub! /\.expects\(/, '.should_receive('
    # data.gsub! /\.returns\(/, '.and_return('
    # data.gsub! /\.stubs\(/, '.stub('
    result << data
  end
  result.join
end

def check_expression(expression, file)
  result = []
  Array(File.open(file).read).each_with_index do |data, i|
    result << "#{(i+1).to_s.rjust(4)}:#{data}" if data =~ /#{expression}/
  end
  unless result.empty?
    puts "="*30 + " #{file.to_s.gsub(%r{^.*spec/},'')} " + "="*30
    puts result.join
  end
end

def show_instruction
  puts "=== Congratulations! Tests are converted. ==="
  puts "Please check the followings."
  puts "Add gem 'rspec-rails'"
  puts "Run $ rails g rspec:install"
end

### Main
Dir.glob(File.join(PROJECT_ROOT, 'test') + "/*").each do |item|
  next if ['performance'].any?{|dir| item =~ %r{/#{dir}$} }
  if File.directory?(item)
    working_dir = prepair_specdir(item)
    Dir.glob(item + "/**/*").each do |subitem|
      options = {}
      source_name = File.basename(subitem)
      out_filepath = File.join(working_dir, subitem.gsub(item, ''))

      # Change helpers directory
      if out_filepath =~ %r{/models/helpers}
        prepair_specdir('helpers')
        out_filepath.gsub!(%r{/models/helpers}, '/helpers')
      end
      # Check fixtures
      if m = subitem.match(%r{/unit/([^/]+)_test\.rb})
        fixture_path = subitem.gsub(%r{/unit/.*$}, "/fixtures/#{m[1].pluralize}.yml")
        options[:fixtures] = true if File.exists?(fixture_path).to_s
      end
      # Add fixtures all for integration test
      options[:fixtures] = true if subitem.match(%r{/integration/([^/]+)_test\.rb})

      if source_name =~ /_test\.rb$/
        out_filepath.gsub!(%r{_test\.rb$}, '_spec.rb')
        print_message('Rewriting', source_name, out_filepath)
        data = File.open(subitem).read
        File.open(out_filepath, "w") do |dest|
          dest.write test2rspec(data, options)
        end
      else
        print_message('Copying', source_name, out_filepath)
        if File.file?(subitem)
          FileUtils.cp(subitem, out_filepath)
        elsif File.directory?(subitem)
          FileUtils.mkdir_p out_filepath
        else
          puts "Unknown type of file. Skipping #{subitem}"
        end
      end
    end
  end
end

# Check expressions
expressions = %w{
  test_helper
  class
  setup
  teardown
  test_
  should_
  assert_response
  assert_redirected_to
  assert_template
  assert_routing
  page.has_
  assert_equal
  assert_select

  assert_raises
  assert_
}
expressions.each do |expression|
  puts "#"*30 + " Checking [#{expression}] " + "#"*30
   Dir.glob(File.join(PROJECT_ROOT, 'spec') + "/**/*.rb").each do |item|
    check_expression(expression, item)
  end
end

show_instruction
