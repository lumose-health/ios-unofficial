#!/usr/bin/env ruby
require 'yaml'
require 'json'
require 'net/http'
require 'uri'

module WorkflowPolicy
  ROSTER = ['Static Analysis Gate', 'Dependency Scan Gate', 'Workflow Lint', 'Workflow Security', 'iOS Gate'].freeze
  AGGREGATE = ['Dependency Scan Gate', 'iOS Gate'].freeze
  NEEDS = { 'Dependency Scan Gate' => ['detect-dependencies', 'osv'], 'iOS Gate' => ['detect-changes', 'build'] }.freeze
  # Gates that pass only when every listed job succeeded. The listed jobs run
  # unconditionally, so a skipped result is never expected and fails the gate.
  ALL_OF = { 'Static Analysis Gate' => ['guards', 'codeql'] }.freeze
  # A shell or working-directory override in a roster workflow changes how
  # every gate command runs. Each allowed override is listed here by
  # 'file:location' (as the policy error prints it) with a non-empty reason.
  SHELL_OVERRIDES = {}.freeze
  SOURCE = { 'Static Analysis Gate' => 'static-analysis.yml', 'Dependency Scan Gate' => 'dependency-scan.yml', 'Workflow Lint' => 'workflow-lint.yml', 'Workflow Security' => 'workflow-security.yml', 'iOS Gate' => 'ios.yml' }.freeze

  def self.load_yaml(file, errors)
    YAML.safe_load(File.read(file), aliases: false) || {}
  rescue StandardError => e
    errors << "#{file}: #{e.message}"
    {}
  end

  # A bare `on:` key parses as the boolean true under YAML 1.1. Triggers may be
  # a single event name, a list of names, or a map; normalize to a map.
  def self.triggers(doc)
    trigger = doc.key?('on') ? doc['on'] : doc[true]
    case trigger
    when Hash then trigger
    when String then { trigger => nil }
    when Array then trigger.each_with_object({}) { |name, map| map[name.to_s] = nil }
    else {}
    end
  end

  def self.walk(node, &block)
    yield node
    case node
    when Hash then node.each_value { |value| walk(value, &block) }
    when Array then node.each { |value| walk(value, &block) }
    end
  end

  def self.needs_of(job)
    needs = job.is_a?(Hash) ? job['needs'] : nil
    needs.is_a?(Array) ? needs.map(&:to_s) : (needs ? [needs.to_s] : [])
  end

  # Every job a roster job depends on, directly or through other jobs.
  def self.upstream(jobs, id)
    seen = []
    queue = needs_of(jobs[id])
    until queue.empty?
      dep = queue.shift
      next if seen.include?(dep)
      seen << dep
      queue.concat(needs_of(jobs[dep]))
    end
    seen
  end

  def self.shell_overrides(file, doc, allow, errors)
    locations = []
    locations << ['defaults', doc['defaults']]
    (doc['jobs'] || {}).each do |id, job|
      next unless job.is_a?(Hash)
      locations << ["#{id}.defaults", job['defaults']]
      (job['steps'] || []).each_with_index do |step, index|
        locations << ["#{id}.steps[#{index}]", { 'run' => step }] if step.is_a?(Hash)
      end
    end
    locations.each do |location, defaults|
      run = defaults.is_a?(Hash) ? defaults['run'] : nil
      next unless run.is_a?(Hash) && (run.key?('shell') || run.key?('working-directory'))
      key = "#{File.basename(file)}:#{location}"
      next unless allow[key].to_s.strip.empty?
      errors << "#{key}: shell or working-directory override needs an allowlisted reason"
    end
  end

  def self.policy(dir, allow = SHELL_OVERRIDES)
    errors = []
    found = Hash.new { |hash, key| hash[key] = [] }
    files = Dir.glob(File.join(dir, '*.{yml,yaml}')).sort
    errors << "#{dir}: no workflows" if files.empty?
    files.each do |file|
      doc = load_yaml(file, errors)
      next unless doc.is_a?(Hash)
      trigger = triggers(doc)
      pr = trigger.key?('pull_request')
      group = doc['concurrency'].is_a?(Hash) ? doc['concurrency']['group'] : nil
      errors << "#{file}: missing concurrency group with github.ref" unless group.to_s.include?('github.ref')
      if pr
        errors << "#{file}: pull_request_target forbidden" if trigger.key?('pull_request_target')
        config = trigger['pull_request']
        errors << "#{file}: pull_request path filter forbidden" if config.is_a?(Hash) && (config.key?('paths') || config.key?('paths-ignore'))
        errors << "#{file}: workflow permissions must be contents: read" unless doc['permissions'] == { 'contents' => 'read' }
        walk(doc) { |node| errors << "#{file}: secrets reference forbidden" if node.is_a?(String) && node.include?('secrets.') }
      end
      jobs = doc['jobs']
      unless jobs.is_a?(Hash)
        errors << "#{file}: missing jobs"
        next
      end
      shell_overrides(file, doc, allow, errors) if SOURCE.value?(File.basename(file))
      jobs.each do |id, job|
        next unless job.is_a?(Hash)
        name = job['name']
        found[name] << "#{file}:#{id}" if ROSTER.include?(name)
        errors << "#{file}:#{id}: missing timeout-minutes" unless job.key?('timeout-minutes')
        if pr && job.key?('permissions')
          allowed = { 'contents' => 'read' }
          allowed['pull-requests'] = 'read' if name.to_s.start_with?('Detect ')
          errors << "#{file}:#{id}: invalid job permissions" unless job['permissions'].is_a?(Hash) && job['permissions'].all? { |key, value| allowed[key] == value } && job['permissions']['contents'] == 'read'
        end
        (job['steps'] || []).each do |step|
          next unless step.is_a?(Hash)
          if step['uses'].to_s.start_with?('actions/checkout@') && step.dig('with', 'persist-credentials') != false
            errors << "#{file}:#{id}: checkout needs persist-credentials: false"
          end
        end
        next unless ROSTER.include?(name)
        errors << "#{file}:#{id}: wrong workflow for #{name}" unless File.basename(file) == SOURCE[name]
        errors << "#{file}:#{id}: pull_request trigger missing" unless pr
        errors << "#{file}:#{id}: continue-on-error forbidden" if job.key?('continue-on-error')
        ([id] + upstream(jobs, id)).each do |dep|
          upstream_job = jobs[dep]
          unless upstream_job.is_a?(Hash)
            errors << "#{file}:#{id}: needs unknown job #{dep}"
            next
          end
          errors << "#{file}:#{dep}: continue-on-error forbidden on a job #{name} needs" if dep != id && upstream_job.key?('continue-on-error')
          (upstream_job['steps'] || []).each_with_index do |step, index|
            errors << "#{file}:#{dep}: continue-on-error forbidden on step #{index}" if step.is_a?(Hash) && step.key?('continue-on-error')
          end
        end
        if AGGREGATE.include?(name)
          value = job['if'].to_s.gsub(/\A\$\{\{\s*|\s*\}\}\z/, '').strip
          errors << "#{file}:#{id}: requires if: always()" unless value == 'always()'
          needs = job['needs']
          errors << "#{file}:#{id}: requires detect and work needs" unless needs.is_a?(Array) && needs.sort == NEEDS[name].sort
          verdict = (job['steps'] || []).find { |step| step.is_a?(Hash) && step['run'].to_s.strip == 'bash scripts/ci-local.sh gate-verdict' }
          errors << "#{file}:#{id}: missing gate-verdict step" unless verdict
          if verdict
            errors << "#{file}:#{id}: gate-verdict step must not have if" if verdict.key?('if')
            env = verdict['env'] || {}
            %w[DETECT_RESULT SHOULD_BUILD WORK_RESULT EVENT_NAME GATE_NAME].each { |key| errors << "#{file}:#{id}: missing #{key} env" unless env.key?(key) }
          end
          walk(job['steps'] || []) { |node| errors << "#{file}:#{id}: needs. in run" if node.is_a?(Hash) && node['run'].to_s.include?('needs.') }
        elsif ALL_OF.key?(name)
          expected = ALL_OF[name]
          value = job['if'].to_s.gsub(/\A\$\{\{\s*|\s*\}\}\z/, '').strip
          errors << "#{file}:#{id}: requires if: always()" unless value == 'always()'
          needs = job['needs']
          errors << "#{file}:#{id}: requires needs #{expected.join(', ')}" unless needs.is_a?(Array) && needs.map(&:to_s).sort == expected.sort
          expected.each do |dep|
            errors << "#{file}:#{dep}: job #{name} needs must not have if" if jobs[dep].is_a?(Hash) && jobs[dep].key?('if')
          end
          verdict = (job['steps'] || []).find { |step| step.is_a?(Hash) && step['run'].to_s.strip == 'bash scripts/ci-local.sh needs-verdict' }
          errors << "#{file}:#{id}: missing needs-verdict step" unless verdict
          if verdict
            errors << "#{file}:#{id}: needs-verdict step must not have if" if verdict.key?('if')
            results = (verdict['env'] || {})['NEEDS_RESULTS'].to_s.strip.gsub(/\s+/, ' ')
            wanted = expected.map { |dep| "#{dep}=${{ needs.#{dep}.result }}" }
            errors << "#{file}:#{id}: NEEDS_RESULTS must be #{wanted.join(' ')}" unless results == wanted.join(' ')
          end
          walk(job['steps'] || []) { |node| errors << "#{file}:#{id}: needs. in run" if node.is_a?(Hash) && node['run'].to_s.include?('needs.') }
        else
          errors << "#{file}:#{id}: unconditional check has if or needs" if job.key?('if') || job.key?('needs')
          errors << "#{file}:#{id}: pull_request trigger missing" unless pr
        end
      end
    end
    ROSTER.each { |name| errors << "#{name}: expected exactly one job, found #{found[name].length}" unless found[name].length == 1 }
    errors
  end

  def self.backstop(dir)
    errors = []
    Dir.glob(File.join(dir, '*.{yml,yaml}')).sort.each do |file|
      doc = load_yaml(file, errors)
      next unless doc.is_a?(Hash)
      trigger = triggers(doc)
      next unless trigger.key?('pull_request_target')
      walk(doc['jobs'] || {}) do |node|
        next unless node.is_a?(Hash) && node['uses'].to_s.start_with?('actions/checkout@')
        values = node['with'] || {}
        if %w[ref repository].any? { |key| values[key].to_s.include?('github.event.pull_request.head') }
          errors << "#{file}: pull_request_target checkout of PR head forbidden"
        end
      end
    end
    errors
  end

  def self.rules_json(path)
    return JSON.parse(File.read(path)) if path
    repository = ENV.fetch('GITHUB_REPOSITORY', 'lumose-health/ios-unofficial')
    uri = URI("https://api.github.com/repos/#{repository}/rules/branches/develop")
    request = Net::HTTP::Get.new(uri)
    request['Accept'] = 'application/vnd.github+json'
    request['Authorization'] = "Bearer #{ENV['GH_TOKEN']}" if ENV['GH_TOKEN'] && !ENV['GH_TOKEN'].empty?
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |http| http.request(request) }
    raise "rules API HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  def self.roster_doc(docs, roster)
    match = File.read(docs).match(/<!-- required-checks:begin -->(.*?)<!-- required-checks:end -->/m)
    published = match ? match[1].scan(/^\s*-\s+`?(.+?)`?\s*$/).flatten : []
    published == roster ? [] : ["#{docs}: required-checks roster drift"]
  rescue StandardError => e
    ["required-checks: #{e.message}"]
  end

  def self.required_checks(docs, rules_path, roster)
    roster_doc(docs, roster) + ruleset(rules_path, roster)
  end

  def self.ruleset(rules_path, roster)
    errors = []
    rules = rules_json(rules_path)
    raise 'rules JSON must be an array' unless rules.is_a?(Array)
    contexts = []
    rules.each do |rule|
      next unless rule.is_a?(Hash) && rule['type'] == 'required_status_checks'
      checks = (rule['parameters'] || {})['required_status_checks'] || []
      checks.each do |check|
        contexts << check['context']
        errors << "#{check['context']}: integration_id must be 15368" if check.key?('integration_id') && check['integration_id'].to_s != '15368'
      end
    end
    errors << 'required status checks do not match roster' unless contexts.sort == roster.sort && contexts.length == roster.length
    errors
  rescue StandardError => e
    errors << "required-checks: #{e.message}"
    errors
  end
end

if $PROGRAM_NAME == __FILE__
  command = ARGV.shift
  errors = case command
           when 'policy' then WorkflowPolicy.policy(ARGV.fetch(0, '.github/workflows'))
           when 'backstop' then WorkflowPolicy.backstop(ARGV.fetch(0, '.github/workflows'))
           when 'required-checks' then WorkflowPolicy.required_checks(ARGV.fetch(0), ARGV[1].to_s.empty? ? nil : ARGV[1], ARGV.drop(2))
           when 'roster-doc' then WorkflowPolicy.roster_doc(ARGV.fetch(0), ARGV.drop(1))
           when 'ruleset' then WorkflowPolicy.ruleset(ARGV[0].to_s.empty? ? nil : ARGV[0], ARGV.drop(1))
           else ["unknown workflow policy command: #{command}"]
           end
  errors.each { |error| warn "ci-local: #{error}" }
  exit(errors.empty? ? 0 : 1)
end
