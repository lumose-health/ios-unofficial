#!/usr/bin/env ruby
require 'json'
require 'fileutils'
require 'open3'

root = Dir.pwd
fixture = '.build/sarif-gate-test'
FileUtils.rm_rf(fixture)
FileUtils.mkdir_p("#{fixture}/Sources")
File.write("#{fixture}/Sources/Seen.swift", '')
File.write("#{fixture}/tracked.txt", "Sources/Seen.swift\n")
evaluator = File.join(root, 'scripts/lib/sarif_gate.rb')
notification = {'descriptor' => {'id' => 'swift/diagnostics/successfully-extracted-files'}, 'locations' => [{'physicalLocation' => {'artifactLocation' => {'uri' => 'Sources/Seen.swift'}}}]}
base = {'runs' => [{'tool' => {'driver' => {'rules' => []}}, 'invocations' => [{'toolExecutionNotifications' => [notification]}], 'results' => []}]}

def check(label, expected, needle, evaluator, fixture, document, exclusion = nil)
  File.write("#{fixture}/case.sarif", JSON.generate(document)) unless document == :missing || document == :empty || document == :invalid
  File.write("#{fixture}/case.sarif", '') if document == :empty
  File.write("#{fixture}/case.sarif", '{') if document == :invalid
  FileUtils.rm_f("#{fixture}/case.sarif") if document == :missing
  if exclusion
    File.write("#{fixture}/exclusions.txt", exclusion)
  else
    FileUtils.rm_f("#{fixture}/exclusions.txt")
  end
  output, status = Open3.capture2e('ruby', evaluator, "#{fixture}/case.sarif", "#{fixture}/exclusions.txt", "#{fixture}/tracked.txt")
  raise "#{label}: #{output}" unless status.success? == expected && output.include?(needle)
  puts "self-test: sarif-#{label}: #{expected ? 'pass' : 'fail'}"
end

def result(id, level = nil)
  value = {'ruleId' => id, 'message' => {'text' => 'finding'}, 'locations' => [{'physicalLocation' => {'artifactLocation' => {'uri' => 'Sources/Seen.swift'}, 'region' => {'startLine' => 9}}}]}
  value['level'] = level if level
  value
end

def copy(value)
  Marshal.load(Marshal.dump(value))
end

check('clean', true, '1 extracted, 0 blocking, 0 warnings', evaluator, fixture, base)
doc = copy(base); doc['runs'][0]['results'] = [result('error', 'error')]
check('error', false, 'error Sources/Seen.swift:9 finding', evaluator, fixture, doc)
doc = copy(base); doc['runs'][0]['tool']['driver']['rules'] = [{'id' => 'high', 'properties' => {'security-severity' => '7.0'}}]; doc['runs'][0]['results'] = [result('high', 'warning')]
check('severity-seven', false, '1 blocking', evaluator, fixture, doc)
doc['runs'][0]['tool']['driver']['rules'][0]['properties']['security-severity'] = '6.9'
check('severity-six-nine', true, '1 warnings', evaluator, fixture, doc)
doc = copy(base); doc['runs'][0]['results'] = [result('note', 'note')]
check('note', true, '0 warnings', evaluator, fixture, doc)
doc = copy(base); doc['runs'][0]['tool']['driver']['rules'] = [{'id' => 'default', 'defaultConfiguration' => {'level' => 'error'}}]; doc['runs'][0]['results'] = [result('default')]
check('default-level', false, '1 blocking', evaluator, fixture, doc)
doc = copy(base); doc['runs'][0]['tool']['extensions'] = [{'rules' => [{'id' => 'extension', 'properties' => {'security-severity' => '8.0'}}]}]; doc['runs'][0]['results'] = [result('extension')]
check('extension-rule', false, '1 blocking', evaluator, fixture, doc)
check('missing', false, 'SARIF missing', evaluator, fixture, :missing)
check('empty', false, 'SARIF empty', evaluator, fixture, :empty)
check('invalid-json', false, 'SARIF invalid JSON', evaluator, fixture, :invalid)
check('no-runs', false, 'SARIF has no runs', evaluator, fixture, {'runs' => []})
doc = copy(base); doc['runs'][0]['invocations'] = []
check('zero-extracted', false, 'zero analyzed files', evaluator, fixture, doc)
doc = copy(base); File.write("#{fixture}/tracked.txt", "Sources/Seen.swift\nSources/Other.swift\n")
check('unextracted', true, 'Tracked Swift files not extracted: Sources/Other.swift', evaluator, fixture, doc)
File.write("#{fixture}/tracked.txt", "Sources/Seen.swift\n")
doc = copy(base); doc['runs'][0]['results'] = [result('error', 'error')]
doc['runs'][0]['results'][0]['locations'][0]['physicalLocation']['artifactLocation']['uri'] = "#{fixture}/Sources/Seen.swift"
check('excluded', true, '0 blocking', evaluator, fixture, doc, "#{fixture}/Sources/Seen.swift # test fixture\n")
check('glob-exclusion', false, 'glob or basename', evaluator, fixture, doc, 'Sources/*.swift # broad')
check('basename-exclusion', false, 'glob or basename', evaluator, fixture, doc, 'Seen.swift # broad')
check('reasonless-exclusion', false, 'reason required', evaluator, fixture, doc, 'Sources/Seen.swift #')
check('absent-exclusion', false, 'path does not exist', evaluator, fixture, doc, 'Sources/Absent.swift # reason')
