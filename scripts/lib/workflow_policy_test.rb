#!/usr/bin/env ruby
require 'tmpdir'
require 'fileutils'
require_relative 'workflow_policy'

module PolicyTest
  def self.check(label, expected, errors)
    raise "#{label}: expected #{expected.inspect}, got #{errors.inspect}" unless errors.any? { |error| error.include?(expected) }
    puts "self-test: #{label}: fail"
  end

  def self.copy_fixture(dir)
    target = File.join(dir, 'workflows')
    FileUtils.cp_r('.github/workflows', target)
    target
  end

  def self.mutate(dir, file, label, expected)
    target = copy_fixture(dir)
    path = File.join(target, file)
    doc = YAML.safe_load(File.read(path), aliases: false)
    yield doc
    File.write(path, YAML.dump(doc))
    check(label, expected, WorkflowPolicy.policy(target))
    FileUtils.rm_rf(target)
  end

  def self.run
    Dir.mktmpdir('ci-policy-') do |dir|
      target = copy_fixture(dir)
      raise 'clean policy fixture failed' unless WorkflowPolicy.policy(target).empty?
      puts 'self-test: clean-policy: pass'
      FileUtils.rm_rf(target)
      mutate(dir, 'static-analysis.yml', 'missing-roster', 'Static Analysis Gate: expected exactly one') { |doc| doc['jobs'].clear }
      mutate(dir, 'static-analysis.yml', 'duplicate-roster', 'Static Analysis Gate: expected exactly one') { |doc| doc['jobs']['copy'] = doc['jobs']['static-analysis'].dup }
      mutate(dir, 'static-analysis.yml', 'required-continue-on-error', 'continue-on-error forbidden') { |doc| doc['jobs']['static-analysis']['continue-on-error'] = true }
      mutate(dir, 'static-analysis.yml', 'unconditional-if', 'unconditional check has if or needs') { |doc| doc['jobs']['static-analysis']['if'] = 'always()' }
      mutate(dir, 'dependency-scan.yml', 'aggregation-if', 'requires if: always()') { |doc| doc['jobs']['dependency-gate']['if'] = 'success()' }
      mutate(dir, 'dependency-scan.yml', 'aggregation-needs', 'requires detect and work needs') { |doc| doc['jobs']['dependency-gate']['needs'] = ['osv'] }
      mutate(dir, 'dependency-scan.yml', 'aggregation-run', 'missing gate-verdict step') { |doc| doc['jobs']['dependency-gate']['steps'].last['run'] = 'echo pass' }
      mutate(dir, 'dependency-scan.yml', 'aggregation-env', 'missing WORK_RESULT env') { |doc| doc['jobs']['dependency-gate']['steps'].last['env'].delete('WORK_RESULT') }
      mutate(dir, 'dependency-scan.yml', 'run-needs', 'needs. in run') { |doc| doc['jobs']['dependency-gate']['steps'].last['run'] += ' # needs.osv.result' }
      mutate(dir, 'static-analysis.yml', 'missing-timeout', 'missing timeout-minutes') { |doc| doc['jobs']['static-analysis'].delete('timeout-minutes') }
      mutate(dir, 'static-analysis.yml', 'missing-concurrency', 'missing concurrency group with github.ref') { |doc| doc.delete('concurrency') }
      mutate(dir, 'static-analysis.yml', 'bad-concurrency', 'missing concurrency group with github.ref') { |doc| doc['concurrency']['group'] = 'static' }
      mutate(dir, 'static-analysis.yml', 'pull-paths', 'pull_request path filter forbidden') { |doc| doc[true]['pull_request'] = { 'paths' => ['Sources/**'] } }
      mutate(dir, 'static-analysis.yml', 'pull-ignore', 'pull_request path filter forbidden') { |doc| doc[true]['pull_request'] = { 'paths-ignore' => ['docs/**'] } }
      mutate(dir, 'static-analysis.yml', 'workflow-permissions', 'workflow permissions must be contents: read') { |doc| doc['permissions'] = { 'contents' => 'write' } }
      mutate(dir, 'static-analysis.yml', 'job-permissions', 'invalid job permissions') { |doc| doc['jobs']['static-analysis']['permissions'] = { 'contents' => 'write' } }
      mutate(dir, 'static-analysis.yml', 'secrets', 'secrets reference forbidden') { |doc| doc['jobs']['static-analysis']['env'] = { 'BAD' => '${{ secrets.TOKEN }}' } }
      mutate(dir, 'static-analysis.yml', 'pull-request-target', 'pull_request_target forbidden') { |doc| doc[true]['pull_request_target'] = nil }
      mutate(dir, 'static-analysis.yml', 'checkout-credentials', 'checkout needs persist-credentials: false') { |doc| doc['jobs']['static-analysis']['steps'][0]['with'].delete('persist-credentials') }
      target = copy_fixture(dir)
      file = File.join(target, 'static-analysis.yml')
      File.write(file, File.read(file).sub('on:', '"on":'))
      raise 'quoted on fixture failed' unless WorkflowPolicy.policy(target).empty?
      puts 'self-test: quoted-on: pass'
      FileUtils.rm_rf(target)
      target = copy_fixture(dir)
      backstop_file = File.join(target, 'unsafe.yml')
      File.write(backstop_file, "on:\n  pull_request_target:\njobs:\n  unsafe:\n    steps:\n      - uses: actions/checkout@#{'a' * 40}\n        with:\n          ref: \\${{ github.event.pull_request.head.sha }}\n")
      check('backstop-head', 'pull_request_target checkout of PR head forbidden', WorkflowPolicy.backstop(target))
      File.write(backstop_file, File.read(backstop_file).sub('github.event.pull_request.head.sha', 'github.sha'))
      raise 'clean backstop fixture failed' unless WorkflowPolicy.backstop(target).empty?
      puts 'self-test: backstop-clean: pass'
      File.write(backstop_file, "on: [pull_request_target]\njobs:\n  unsafe:\n    steps:\n      - uses: actions/checkout@#{'a' * 40}\n        with:\n          repository: \\${{ github.event.pull_request.head.repo.full_name }}\n")
      check('backstop-list-trigger', 'pull_request_target checkout of PR head forbidden', WorkflowPolicy.backstop(target))
      FileUtils.rm_rf(target)
      docs = File.join(dir, 'ci-checks.md')
      File.write(docs, "<!-- required-checks:begin -->\n" + WorkflowPolicy::ROSTER.map { |name| "- #{name}\n" }.join + "<!-- required-checks:end -->\n")
      rules = File.join(dir, 'rules.json')
      entries = WorkflowPolicy::ROSTER.map { |name| { 'context' => name, 'integration_id' => 15368 } }
      data = [{ 'type' => 'required_status_checks', 'parameters' => { 'required_status_checks' => entries } }]
      File.write(rules, JSON.dump(data))
      raise 'matching rules fixture failed' unless WorkflowPolicy.required_checks(docs, rules, WorkflowPolicy::ROSTER).empty?
      puts 'self-test: rules-match: pass'
      entries.pop
      File.write(rules, JSON.dump(data))
      check('rules-missing', 'do not match roster', WorkflowPolicy.required_checks(docs, rules, WorkflowPolicy::ROSTER))
      entries << { 'context' => 'extra', 'integration_id' => 15368 }
      File.write(rules, JSON.dump(data))
      check('rules-extra', 'do not match roster', WorkflowPolicy.required_checks(docs, rules, WorkflowPolicy::ROSTER))
      entries.pop
      entries << { 'context' => 'iOS Gate', 'integration_id' => 42 }
      File.write(rules, JSON.dump(data))
      check('rules-integration', 'integration_id must be 15368', WorkflowPolicy.required_checks(docs, rules, WorkflowPolicy::ROSTER))
      File.write(rules, '[]')
      check('rules-absent-rule', 'do not match roster', WorkflowPolicy.required_checks(docs, rules, WorkflowPolicy::ROSTER))
      File.write(docs, File.read(docs).sub('- iOS Gate', '- Wrong Gate'))
      check('docs-drift', 'roster drift', WorkflowPolicy.required_checks(docs, rules, WorkflowPolicy::ROSTER))
      File.write(rules, '{')
      check('rules-invalid-json', 'required-checks:', WorkflowPolicy.required_checks(docs, rules, WorkflowPolicy::ROSTER))
    end
  end
end

PolicyTest.run
