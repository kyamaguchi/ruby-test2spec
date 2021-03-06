#!/usr/bin/env ruby

data = $stdin.read

data.gsub! /require 'test_helper'/, 'require \'spec_helper\''

data.gsub! /class (.*)Test < ActiveSupport::TestCase/, 'describe \1 do'

while(m = data.match /(^\s+)should(_not)?_(belong_to|have_one|have_many|allow_mass_assignment_of|validate_presence_of) (:.+)/)
  replace = []
  m[4].split(/,\s+/).each do |key|
    replace.push "#{m[1]}it { should#{m[2]} #{m[3]} #{key} }"
  end
  data.gsub! m[0], replace.join("\n")
end

data.gsub! /setup do/, 'before :each do'
data.gsub! /setup \{(.*)\}/, 'before(:each) {\1}'

#TODO automatically convert assert @xxx.verb? to @xxx.should be_verb
data.gsub! /assert !([^\s\.]+)\.(\w+)\?/, '\1.should_not be_\2'
data.gsub! /assert ([^\s\.]+)\.(\w+)\?/, '\1.should be_\2'
data.gsub! /assert_false ([^\s\.]+)\.(\w+)\?/, '\1.should_not be_\2'
data.gsub! /assert_equal false, ([^\s\.]+)\.(\w+)\?/, '\1.should_not be_\2'
#TODO automatically convert assert !@xxx.verb? to @xxx.should_not be_verb

#data.gsub! /assert_equal ([^,]+), (.*)/, '(\2).should == \1'
data.gsub! /assert_equal ((?:\[.*?\]|\(.*?\)|[^,\(\[])+), (.+)/, '\2.should == \1'

data.gsub! /assert(_not)?_nil (.*)/, '\2.should\1 be_nil'

data.gsub! /assert !(.*)/, '\1.should be_false'
data.gsub! /assert (.*)/, '\1.should be_true'

data.gsub! /(\s+)should "/, '\1it "should '

# Deal with Mocha -> Rspec Mocks
data.gsub! /\.expects\(/, '.should_receive('
data.gsub! /\.returns\(/, '.and_return('
data.gsub! /\.stubs\(/, '.stub('

puts data
