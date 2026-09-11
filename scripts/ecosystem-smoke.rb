#!/usr/bin/env ruby
# Isolated LLM fixtures plus native system readings; owns only its child processes.
require 'json'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'digest'

root = File.expand_path('..', __dir__)
duration = Integer(ENV.fetch('CATS_TEST_SECONDS', '12'))
raise 'CATS_TEST_SECONDS must be 6..600' unless (6..600).cover?(duration)
with_ui = ARGV.include?('--ui')
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
sample = lambda do |pid|
  text, status = Open3.capture2('/bin/ps', '-p', pid.to_s, '-o', 'time=', '-o', 'rss=')
  raise "Child #{pid} exited" unless status.success?
  time, rss = text.split
  cpu = time.split(':').map(&:to_f).reduce(0) { |sum, part| sum * 60 + part }
  {cpu: cpu, rss_kib: rss.to_i}
end
Dir.mktmpdir('cats-ecosystem-') do |directory|
  llm = File.join(directory, 'llm')
  metrics = File.join(directory, 'metrics')
  FileUtils.mkdir_p([llm, metrics, File.join(directory, 'claude'), File.join(directory, 'codex')])
  FileUtils.cp(File.join(root, 'crates/cats-llm/tests/fixtures/codex.jsonl'), File.join(directory, 'codex', 'fixture.jsonl'))
  llm_config = File.join(directory, 'llm.toml')
  metrics_config = File.join(directory, 'metrics.toml')
  File.write(llm_config, "theme = 'nord'\nclaude-dir = #{File.join(directory, 'claude').to_json}\ncodex-dir = #{File.join(directory, 'codex').to_json}\n")
  File.write(metrics_config, "theme = 'nord'\n")
  llm_binary = File.join(root, 'target/release/cats-llm')
  metrics_binary = File.join(root, 'target/release/cats-metrics')
  out, status = Open3.capture2e(llm_binary, '--config', llm_config, '--data-dir', llm, '--once')
  raise out unless status.success?
  llm_digest = Digest::SHA256.file(File.join(llm, 'state.json')).hexdigest
  children = {}
  begin
    children[:metrics_collector] = Process.spawn(metrics_binary, '--config', metrics_config, '--data-dir', metrics, out: File::NULL, err: File.join(directory, 'metrics.log'))
    deadline = clock.call + 10
    until File.exist?(File.join(metrics, 'heartbeat'))
      raise 'Metrics failed to start' if clock.call > deadline
      sleep 0.1
    end
    _, status = Open3.capture2e(metrics_binary, '--config', metrics_config, '--data-dir', metrics, '--once')
    raise 'Duplicate writer was allowed' if status.success?
    if with_ui
      [['LLM', llm, 'CatsLLM'], ['METRICS', metrics, 'CatsMetrics']].each do |name, data, app|
        env = {"CATS_#{name}_DATA_DIR" => data, "CATS_#{name}_EXTERNAL_COLLECTOR" => '1'}
        children["#{name.downcase}_ui"] = Process.spawn(env, File.join(root, "build/Build/Products/Release/#{app}.app/Contents/MacOS/#{app}"), out: File::NULL, err: File.join(directory, "#{name}.log"))
      end
    end
    sleep 3
    first = children.transform_values { |pid| sample.call(pid) }
    peaks = first.transform_values { |value| value[:rss_kib] }
    changes = 0
    previous = nil
    started = clock.call
    while clock.call - started < duration
      bytes = File.read(File.join(metrics, 'state.json'))
      state = JSON.parse(bytes)
      raise 'Unbounded history' if state.fetch('history').length > 60
      changes += 1 if previous && previous != bytes
      previous = bytes
      children.each { |name, pid| peaks[name] = [peaks[name], sample.call(pid)[:rss_kib]].max }
      sleep 2
    end
    elapsed = clock.call - started
    raise 'Metrics did not refresh' if changes < 2
    raise 'Metrics changed LLM state' unless Digest::SHA256.file(File.join(llm, 'state.json')).hexdigest == llm_digest
    raise 'Metrics created a database' if Dir.children(metrics).any? { |name| name.include?('sqlite') }
    report = {platform: `uname -sm`.strip, release: true, duration_seconds: elapsed, ui: with_ui, snapshot_changes: changes,
      processes: children.to_h { |name, pid| [name, {cpu_percent_one_core: (sample.call(pid)[:cpu] - first[name][:cpu]) / elapsed * 100, peak_rss_mib: peaks[name] / 1024.0}] }}
    FileUtils.mkdir_p(File.join(root, 'build'))
    File.write(File.join(root, 'build/ecosystem-report.json'), JSON.pretty_generate(report))
    puts JSON.pretty_generate(report)
  ensure
    children.each_value do |pid|
      begin
        Process.kill('TERM', pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
      end
    end
  end
end
