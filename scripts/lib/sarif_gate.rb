#!/usr/bin/env ruby
require 'json'
require 'uri'

def fail_gate(message)
  warn "codeql: #{message}"
  exit 1
end

def source_path(uri)
  return '' unless uri.is_a?(String)
  path = uri.start_with?('file://') ? URI::DEFAULT_PARSER.unescape(URI.parse(uri).path) : URI::DEFAULT_PARSER.unescape(uri)
  path = path.sub(%r{\A#{Regexp.escape(Dir.pwd)}/}, '')
  path.sub(%r{\A\./}, '')
rescue URI::InvalidURIError
  ''
end

def location_for(item)
  place = (item['locations'] || []).first || {}
  physical = place['physicalLocation'] || {}
  [source_path((physical['artifactLocation'] || {})['uri']), (physical['region'] || {})['startLine'] || 1]
end

sarif_file, exclusions_file, tracked_file = ARGV
fail_gate('expected SARIF, exclusions and tracked-file arguments') unless ARGV.length == 3
fail_gate("SARIF missing: #{sarif_file}") unless File.file?(sarif_file)
fail_gate("SARIF empty: #{sarif_file}") if File.zero?(sarif_file)
begin
  document = JSON.parse(File.read(sarif_file))
rescue JSON::ParserError
  fail_gate("SARIF invalid JSON: #{sarif_file}")
end
runs = document.is_a?(Hash) ? document['runs'] : nil
fail_gate('SARIF has no runs') unless runs.is_a?(Array) && !runs.empty?
fail_gate("tracked Swift list missing: #{tracked_file}") unless File.file?(tracked_file)

exclusions = []
if File.exist?(exclusions_file)
  File.readlines(exclusions_file).each_with_index do |line, index|
    entry = line.strip
    next if entry.empty? || entry.start_with?('#')
    match = /\A([^#]+?)\s+#\s*(\S.*)\z/.match(entry)
    fail_gate("invalid exclusion at line #{index + 1}: reason required") unless match
    path = match[1].strip
    fail_gate("invalid exclusion at line #{index + 1}: glob or basename") if path.match?(/[\*\?\[]/) || !path.include?('/')
    fail_gate("invalid exclusion at line #{index + 1}: path must be repo-relative") if path.start_with?('/') || path.split('/').include?('..')
    fail_gate("invalid exclusion at line #{index + 1}: path does not exist: #{path}") unless File.file?(path)
    exclusions << path
  end
end

extracted = []
blocking = 0
warnings = 0
runs.each do |run|
  fail_gate('SARIF run is invalid') unless run.is_a?(Hash)
  tool = run['tool'] || {}
  components = [tool['driver'] || {}] + (tool['extensions'] || [])
  (run['invocations'] || []).each do |invocation|
    (invocation['toolExecutionNotifications'] || []).each do |notification|
      next unless (notification['descriptor'] || {})['id'] == 'swift/diagnostics/successfully-extracted-files'
      path, = location_for(notification)
      extracted << path if path.start_with?('Sources/', 'Apps/')
    end
  end
  (run['results'] || []).each do |result|
    id = result['ruleId'] || (result['rule'] || {})['id'] || 'unknown-rule'
    component_index = ((result['rule'] || {})['toolComponent'] || {})['index']
    search = component_index.is_a?(Integer) ? [components[component_index + 1]].compact : components
    rule = search.map { |component| (component['rules'] || []).find { |candidate| candidate['id'] == id } }.compact.first || {}
    level = result['level'] || (rule['defaultConfiguration'] || {})['level'] || 'warning'
    severity = (rule['properties'] || {})['security-severity']
    severity = Float(severity) rescue nil
    next if level == 'note'
    path, line = location_for(result)
    next if exclusions.include?(path)
    message = (result['message'] || {})['text'] || ''
    output = "#{id} #{path}:#{line} #{message.gsub(/\s+/, ' ').strip}"
    if level == 'error' || (severity && severity >= 7.0)
      blocking += 1
      warn output
    elsif level == 'warning'
      warnings += 1
      warn output
    end
  end
end
extracted.uniq!
fail_gate('zero analyzed files under Sources/ or Apps/') if extracted.empty?
tracked = File.readlines(tracked_file).map(&:strip).select { |path| path.end_with?('.swift') && path.start_with?('Sources/', 'Apps/') }
missing = tracked.uniq - extracted
puts "::warning::Tracked Swift files not extracted: #{missing.join(', ')}" unless missing.empty?
puts "codeql: #{extracted.length} extracted, #{blocking} blocking, #{warnings} warnings"
exit(blocking.zero? ? 0 : 1)
